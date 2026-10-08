package noxflux

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"runtime/debug"
	"sync"

	"golang.org/x/crypto/scrypt"
	"openflux/transport"
)

// sealed is OpenFlux's EncryptedTransport (transport/encrypted.go, wire format v1: "OFX", version,
// direction, 12-byte nonce, AES-256-GCM with the header as additional data, 4096-nonce replay
// window) for the client side, built from an already derived master key.
//
// OpenFlux derives that key with scrypt (N=32768, r=8), which needs 32 MB — more than a Network
// Extension can spare next to sing-box. The app derives it instead (Nox/Tunnel/Scrypt.swift) and
// passes master_key; deriveMaster is the fallback for configs that only carry the secret.
type sealed struct {
	transport.Transport
	send, recv cipher.AEAD

	mu    sync.Mutex
	seen  map[string]struct{}
	order []string
}

const (
	sealedVersion   = 1
	sealedHeader    = 5
	sealedWindow    = 4096
	clientToExit    = 0
	exitToClient    = 1
	masterKeyLength = 32
)

// deriveMaster is OpenFlux's key derivation: scrypt(secret, SHA-256(label || context)).
func deriveMaster(secret, context string) ([]byte, error) {
	salt := sha256.Sum256([]byte("OpenFlux encrypted transport v1\x00" + context))
	defer debug.FreeOSMemory()
	return scrypt.Key([]byte(secret), salt[:], 32768, 8, 1, masterKeyLength)
}

func parseMaster(text string) ([]byte, error) {
	b, err := hex.DecodeString(text)
	if err != nil || len(b) != masterKeyLength {
		return nil, errors.New("openflux: master_key must be 64 hex characters")
	}
	return b, nil
}

func directionKey(master []byte, label string) []byte {
	mac := hmac.New(sha256.New, master)
	_, _ = mac.Write([]byte("OpenFlux direction v1\x00" + label))
	return mac.Sum(nil)
}

func gcm(key []byte) (cipher.AEAD, error) {
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

func newSealed(inner transport.Transport, master []byte) (*sealed, error) {
	send, err := gcm(directionKey(master, "client-to-exit"))
	if err != nil {
		return nil, fmt.Errorf("openflux encryption: %w", err)
	}
	recv, err := gcm(directionKey(master, "exit-to-client"))
	if err != nil {
		return nil, fmt.Errorf("openflux encryption: %w", err)
	}
	return &sealed{Transport: inner, send: send, recv: recv, seen: map[string]struct{}{}}, nil
}

func (e *sealed) Send(data []byte) error {
	header := [sealedHeader]byte{'O', 'F', 'X', sealedVersion, clientToExit}
	packet := make([]byte, sealedHeader+e.send.NonceSize(), sealedHeader+e.send.NonceSize()+len(data)+e.send.Overhead())
	copy(packet, header[:])
	nonce := packet[sealedHeader:]
	if _, err := rand.Read(nonce); err != nil {
		return fmt.Errorf("openflux encryption: nonce: %w", err)
	}
	return e.Transport.Send(e.send.Seal(packet, nonce, data, header[:]))
}

func (e *sealed) Receive(callback func([]byte)) {
	e.Transport.Receive(func(packet []byte) {
		n := e.recv.NonceSize()
		if len(packet) < sealedHeader+n+e.recv.Overhead() {
			return
		}
		header := packet[:sealedHeader]
		if header[0] != 'O' || header[1] != 'F' || header[2] != 'X' || header[3] != sealedVersion || header[4] != exitToClient {
			return
		}
		nonce := packet[sealedHeader : sealedHeader+n]
		plain, err := e.recv.Open(nil, nonce, packet[sealedHeader+n:], header)
		if err != nil || !e.remember(nonce) {
			return
		}
		callback(plain)
	})
}

// remember rejects replayed packets (a bounded window, like OpenFlux).
func (e *sealed) remember(nonce []byte) bool {
	key := string(nonce)
	e.mu.Lock()
	defer e.mu.Unlock()
	if _, ok := e.seen[key]; ok {
		return false
	}
	e.seen[key] = struct{}{}
	e.order = append(e.order, key)
	if len(e.order) > sealedWindow {
		delete(e.seen, e.order[0])
		e.order = e.order[1:]
	}
	return true
}
