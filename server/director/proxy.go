package director

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"strings"
	"time"
)

// Server accepts client connections, reads their WebSocket upgrade line, routes
// them to a pooled child by intent, and splices the raw byte streams.
type Server struct {
	pool *Pool
	// dial opens a single connection attempt to a child on the given internal
	// port. Injectable for tests; defaults to a localhost TCP dial.
	dial func(port int) (net.Conn, error)
	// dialTimeout bounds how long dialReady retries a freshly-spawned (still
	// booting) child before giving up.
	dialTimeout time.Duration
}

// NewServer builds a Server backed by pool.
func NewServer(pool *Pool) *Server {
	return &Server{
		pool: pool,
		dial: func(port int) (net.Conn, error) {
			return net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 2*time.Second)
		},
		dialTimeout: 25 * time.Second,
	}
}

// Serve accepts connections on ln until it errors (e.g. the listener closes).
func (s *Server) Serve(ln net.Listener) error {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return err
		}
		go s.handle(conn)
	}
}

// handle routes one client connection. Any error before splicing simply closes
// the client socket — the client surfaces that as a failed connection.
func (s *Server) handle(client net.Conn) {
	defer client.Close()

	br := bufio.NewReader(client)
	rawLine, err := br.ReadString('\n')
	if err != nil {
		return
	}
	requestLine := strings.TrimRight(rawLine, "\r\n")

	intent, err := ParseUpgrade(requestLine)
	if err != nil {
		// Not a game connection (health probe, browser hit, curl) — answer with a
		// tiny HTTP 200 instead of a silent close so probes and humans see life.
		const body = "director ok\n"
		fmt.Fprintf(client, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s", len(body), body)
		return
	}

	var child Child
	switch intent.Kind {
	case KindHost:
		child, _, err = s.pool.Host()
		if err != nil {
			return // pool full or spawn failed → close the socket
		}
		// One child = one host session. When the host's connection ends — whether
		// abandoned in the menu/lobby or closed after a finished match — kill the
		// child so the pool reaps the slot and refills the warm buffer. Without
		// this a host that never cleanly empties its room (an abandoned connection,
		// a web client that just drops the socket) pins its slot forever, and after
		// MAX_GAMES such attempts the pool is exhausted and every host is refused.
		// This mirrors the game's own rule that the host leaving closes the room.
		defer child.Kill()
	case KindJoin:
		var ok bool
		child, ok = s.pool.Join(intent.Code)
		if !ok {
			return // no such live room → close the socket
		}
	}

	// A freshly-spawned host child may still be booting; retry until it accepts.
	backend, err := s.dialReady(child.Port())
	if err != nil {
		return
	}
	defer backend.Close()

	// Give the child a byte-identical, root-path handshake.
	if _, err := io.WriteString(backend, RewriteRequestLine(requestLine)+"\r\n"); err != nil {
		return
	}

	// Splice both directions; return as soon as either side is done.
	done := make(chan struct{}, 2)
	go func() { io.Copy(backend, br); done <- struct{}{} }()
	go func() { io.Copy(client, backend); done <- struct{}{} }()
	<-done
}

// dialReady dials the child, retrying while it boots, until dialTimeout.
func (s *Server) dialReady(port int) (net.Conn, error) {
	deadline := time.Now().Add(s.dialTimeout)
	for {
		conn, err := s.dial(port)
		if err == nil {
			return conn, nil
		}
		if time.Now().After(deadline) {
			return nil, err
		}
		time.Sleep(150 * time.Millisecond)
	}
}
