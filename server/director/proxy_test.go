package director

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"
)

// startEchoBackend listens on localhost, accepts one connection, reports the
// first request line it received, then echoes everything after it.
func startEchoBackend(t *testing.T) (addr string, firstLine <-chan string) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { ln.Close() })
	lineCh := make(chan string, 1)
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		r := bufio.NewReader(conn)
		line, _ := r.ReadString('\n')
		lineCh <- line
		io.Copy(conn, r)
	}()
	return ln.Addr().String(), lineCh
}

func newServerWithBackend(t *testing.T, cap int, backendAddr string) *Server {
	t.Helper()
	p, _ := newTestPool(cap)
	s := NewServer(p)
	s.dial = func(port int) (net.Conn, error) {
		return net.Dial("tcp", backendAddr)
	}
	return s
}

func TestProxy_HostRewritesAndSplices(t *testing.T) {
	backendAddr, firstLine := startEchoBackend(t)
	s := newServerWithBackend(t, 5, backendAddr)

	dirLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { dirLn.Close() })
	go s.Serve(dirLn)

	c, err := net.Dial("tcp", dirLn.Addr().String())
	if err != nil {
		t.Fatalf("dial director: %v", err)
	}
	defer c.Close()

	if _, err := io.WriteString(c, "GET /?host=1 HTTP/1.1\r\n\r\nHELLO"); err != nil {
		t.Fatalf("write: %v", err)
	}

	select {
	case line := <-firstLine:
		if line != "GET / HTTP/1.1\r\n" {
			t.Errorf("backend saw %q, want rewritten %q", line, "GET / HTTP/1.1\r\n")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("backend never received the request line")
	}

	// Everything after the first line (the header terminator + body) is spliced
	// through verbatim, so the echo returns "\r\nHELLO".
	c.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, len("\r\nHELLO"))
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatalf("reading echoed payload: %v", err)
	}
	if string(buf) != "\r\nHELLO" {
		t.Errorf("echoed payload = %q, want %q", string(buf), "\r\nHELLO")
	}
}

// Regression: a freshly-spawned host child is still booting, so the first dials
// fail. The director must retry until the child accepts, not close the client.
func TestProxy_HostRetriesDialUntilChildReady(t *testing.T) {
	backendAddr, firstLine := startEchoBackend(t)
	p, _ := newTestPool(5)
	s := NewServer(p)
	s.dialTimeout = 3 * time.Second
	var attempts int32
	s.dial = func(port int) (net.Conn, error) {
		if atomic.AddInt32(&attempts, 1) < 3 { // "booting" for the first two tries
			return nil, fmt.Errorf("child still booting")
		}
		return net.Dial("tcp", backendAddr)
	}

	dirLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { dirLn.Close() })
	go s.Serve(dirLn)

	c, err := net.Dial("tcp", dirLn.Addr().String())
	if err != nil {
		t.Fatalf("dial director: %v", err)
	}
	defer c.Close()
	if _, err := io.WriteString(c, "GET /?host=1 HTTP/1.1\r\n\r\nHI"); err != nil {
		t.Fatalf("write: %v", err)
	}

	select {
	case line := <-firstLine:
		if line != "GET / HTTP/1.1\r\n" {
			t.Errorf("backend saw %q, want rewritten root path", line)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("director never reached the child after retrying")
	}
	if got := atomic.LoadInt32(&attempts); got < 3 {
		t.Errorf("expected at least 3 dial attempts, got %d", got)
	}
}

func TestProxy_JoinUnknownCodeClosesConnection(t *testing.T) {
	backendAddr, _ := startEchoBackend(t)
	s := newServerWithBackend(t, 5, backendAddr)

	dirLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { dirLn.Close() })
	go s.Serve(dirLn)

	c, err := net.Dial("tcp", dirLn.Addr().String())
	if err != nil {
		t.Fatalf("dial director: %v", err)
	}
	defer c.Close()

	if _, err := io.WriteString(c, "GET /?join=ZZZZ HTTP/1.1\r\n\r\n"); err != nil {
		t.Fatalf("write: %v", err)
	}

	c.SetReadDeadline(time.Now().Add(2 * time.Second))
	buf := make([]byte, 1)
	if _, err := c.Read(buf); err != io.EOF {
		t.Errorf("expected EOF (director closed the socket), got %v", err)
	}
}
