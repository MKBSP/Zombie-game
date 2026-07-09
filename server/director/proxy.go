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
	// dial opens a connection to a child on the given internal port. Injectable
	// for tests; defaults to a localhost TCP dial.
	dial func(port int) (net.Conn, error)
}

// NewServer builds a Server backed by pool.
func NewServer(pool *Pool) *Server {
	return &Server{
		pool: pool,
		dial: func(port int) (net.Conn, error) {
			return net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 5*time.Second)
		},
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
		return
	}

	var child Child
	var code string
	switch intent.Kind {
	case KindHost:
		child, code, err = s.pool.Host()
		if err != nil {
			return // pool full or spawn failed → close the socket
		}
	case KindJoin:
		var ok bool
		child, ok = s.pool.Join(intent.Code)
		if !ok {
			return // no such live room → close the socket
		}
		code = intent.Code
	}

	backend, err := s.dial(child.Port())
	if err != nil {
		return
	}
	defer backend.Close()

	// Give the child a byte-identical, root-path handshake.
	if _, err := io.WriteString(backend, RewriteRequestLine(requestLine)+"\r\n"); err != nil {
		return
	}
	s.pool.MarkActive(code)

	// Splice both directions; return as soon as either side is done.
	done := make(chan struct{}, 2)
	go func() { io.Copy(backend, br); done <- struct{}{} }()
	go func() { io.Copy(client, backend); done <- struct{}{} }()
	<-done
}
