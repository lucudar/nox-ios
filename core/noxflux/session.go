package noxflux

import (
	"context"
	"crypto/subtle"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"sync"
	"time"

	"openflux/transport"
	"openflux/tunnel"
	"openflux/utils"
)

// session is one connected transport plus the SOCKS5 listener sing-box dials.
type session struct {
	cfg     config
	id      string
	inner   transport.Transport
	ln      net.Listener
	tun     *tunnel.TCPTunnel
	started time.Time
	done    chan struct{}

	mu    sync.Mutex
	conns map[net.Conn]struct{}

	resolver *net.Resolver
	dnsMu    sync.Mutex
	dnsCache map[string]dnsEntry
}

type dnsEntry struct {
	ip      string
	expires time.Time
}

func newSession(cfg config, id string, inner transport.Transport) (*session, error) {
	ln, err := net.Listen("tcp", cfg.Listen)
	if err != nil {
		return nil, fmt.Errorf("openflux: SOCKS5 %s: %w", cfg.Listen, err)
	}
	r, tun := stack()
	inner.Receive(r.deliver)
	if err := startTransport(inner); err != nil {
		ln.Close()
		stopTransport(inner)
		return nil, fmt.Errorf("openflux: transport %s: %w", cfg.Transport, err)
	}
	r.set(inner)
	s := &session{
		cfg: cfg, id: id, inner: inner, ln: ln, tun: tun,
		started:  time.Now(),
		done:     make(chan struct{}),
		conns:    map[net.Conn]struct{}{},
		dnsCache: map[string]dnsEntry{},
	}
	// Names are resolved through the tunnel (DNS over TCP via the exit node): the local resolver
	// may be filtered, and the exit has to reach the address anyway.
	s.resolver = &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return s.dial(ctx, s.cfg.DNS)
	}}
	go s.serve()
	go s.watch()
	enc := "off"
	if cfg.encrypted() {
		enc = "AES-256-GCM"
	}
	logf("started OpenFlux %s: transport %s, %d channel(s), codec %s, encryption %s, SOCKS5 %s",
		openFluxVersion, cfg.Transport, max(1, len(cfg.URLs)), cfg.Codec, enc, ln.Addr())
	return s, nil
}

// startTransport runs the transport's Start, turning a panic into an error: OpenFlux clients
// can crash on a failed connection (the MAX client logs in over a nil socket), and the SOCKS5
// listener has to be released either way, or the next start can't bind the port.
func startTransport(t transport.Transport) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("crashed while connecting (%v)", r)
		}
	}()
	return t.Start()
}

// stopTransport stops a transport that may be only partly started.
func stopTransport(t transport.Transport) {
	defer func() {
		if r := recover(); r != nil {
			logf("transport stop: %v", r)
		}
	}()
	_ = t.Stop()
}

func (s *session) close() {
	select {
	case <-s.done:
		return
	default:
		close(s.done)
	}
	s.ln.Close()
	s.mu.Lock()
	for c := range s.conns {
		c.Close()
	}
	s.conns = nil
	s.mu.Unlock()
	r, _ := stack()
	r.clear(s.inner)
	stopTransport(s.inner)
}

func (s *session) closed() bool {
	select {
	case <-s.done:
		return true
	default:
		return false
	}
}

func (s *session) track(c net.Conn) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.conns == nil {
		return false
	}
	s.conns[c] = struct{}{}
	return true
}

func (s *session) untrack(c net.Conn) {
	s.mu.Lock()
	if s.conns != nil {
		delete(s.conns, c)
	}
	s.mu.Unlock()
}

func (s *session) connections() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.conns) / 2
}

// watch logs connection changes (OpenFlux reconnects on its own).
func (s *session) watch() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	was := false
	var lostAt time.Time
	for {
		select {
		case <-s.done:
			return
		case <-ticker.C:
		}
		now := s.inner.IsConnected()
		if now == was {
			continue
		}
		st := s.inner.Stats()
		if now {
			if lostAt.IsZero() {
				logf("connected in %s", time.Since(s.started).Round(100*time.Millisecond))
			} else {
				logf("reconnected after %s (reconnects: %d)", time.Since(lostAt).Round(time.Second), st.Reconnects)
			}
		} else {
			lostAt = time.Now()
			logf("connection lost, reconnecting (sent %d B, received %d B)", st.BytesSent, st.BytesReceived)
		}
		was = now
	}
}

// MARK: SOCKS5 (RFC 1928, CONNECT only; username/password auth, RFC 1929, when configured)

func (s *session) serve() {
	for {
		c, err := s.ln.Accept()
		if err != nil {
			if s.closed() {
				return
			}
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() {
				continue
			}
			logf("SOCKS5 accept: %v", err)
			time.Sleep(200 * time.Millisecond)
			continue
		}
		go s.handle(c)
	}
}

const (
	repOK          = 0x00
	repFailure     = 0x01
	repUnreachable = 0x04
	repRefused     = 0x05
	repCommand     = 0x07
	repAddress     = 0x08
)

type socksError struct {
	code byte
	err  error
}

func (e *socksError) Error() string { return e.err.Error() }

func reply(c net.Conn, code byte) {
	_, _ = c.Write([]byte{5, code, 0, 1, 0, 0, 0, 0, 0, 0})
}

// handshake reads the greeting (and credentials) and the request; returns the target host and port.
func handshake(c net.Conn, user, pass string) (string, uint16, error) {
	var b [262]byte
	if _, err := io.ReadFull(c, b[:2]); err != nil {
		return "", 0, err
	}
	if b[0] != 5 {
		return "", 0, errors.New("not a SOCKS5 client")
	}
	methods := b[:b[1]]
	if _, err := io.ReadFull(c, methods); err != nil {
		return "", 0, err
	}
	want := byte(0)
	if user != "" || pass != "" {
		want = 2
	}
	offered := false
	for _, m := range methods {
		offered = offered || m == want
	}
	if !offered {
		_, _ = c.Write([]byte{5, 0xff})
		return "", 0, fmt.Errorf("no acceptable auth method (want %d)", want)
	}
	if _, err := c.Write([]byte{5, want}); err != nil {
		return "", 0, err
	}
	if want == 2 {
		if _, err := io.ReadFull(c, b[:2]); err != nil {
			return "", 0, err
		}
		name := make([]byte, b[1])
		if _, err := io.ReadFull(c, name); err != nil {
			return "", 0, err
		}
		if _, err := io.ReadFull(c, b[:1]); err != nil {
			return "", 0, err
		}
		secret := make([]byte, b[0])
		if _, err := io.ReadFull(c, secret); err != nil {
			return "", 0, err
		}
		okUser := subtle.ConstantTimeCompare(name, []byte(user)) == 1
		okPass := subtle.ConstantTimeCompare(secret, []byte(pass)) == 1
		if !okUser || !okPass {
			_, _ = c.Write([]byte{1, 1})
			return "", 0, errors.New("wrong SOCKS5 credentials")
		}
		if _, err := c.Write([]byte{1, 0}); err != nil {
			return "", 0, err
		}
	}
	if _, err := io.ReadFull(c, b[:4]); err != nil {
		return "", 0, err
	}
	if b[0] != 5 {
		return "", 0, errors.New("bad SOCKS5 request")
	}
	cmd, atyp := b[1], b[3]
	var host string
	switch atyp {
	case 1:
		if _, err := io.ReadFull(c, b[:4]); err != nil {
			return "", 0, err
		}
		host = net.IPv4(b[0], b[1], b[2], b[3]).String()
	case 3:
		if _, err := io.ReadFull(c, b[:1]); err != nil {
			return "", 0, err
		}
		name := b[:b[0]]
		if _, err := io.ReadFull(c, name); err != nil {
			return "", 0, err
		}
		host = string(name)
	case 4:
		if _, err := io.ReadFull(c, b[:16]); err != nil {
			return "", 0, err
		}
		host = net.IP(append([]byte(nil), b[:16]...)).String()
	default:
		return "", 0, &socksError{repAddress, fmt.Errorf("address type %d", atyp)}
	}
	if _, err := io.ReadFull(c, b[:2]); err != nil {
		return "", 0, err
	}
	port := binary.BigEndian.Uint16(b[:2])
	switch {
	case cmd == 3:
		return "", 0, &socksError{repCommand, errors.New("UDP isn't carried over OpenFlux")}
	case cmd != 1:
		return "", 0, &socksError{repCommand, fmt.Errorf("command %d", cmd)}
	case atyp == 4:
		return "", 0, &socksError{repAddress, errors.New("IPv6 isn't carried over OpenFlux")}
	}
	return host, port, nil
}

func (s *session) handle(c net.Conn) {
	defer func() {
		if r := recover(); r != nil {
			logf("SOCKS5 handler: %v", r)
		}
	}()
	defer c.Close()
	if !s.track(c) {
		return
	}
	defer s.untrack(c)

	_ = c.SetDeadline(time.Now().Add(30 * time.Second))
	host, port, err := handshake(c, s.cfg.Username, s.cfg.Password)
	if err != nil {
		var se *socksError
		if errors.As(err, &se) {
			reply(c, se.code)
		}
		utils.Debugf("[NOX] SOCKS5: %v", err)
		return
	}
	ip, err := s.resolve(host)
	if err != nil {
		reply(c, repUnreachable)
		// Go names the system resolver in the error; the query really went to cfg.DNS.
		logf("resolve %s via %s through the tunnel: %v", host, s.cfg.DNS, err)
		return
	}
	target := net.JoinHostPort(ip, strconv.Itoa(int(port)))
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	remote, err := s.dial(ctx, target)
	cancel()
	if err != nil {
		code := byte(repUnreachable)
		if errors.Is(err, errNoTransport) {
			code = repFailure
		} else if !errors.Is(err, context.DeadlineExceeded) {
			code = repRefused
		}
		reply(c, code)
		utils.Debugf("[NOX] dial %s (%s): %v", target, host, err)
		return
	}
	defer remote.Close()
	if !s.track(remote) {
		return
	}
	defer s.untrack(remote)
	reply(c, repOK)
	_ = c.SetDeadline(time.Time{})
	pipe(c, remote)
}

// dial opens a TCP connection through the tunnel. gVisor's dial has no timeout, so it runs aside.
func (s *session) dial(ctx context.Context, address string) (net.Conn, error) {
	if !s.inner.IsConnected() {
		// Still connecting: give the transport a moment instead of failing at once.
		for i := 0; i < 50 && !s.inner.IsConnected(); i++ {
			select {
			case <-ctx.Done():
				return nil, errNoTransport
			case <-s.done:
				return nil, errNoTransport
			case <-time.After(100 * time.Millisecond):
			}
		}
		if !s.inner.IsConnected() {
			return nil, errNoTransport
		}
	}
	type result struct {
		c   net.Conn
		err error
	}
	ch := make(chan result, 1)
	go func() {
		c, err := s.tun.DialTCP(address)
		ch <- result{c, err}
	}()
	abandon := func() {
		go func() {
			if r := <-ch; r.c != nil {
				r.c.Close()
			}
		}()
	}
	select {
	case r := <-ch:
		return r.c, r.err
	case <-ctx.Done():
		abandon()
		return nil, ctx.Err()
	case <-s.done:
		abandon()
		return nil, errNoTransport
	}
}

func (s *session) resolve(host string) (string, error) {
	if ip := net.ParseIP(host); ip != nil {
		if ip.To4() == nil {
			return "", errors.New("IPv6 isn't carried over OpenFlux")
		}
		return ip.String(), nil
	}
	now := time.Now()
	s.dnsMu.Lock()
	if e, ok := s.dnsCache[host]; ok && now.Before(e.expires) {
		s.dnsMu.Unlock()
		return e.ip, nil
	}
	s.dnsMu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	ips, err := s.resolver.LookupIP(ctx, "ip4", host)
	if err != nil {
		return "", err
	}
	if len(ips) == 0 {
		return "", errors.New("no IPv4 address")
	}
	ip := ips[0].String()
	s.dnsMu.Lock()
	if len(s.dnsCache) > 256 {
		s.dnsCache = map[string]dnsEntry{}
	}
	s.dnsCache[host] = dnsEntry{ip, now.Add(5 * time.Minute)}
	s.dnsMu.Unlock()
	return ip, nil
}

var bufPool = sync.Pool{New: func() any { b := make([]byte, 32<<10); return &b }}

// pipe copies both ways; after one side finishes the other gets a minute to drain.
func pipe(a, b net.Conn) {
	done := make(chan struct{}, 2)
	copyHalf := func(dst, src net.Conn) {
		buf := bufPool.Get().(*[]byte)
		_, _ = io.CopyBuffer(dst, src, *buf)
		bufPool.Put(buf)
		if cw, ok := dst.(interface{ CloseWrite() error }); ok {
			_ = cw.CloseWrite()
		} else {
			_ = dst.Close()
		}
		done <- struct{}{}
	}
	go copyHalf(a, b)
	go copyHalf(b, a)
	<-done
	timer := time.NewTimer(time.Minute)
	select {
	case <-done:
	case <-timer.C:
	}
	timer.Stop()
	a.Close()
	b.Close()
}

// MARK: log file

// logFile is openflux.log in the App Group (the app shows it in Logs), kept under 512 KB.
type logFile struct {
	mu   sync.Mutex
	path string
	f    *os.File
	size int64
}

const logLimit = 512 << 10

func (l *logFile) open(path string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if path == l.path && (l.f != nil || path == "") {
		return
	}
	if l.f != nil {
		l.f.Close()
		l.f = nil
	}
	l.path = path
	if path == "" {
		return
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	l.f = f
	l.size = 0
	if st, err := f.Stat(); err == nil {
		l.size = st.Size()
	}
	if l.size > logLimit {
		l.truncate()
	}
}

func (l *logFile) truncate() {
	_ = l.f.Truncate(0)
	_, _ = l.f.Seek(0, io.SeekStart)
	l.size = 0
}

func (l *logFile) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.f == nil {
		return os.Stderr.Write(p)
	}
	if l.size+int64(len(p)) > logLimit {
		l.truncate()
	}
	n, err := l.f.Write(p)
	l.size += int64(n)
	return n, err
}
