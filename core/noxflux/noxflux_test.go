package noxflux

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"openflux/transport"
	"openflux/tunnel"
)

// pipeTransport is one end of an in-memory channel between the client and an exit node.
type pipeTransport struct {
	peer  *pipeTransport
	queue chan []byte
	mu    sync.RWMutex
	recv  func([]byte)
	up    atomic.Bool
	stop  chan struct{}
	once  sync.Once
}

func newPipe() (*pipeTransport, *pipeTransport) {
	a := &pipeTransport{queue: make(chan []byte, 8192), stop: make(chan struct{})}
	b := &pipeTransport{queue: make(chan []byte, 8192), stop: make(chan struct{})}
	a.peer, b.peer = b, a
	return a, b
}

func (p *pipeTransport) Start() error {
	p.up.Store(true)
	go func() {
		for {
			select {
			case d := <-p.queue:
				p.mu.RLock()
				cb := p.recv
				p.mu.RUnlock()
				if cb != nil {
					cb(d)
				}
			case <-p.stop:
				return
			}
		}
	}()
	return nil
}

func (p *pipeTransport) Stop() error {
	p.up.Store(false)
	p.once.Do(func() { close(p.stop) })
	return nil
}

func (p *pipeTransport) Send(d []byte) error {
	if !p.IsConnected() {
		return errors.New("pipe down")
	}
	select {
	case p.peer.queue <- append([]byte(nil), d...):
		return nil
	default:
		return errors.New("pipe full")
	}
}

func (p *pipeTransport) Receive(cb func([]byte)) {
	p.mu.Lock()
	p.recv = cb
	p.mu.Unlock()
}

func (p *pipeTransport) IsConnected() bool { return p.up.Load() && p.peer.up.Load() }
func (p *pipeTransport) Stats() transport.TransportStats {
	return transport.TransportStats{Connected: p.IsConnected()}
}

// exitNode starts an OpenFlux L4 exit on the other end, wrapped like main.go --role=exit does.
func exitNode(t *testing.T, cfg config, base transport.Transport) {
	t.Helper()
	var inner transport.Transport
	if cfg.Codec == "legacy" {
		inner = transport.NewCompressedTransport(base)
	} else {
		inner = transport.NewBatchedTransport(base)
	}
	if cfg.Key != "" {
		enc, err := transport.NewEncryptedTransport(inner, cfg.Key, cfg.keyContext(), true)
		if err != nil {
			t.Fatal(err)
		}
		inner = enc
	}
	if err := inner.Start(); err != nil {
		t.Fatal(err)
	}
	ex, err := tunnel.NewExitNode(inner, "l4")
	if err != nil {
		t.Fatal(err)
	}
	if err := ex.Start(); err != nil {
		t.Fatal(err)
	}
}

// localIP is a non-loopback address: gVisor drops loopback destinations on its tunnel NIC.
func localIP(t *testing.T) string {
	addrs, _ := net.InterfaceAddrs()
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok && !n.IP.IsLoopback() && n.IP.To4() != nil {
			return n.IP.String()
		}
	}
	t.Skip("no non-loopback IPv4 address")
	return ""
}

var payload = func() []byte {
	b := make([]byte, 6<<20)
	rand.New(rand.NewSource(1)).Read(b)
	return b
}()

func httpServer(t *testing.T, ip string) int {
	mux := http.NewServeMux()
	mux.HandleFunc("/hello", func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "hello through openflux") })
	mux.HandleFunc("/big", func(w http.ResponseWriter, r *http.Request) { w.Write(payload) })
	mux.HandleFunc("/upload", func(w http.ResponseWriter, r *http.Request) {
		h := sha256.New()
		n, _ := io.Copy(h, r.Body)
		fmt.Fprintf(w, "%d %x", n, h.Sum(nil))
	})
	ln, err := net.Listen("tcp", ip+":0")
	if err != nil {
		t.Fatal(err)
	}
	srv := &http.Server{Handler: mux}
	go srv.Serve(ln)
	t.Cleanup(func() { srv.Close() })
	return ln.Addr().(*net.TCPAddr).Port
}

// dnsServer answers A queries for test.nox over TCP.
func dnsServer(t *testing.T, ip, answer string) string {
	ln, err := net.Listen("tcp", ip+":0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				for {
					var l [2]byte
					if _, err := io.ReadFull(c, l[:]); err != nil {
						return
					}
					q := make([]byte, binary.BigEndian.Uint16(l[:]))
					if _, err := io.ReadFull(c, q); err != nil {
						return
					}
					// The question ends after the name's zero label + type + class (EDNS records follow).
					end := 12
					for end < len(q) && q[end] != 0 {
						end += int(q[end]) + 1
					}
					end += 5
					if end > len(q) {
						return
					}
					qtype := binary.BigEndian.Uint16(q[end-4:])
					// header: same id, response + RD + RA, 1 question, 1 answer (only for test.nox A).
					resp := append([]byte(nil), q[:2]...)
					an := uint16(0)
					if qtype == 1 && bytes.Contains(q[12:end], []byte("\x04test\x03nox")) {
						an = 1
					}
					resp = append(resp, 0x81, 0x80, 0, 1, byte(an>>8), byte(an), 0, 0, 0, 0)
					resp = append(resp, q[12:end]...)
					if an == 1 {
						resp = append(resp, 0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4)
						resp = append(resp, net.ParseIP(answer).To4()...)
					}
					out := binary.BigEndian.AppendUint16(nil, uint16(len(resp)))
					c.Write(append(out, resp...))
				}
			}(c)
		}
	}()
	return ln.Addr().String()
}

// Credentials the test sessions require (cfg.Username / cfg.Password).
const testUser, testPass = "nox", "s3cret-for-tests"

// socksConnect does a SOCKS5 CONNECT with the test credentials and returns the reply code.
func socksConnect(proxy string, cmd, atyp byte, host string, port int) (net.Conn, byte, error) {
	return socksConnectAs(proxy, testUser, testPass, cmd, atyp, host, port)
}

func socksConnectAs(proxy, user, pass string, cmd, atyp byte, host string, port int) (net.Conn, byte, error) {
	c, err := net.DialTimeout("tcp", proxy, 5*time.Second)
	if err != nil {
		return nil, 0, err
	}
	c.SetDeadline(time.Now().Add(30 * time.Second))
	if user == "" {
		c.Write([]byte{5, 1, 0})
	} else {
		c.Write([]byte{5, 2, 0, 2})
	}
	var b [10]byte
	if _, err := io.ReadFull(c, b[:2]); err != nil || (b[1] != 0 && b[1] != 2) {
		c.Close()
		return nil, 0, fmt.Errorf("greeting: %v %v", b[:2], err)
	}
	if b[1] == 2 {
		auth := append([]byte{1, byte(len(user))}, user...)
		auth = append(append(auth, byte(len(pass))), pass...)
		c.Write(auth)
		if _, err := io.ReadFull(c, b[:2]); err != nil || b[1] != 0 {
			c.Close()
			return nil, 0, fmt.Errorf("auth: %v %v", b[:2], err)
		}
	}
	req := []byte{5, cmd, 0, atyp}
	switch atyp {
	case 1:
		req = append(req, net.ParseIP(host).To4()...)
	case 3:
		req = append(req, byte(len(host)))
		req = append(req, host...)
	case 4:
		req = append(req, net.ParseIP(host).To16()...)
	}
	req = binary.BigEndian.AppendUint16(req, uint16(port))
	c.Write(req)
	if _, err := io.ReadFull(c, b[:10]); err != nil {
		c.Close()
		return nil, 0, err
	}
	c.SetDeadline(time.Time{})
	return c, b[1], nil
}

func client(proxy string) *http.Client {
	return &http.Client{Timeout: 60 * time.Second, Transport: &http.Transport{
		DisableKeepAlives: true,
		DialContext: func(ctx context.Context, _, addr string) (net.Conn, error) {
			host, p, _ := net.SplitHostPort(addr)
			port, _ := strconv.Atoi(p)
			atyp := byte(1)
			if net.ParseIP(host) == nil {
				atyp = 3
			}
			c, code, err := socksConnect(proxy, 1, atyp, host, port)
			if err != nil {
				return nil, err
			}
			if code != 0 {
				c.Close()
				return nil, fmt.Errorf("socks reply %d", code)
			}
			return c, nil
		},
	}}
}

func get(t *testing.T, c *http.Client, url string) []byte {
	t.Helper()
	resp, err := c.Get(url)
	if err != nil {
		t.Fatalf("GET %s: %v", url, err)
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("GET %s body: %v", url, err)
	}
	return b
}

func startPair(t *testing.T, cfg config) string {
	t.Helper()
	return startPairWithExit(t, cfg, cfg)
}

// startPairWithExit runs the client with cfg against an exit configured with exitCfg.
func startPairWithExit(t *testing.T, cfg, exitCfg config) string {
	t.Helper()
	a, b := newPipe()
	exitNode(t, exitCfg, b)
	inner, err := cfg.wrap(a, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := start(cfg, inner); err != nil {
		t.Fatal(err)
	}
	if !WaitConnected(5000) {
		t.Fatal("not connected")
	}
	mu.Lock()
	addr := active.ln.Addr().String()
	mu.Unlock()
	return addr
}

func testConfig(t *testing.T, key string) config {
	cfg, err := parse(`{"transport":"yandex","urls":["https://disk.yandex.ru/edit/d/test-1, https://disk.yandex.ru/edit/d/test-2"],"listen":"127.0.0.1:0","key":"` + key + `","username":"` + testUser + `","password":"` + testPass + `"}`)
	if err != nil {
		t.Fatal(err)
	}
	return cfg
}

func TestTunnel(t *testing.T) {
	ip := localIP(t)
	port := httpServer(t, ip)
	const secret = "correct horse battery staple"
	for _, tc := range []struct {
		name        string
		key, master bool
	}{{"plain", false, false}, {"secret", true, false}, {"master key", true, true}} {
		t.Run(tc.name, func(t *testing.T) {
			exitCfg := testConfig(t, map[bool]string{true: secret}[tc.key])
			exitCfg.DNS = dnsServer(t, ip, ip)
			cfg := exitCfg
			if tc.master {
				// What the app sends: the derived key, not the secret.
				m, err := deriveMaster(secret, exitCfg.keyContext())
				if err != nil {
					t.Fatal(err)
				}
				cfg.Key, cfg.MasterKey = "", hex.EncodeToString(m)
			}
			proxy := startPairWithExit(t, cfg, exitCfg)
			defer Stop()
			c := client(proxy)
			base := "http://" + net.JoinHostPort(ip, strconv.Itoa(port))
			if got := string(get(t, c, base+"/hello")); got != "hello through openflux" {
				t.Fatalf("hello: %q", got)
			}
			// Domain targets are resolved through the tunnel.
			if got := string(get(t, c, "http://test.nox:"+strconv.Itoa(port)+"/hello")); got != "hello through openflux" {
				t.Fatalf("domain: %q", got)
			}
			start := time.Now()
			big := get(t, c, base+"/big")
			if !bytes.Equal(big, payload) {
				t.Fatalf("download: %d bytes, mismatch", len(big))
			}
			t.Logf("download %d MB in %s", len(big)>>20, time.Since(start).Round(time.Millisecond))
			resp, err := c.Post(base+"/upload", "application/octet-stream", bytes.NewReader(payload[:3<<20]))
			if err != nil {
				t.Fatal(err)
			}
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			sum := sha256.Sum256(payload[:3<<20])
			if want := fmt.Sprintf("%d %s", 3<<20, hex.EncodeToString(sum[:])); string(body) != want {
				t.Fatalf("upload: %q", body)
			}
			var wg sync.WaitGroup
			errs := make(chan error, 16)
			for i := 0; i < 16; i++ {
				wg.Add(1)
				go func() {
					defer wg.Done()
					resp, err := c.Get(base + "/hello")
					if err != nil {
						errs <- err
						return
					}
					io.Copy(io.Discard, resp.Body)
					resp.Body.Close()
				}()
			}
			wg.Wait()
			close(errs)
			for err := range errs {
				t.Fatalf("parallel: %v", err)
			}
			t.Logf("status: %s", Status())
		})
	}
}

func TestSocksRejects(t *testing.T) {
	cfg := testConfig(t, "")
	proxy := startPair(t, cfg)
	defer Stop()
	if c, code, err := socksConnect(proxy, 3, 1, "0.0.0.0", 0); err != nil || code != repCommand {
		t.Fatalf("UDP associate: code %d err %v", code, err)
	} else {
		c.Close()
	}
	if c, code, err := socksConnect(proxy, 1, 4, "2001:db8::1", 443); err != nil || code != repAddress {
		t.Fatalf("IPv6: code %d err %v", code, err)
	} else {
		c.Close()
	}
}

func TestSocksAuth(t *testing.T) {
	ip := localIP(t)
	port := httpServer(t, ip)
	cfg := testConfig(t, "")
	proxy := startPair(t, cfg)
	defer Stop()
	if _, _, err := socksConnectAs(proxy, "", "", 1, 1, ip, port); err == nil {
		t.Fatal("no-auth client accepted")
	}
	if _, _, err := socksConnectAs(proxy, testUser, "wrong", 1, 1, ip, port); err == nil {
		t.Fatal("wrong password accepted")
	}
	c, code, err := socksConnect(proxy, 1, 1, ip, port)
	if err != nil || code != repOK {
		t.Fatalf("right password: code %d err %v", code, err)
	}
	c.Close()
}

func TestProbe(t *testing.T) {
	if got := Probe(100); got != ProbeNotRunning {
		t.Fatalf("idle probe = %d", got)
	}
	cfg := testConfig(t, "")
	before := Generation()
	startPair(t, cfg)
	if Generation() == before {
		t.Fatal("generation did not change")
	}
	if got := Probe(10000); got != ProbeOK {
		t.Fatalf("probe = %d", got)
	}
	// Same settings again: same session, same generation.
	g := Generation()
	if err := start(cfg, nil); err != nil || Generation() != g {
		t.Fatalf("restart with the same settings: %v, generation %d → %d", err, g, Generation())
	}
	Stop()

	// A channel with nobody on the other side.
	a, b := newPipe()
	b.Start()
	inner, err := cfg.wrap(a, false)
	if err != nil {
		t.Fatal(err)
	}
	cfg.Codec = "legacy" // new identity → new session
	if err := start(cfg, inner); err != nil {
		t.Fatal(err)
	}
	defer Stop()
	started := time.Now()
	if got := Probe(1500); got != ProbeExitSilent {
		t.Fatalf("probe without an exit = %d", got)
	}
	if d := time.Since(started); d > 3*time.Second {
		t.Fatalf("probe took %s", d)
	}
}

func TestRestartReusesStack(t *testing.T) {
	ip := localIP(t)
	port := httpServer(t, ip)
	url := "http://" + net.JoinHostPort(ip, strconv.Itoa(port)) + "/hello"
	cfg := testConfig(t, "")
	proxy := startPair(t, cfg)
	get(t, client(proxy), url)
	// Same settings: the session is kept.
	mu.Lock()
	first := active
	mu.Unlock()
	if err := start(cfg, nil); err != nil {
		t.Fatal(err)
	}
	mu.Lock()
	same := active == first
	mu.Unlock()
	if !same {
		t.Fatal("same settings replaced the session")
	}
	// New settings: a new transport behind the same TCP stack.
	cfg.Codec = "legacy"
	proxy = startPair(t, cfg)
	defer Stop()
	if got := string(get(t, client(proxy), url)); got != "hello through openflux" {
		t.Fatalf("after restart: %q", got)
	}
}

func TestParse(t *testing.T) {
	bad := []string{
		`{"transport":"yandex","urls":["a"],"master_key":"abcd"}`,
		`{"transport":"yandex"}`,
		`{"transport":"oneme","max_token":"x"}`,
		`{"transport":"oneme","max_token":"x","max_uid":"abc"}`,
		`{"transport":"nope","urls":["a"]}`,
		`{"transport":"yandex","urls":["a"],"codec":"zip"}`,
		`{"transport":"yandex","urls":["a"],"key":"short"}`,
		`{"transport":"yandex","urls":["a"],"dns":"dns.google"}`,
	}
	for _, s := range bad {
		if _, err := parse(s); err == nil {
			t.Errorf("accepted %s", s)
		}
	}
	c, err := parse(`{"transport":"MailRu","urls":["https://cloud.mail.ru/public/a/b\nhttps://cloud.mail.ru/public/c/d"],"dns":"8.8.8.8"}`)
	if err != nil {
		t.Fatal(err)
	}
	if c.Transport != "mailru" || len(c.URLs) != 2 || c.Codec != "batched" || c.DNS != "8.8.8.8:53" || c.Listen != defaultListen {
		t.Fatalf("parsed %+v", c)
	}
	if got := c.keyContext(); got != "https://cloud.mail.ru/public/a/b,https://cloud.mail.ru/public/c/d" {
		t.Fatalf("context %q", got)
	}
	m, _ := parse(`{"transport":"oneme","max_token":"t","max_uid":"42"}`)
	if m.keyContext() != "http://#" {
		t.Fatalf("MAX context %q", m.keyContext())
	}
	cups, _ := parse(`{"transport":"cupsonline","urls":["https://interview.cups.online/?rooms=abc"]}`)
	if cups.keyContext() != "http://#" {
		t.Fatalf("cupsonline context %q", cups.keyContext())
	}
	if o, _ := parse(`{"transport":"cupsonline","urls":["x"],"key_context":"own"}`); o.keyContext() != "own" {
		t.Fatalf("explicit context %q", o.keyContext())
	}
	for _, tr := range []string{"yandex", "vyandex", "mailru", "cupsonline"} {
		cfg, err := parse(`{"transport":"` + tr + `","urls":["https://example.com/doc/1"],"key":"0123456789abcdef"}`)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := buildTransport(cfg); err != nil {
			t.Fatalf("%s: %v", tr, err)
		}
	}
}

// crashTransport fails like OpenFlux's MAX client without a network: Start panics.
type crashTransport struct{ *pipeTransport }

func (crashTransport) Start() error { panic("login over a nil websocket") }

func TestStartCrashReleasesListener(t *testing.T) {
	cfg := testConfig(t, "")
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	cfg.Listen = l.Addr().String()
	l.Close()
	a, _ := newPipe()
	err = start(cfg, crashTransport{a})
	if err == nil || !strings.Contains(err.Error(), "crashed while connecting") {
		t.Fatalf("start with a crashing transport: %v", err)
	}
	if IsRunning() {
		t.Fatal("running after a failed start")
	}
	// The port is free again: a working transport starts on the same address.
	a, b := newPipe()
	exitNode(t, cfg, b)
	inner, err := cfg.wrap(a, false)
	if err != nil {
		t.Fatal(err)
	}
	if err := start(cfg, inner); err != nil {
		t.Fatal(err)
	}
	defer Stop()
	if got := Probe(5000); got != ProbeOK {
		t.Fatalf("probe after the restart = %d", got)
	}
}
