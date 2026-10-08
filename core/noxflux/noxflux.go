// Package noxflux runs an OpenFlux client (https://github.com/lucudar/OpenFlux) inside Nox's
// Packet Tunnel, next to sing-box.
//
// OpenFlux carries raw IPv4 packets through services that stay reachable under "whitelist"
// restrictions — Yandex.Docs, Yandex Volga, Mail.ru Docs, MAX calls, Cups.online — to an
// OpenFlux exit node. sing-box keeps the TUN, routing and DNS: its "proxy" outbound is SOCKS5 to
// 127.0.0.1:<port> served here, and every connection is opened in a small userspace TCP stack
// (gVisor, address 10.10.10.2 as exit nodes expect) whose packets go into the transport.
//
// The package is compiled into Libbox.xcframework together with sing-box
// (gomobile bind ./experimental/libbox ./experimental/noxflux), so there is one Go runtime per
// process. See tools/build_libbox.sh.
package noxflux

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"openflux/transport"
	"openflux/transport/cupsonline"
	"openflux/transport/mailru"
	"openflux/transport/oneme"
	"openflux/transport/yandex"
	"openflux/tunnel"
	"openflux/utils"
)

// openFluxVersion is the OpenFlux commit, set by tools/build_libbox.sh.
var openFluxVersion = "dev"

const (
	defaultListen = "127.0.0.1:19191"
	// OpenFlux's --url default, which becomes the encryption context when no URL is given.
	defaultKeyContext = "http://#"
)

// config is the JSON the app writes next to the sing-box config (Nox/Tunnel/OpenFluxConfig.swift).
type config struct {
	// yandex (Yandex.Docs), vyandex (Yandex Volga), mailru (Mail.ru Docs), oneme (MAX), cupsonline.
	Transport string `json:"transport"`
	// Documents / rooms, in the same order as on the exit node (--url a,b,c).
	URLs     []string `json:"urls,omitempty"`
	MaxToken string   `json:"max_token,omitempty"`
	MaxUID   string   `json:"max_uid,omitempty"`
	// batched (zstd + coalescing, OpenFlux's default) or legacy (per-packet LZ4). Must match the exit.
	Codec string `json:"codec,omitempty"`
	// Optional AES-256-GCM secret (--encryption-key-file on the exit) and its context, which is
	// the exit's --url string by default. The app sends the scrypt-derived master_key (hex)
	// instead of the secret: see sealed.go.
	Key        string `json:"key,omitempty"`
	KeyContext string `json:"key_context,omitempty"`
	MasterKey  string `json:"master_key,omitempty"`
	// SOCKS5 address for sing-box and its credentials (RFC 1929): the port is reachable by every
	// app on the device, so it is never an open proxy when a password is set.
	Listen   string `json:"listen,omitempty"`
	Username string `json:"username,omitempty"`
	Password string `json:"password,omitempty"`
	// Resolver for domain targets, reached through the tunnel over TCP.
	DNS     string `json:"dns,omitempty"`
	LogPath string `json:"log_path,omitempty"`
	Verbose bool   `json:"verbose,omitempty"`
}

var (
	mu         sync.Mutex
	active     *session
	generation int64
	logOut     = &logFile{}
	logger     = log.New(logOut, "", log.LstdFlags)
)

func logf(format string, args ...any) { logger.Printf("[nox] "+format, args...) }

// Start connects the transport and serves SOCKS5 on the configured address. Calling it again
// with the same settings keeps the running session, so sing-box reloads don't drop it; new
// settings replace it.
func Start(configJSON string) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("openflux: internal error: %v", r)
		}
	}()
	cfg, err := parse(configJSON)
	if err != nil {
		return err
	}
	inner, err := buildTransport(cfg)
	if err != nil {
		return err
	}
	return start(cfg, inner)
}

func start(cfg config, inner transport.Transport) error {
	mu.Lock()
	defer mu.Unlock()
	logOut.open(cfg.LogPath)
	utils.SetOutput(logOut)
	utils.SetDebug(cfg.Verbose)
	id := cfg.identity()
	if active != nil {
		if active.id == id {
			return nil
		}
		logf("settings changed, reconnecting")
		active.close()
		active = nil
	}
	s, err := newSession(cfg, id, inner)
	if err != nil {
		logf("start failed: %v", err)
		return err
	}
	active = s
	generation++
	return nil
}

// Generation changes every time Start opens a new session (and not when it keeps one).
func Generation() int64 {
	mu.Lock()
	defer mu.Unlock()
	return generation
}

// Stop disconnects the transport and closes the SOCKS5 listener and its connections.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	if active != nil {
		active.close()
		active = nil
		logf("stopped")
	}
}

// IsRunning reports whether a session is active (connected or reconnecting).
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return active != nil
}

// IsConnected reports whether the transport currently has a live channel to the exit node.
func IsConnected() bool {
	mu.Lock()
	s := active
	mu.Unlock()
	return s != nil && s.inner.IsConnected()
}

// WaitConnected waits up to timeoutMillis for the transport to connect.
func WaitConnected(timeoutMillis int64) bool {
	return waitConnected(time.Now().Add(time.Duration(timeoutMillis) * time.Millisecond))
}

func waitConnected(deadline time.Time) bool {
	for {
		if IsConnected() {
			return true
		}
		if !IsRunning() || time.Now().After(deadline) {
			return false
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// Probe results.
const (
	ProbeOK          = 0
	ProbeNotRunning  = 1
	ProbeNoTransport = 2 // the service channel did not come up
	ProbeExitSilent  = 3 // the channel is up, but no exit node answers on the other side
)

// Probe checks the whole path within timeoutMillis: the transport connects and the exit node
// completes a TCP handshake through it (OpenFlux exits accept the connection before dialing out).
func Probe(timeoutMillis int64) int {
	deadline := time.Now().Add(time.Duration(timeoutMillis) * time.Millisecond)
	if !waitConnected(deadline) {
		if !IsRunning() {
			return ProbeNotRunning
		}
		logf("probe: the transport did not connect in %d ms", timeoutMillis)
		return ProbeNoTransport
	}
	mu.Lock()
	s := active
	mu.Unlock()
	if s == nil {
		return ProbeNotRunning
	}
	started := time.Now()
	ctx, cancel := context.WithDeadline(context.Background(), deadline)
	defer cancel()
	c, err := s.dial(ctx, s.cfg.DNS)
	if err != nil {
		logf("probe: no answer from the exit node (%v)", err)
		return ProbeExitSilent
	}
	c.Close()
	logf("probe: the exit node answered in %s", time.Since(started).Round(time.Millisecond))
	return ProbeOK
}

// Status is a JSON snapshot: running, connected, transport, traffic, reconnects, connections.
func Status() string {
	mu.Lock()
	s := active
	mu.Unlock()
	out := map[string]any{"running": s != nil, "version": openFluxVersion}
	if s != nil {
		st := s.inner.Stats()
		out["connected"] = s.inner.IsConnected()
		out["transport"] = s.cfg.Transport
		out["bytes_sent"] = st.BytesSent
		out["bytes_received"] = st.BytesReceived
		out["reconnects"] = st.Reconnects
		out["connections"] = s.connections()
		out["uptime"] = int64(time.Since(s.started) / time.Second)
	}
	b, _ := json.Marshal(out)
	return string(b)
}

// Version is the OpenFlux commit Nox was built with.
func Version() string { return openFluxVersion }

// MARK: config

func parse(text string) (config, error) {
	var c config
	if err := json.Unmarshal([]byte(text), &c); err != nil {
		return c, fmt.Errorf("openflux config: %w", err)
	}
	c.Transport = strings.ToLower(strings.TrimSpace(c.Transport))
	if c.Transport == "" {
		c.Transport = "yandex"
	}
	var urls []string
	for _, u := range c.URLs {
		urls = append(urls, splitList(u)...)
	}
	c.URLs = urls
	c.MaxToken = strings.TrimSpace(c.MaxToken)
	c.MaxUID = strings.TrimSpace(c.MaxUID)
	c.Codec = strings.ToLower(strings.TrimSpace(c.Codec))
	if c.Codec == "" {
		c.Codec = "batched"
	}
	if c.Codec != "batched" && c.Codec != "legacy" {
		return c, fmt.Errorf("openflux: unknown codec %q (batched or legacy)", c.Codec)
	}
	switch c.Transport {
	case "yandex", "vyandex", "mailru", "cupsonline":
		if len(c.URLs) == 0 {
			return c, errors.New("openflux: no document URL")
		}
	case "oneme":
		if c.MaxToken == "" || c.MaxUID == "" {
			return c, errors.New("openflux: MAX needs a token and a user id")
		}
		if _, err := strconv.ParseInt(c.MaxUID, 10, 64); err != nil {
			return c, fmt.Errorf("openflux: MAX user id %q is not a number", c.MaxUID)
		}
	default:
		return c, fmt.Errorf("openflux: unknown transport %q", c.Transport)
	}
	c.Key = strings.TrimSpace(c.Key)
	if c.Key != "" && len(c.Key) < 16 {
		return c, errors.New("openflux: the encryption key needs at least 16 characters")
	}
	c.MasterKey = strings.ToLower(strings.TrimSpace(c.MasterKey))
	if c.MasterKey != "" {
		if _, err := parseMaster(c.MasterKey); err != nil {
			return c, err
		}
	}
	if c.Listen == "" {
		c.Listen = defaultListen
	}
	if c.DNS == "" {
		c.DNS = "1.1.1.1:53"
	} else if _, _, err := net.SplitHostPort(c.DNS); err != nil {
		c.DNS = net.JoinHostPort(c.DNS, "53")
	}
	if host, _, _ := net.SplitHostPort(c.DNS); net.ParseIP(host).To4() == nil {
		return c, fmt.Errorf("openflux: DNS server %q must be an IPv4 address", c.DNS)
	}
	return c, nil
}

// identity covers everything that needs a new session when it changes.
func (c config) identity() string {
	c.LogPath, c.Verbose = "", false
	b, _ := json.Marshal(c)
	return string(b)
}

// keyContext matches OpenFlux's main.go: the exit's --url string, "http://#" (the flag's
// default) without one. A cupsonline exit creates its rooms itself and runs without --url,
// so the client-side room list is not part of the context there.
func (c config) keyContext() string {
	if c.KeyContext != "" {
		return c.KeyContext
	}
	if len(c.URLs) > 0 && c.Transport != "cupsonline" {
		return strings.Join(c.URLs, ",")
	}
	return defaultKeyContext
}

// splitList is OpenFlux's splitDocURLs: commas, spaces and newlines separate documents.
func splitList(raw string) []string {
	var out []string
	for _, f := range strings.FieldsFunc(raw, func(r rune) bool { return r == ',' || r == '\n' || r == ' ' || r == '\t' || r == '\r' }) {
		if s := strings.TrimSpace(f); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// buildTransport wraps the transport exactly like OpenFlux's main.go does for --role=client:
// channels → codec (outermost; per channel for several Mail.ru documents) → encryption.
func buildTransport(c config) (transport.Transport, error) {
	tc := transport.DefaultConfig()
	codec := func(t transport.Transport) transport.Transport {
		if c.Codec == "legacy" {
			return transport.NewCompressedTransport(t)
		}
		return transport.NewBatchedTransport(t)
	}
	var inner transport.Transport
	codecApplied := false
	switch c.Transport {
	case "yandex", "vyandex":
		subs := make([]transport.Transport, len(c.URLs))
		for i, u := range c.URLs {
			if c.Transport == "vyandex" {
				subs[i] = yandex.NewYandexVolgaTransport(u, tc)
			} else {
				subs[i] = yandex.NewYandexDocsTransport(u, tc)
			}
		}
		inner = transport.NewMultiTransport(subs)
	case "mailru":
		if len(c.URLs) > 1 {
			subs := make([]transport.Transport, len(c.URLs))
			for i, u := range c.URLs {
				subs[i] = codec(mailru.NewMailruDocsTransport(u, tc))
			}
			inner = transport.NewMultiTransport(subs)
			codecApplied = true
		} else {
			inner = mailru.NewMailruDocsTransport(c.URLs[0], tc)
		}
	case "oneme":
		uid, _ := strconv.ParseInt(c.MaxUID, 10, 64)
		inner = oneme.NewOneMeTransport(false, c.MaxToken, uid, tc)
	case "cupsonline":
		inner = cupsonline.NewCupsonlineTransport(c.URLs[0], tc, true)
	default:
		return nil, fmt.Errorf("openflux: unknown transport %q", c.Transport)
	}
	return c.wrap(inner, codecApplied)
}

// wrap adds the codec (unless the channels already have it) and the optional encryption.
func (c config) wrap(inner transport.Transport, codecApplied bool) (transport.Transport, error) {
	if !codecApplied {
		if c.Codec == "legacy" {
			inner = transport.NewCompressedTransport(inner)
		} else {
			inner = transport.NewBatchedTransport(inner)
		}
	}
	if !c.encrypted() {
		return inner, nil
	}
	var master []byte
	var err error
	if c.MasterKey != "" {
		master, err = parseMaster(c.MasterKey)
	} else {
		master, err = deriveMaster(c.Key, c.keyContext())
	}
	if err != nil {
		return nil, fmt.Errorf("openflux encryption: %w", err)
	}
	return newSealed(inner, master)
}

func (c config) encrypted() bool { return c.Key != "" || c.MasterKey != "" }

// MARK: the shared TCP stack

// relay is the transport OpenFlux's TCP stack talks to. TCPTunnel has no Close, so the stack is
// created once per process and the real transport behind it is swapped when settings change.
type relay struct {
	mu    sync.RWMutex
	inner transport.Transport
	recv  func([]byte)
}

var errNoTransport = errors.New("openflux: transport not connected")

func (r *relay) Start() error { return nil }
func (r *relay) Stop() error  { return nil }

func (r *relay) Send(data []byte) error {
	r.mu.RLock()
	t := r.inner
	r.mu.RUnlock()
	if t == nil {
		return errNoTransport
	}
	return t.Send(data)
}

func (r *relay) Receive(callback func([]byte)) {
	r.mu.Lock()
	r.recv = callback
	r.mu.Unlock()
}

func (r *relay) IsConnected() bool {
	r.mu.RLock()
	t := r.inner
	r.mu.RUnlock()
	return t != nil && t.IsConnected()
}

func (r *relay) Stats() transport.TransportStats {
	r.mu.RLock()
	t := r.inner
	r.mu.RUnlock()
	if t == nil {
		return transport.TransportStats{}
	}
	return t.Stats()
}

func (r *relay) deliver(data []byte) {
	r.mu.RLock()
	cb := r.recv
	r.mu.RUnlock()
	if cb != nil {
		cb(data)
	}
}

func (r *relay) set(t transport.Transport) {
	r.mu.Lock()
	r.inner = t
	r.mu.Unlock()
}

// clear detaches t if it is still the current transport.
func (r *relay) clear(t transport.Transport) {
	r.mu.Lock()
	if r.inner == t {
		r.inner = nil
	}
	r.mu.Unlock()
}

var shared struct {
	once  sync.Once
	relay *relay
	tun   *tunnel.TCPTunnel
}

func stack() (*relay, *tunnel.TCPTunnel) {
	shared.once.Do(func() {
		// Phone-sized TCP windows: OpenFlux's defaults (16–64 MB) are meant for exit nodes, and
		// a Network Extension is killed above ~50 MB.
		tunnel.TCPBufMin = 16 << 10
		tunnel.TCPBufDefault = 256 << 10
		tunnel.TCPBufMax = 2 << 20
		shared.relay = &relay{}
		shared.tun = tunnel.NewTCPTunnel(shared.relay, false)
	})
	return shared.relay, shared.tun
}
