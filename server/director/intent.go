package director

import (
	"fmt"
	"net/url"
	"strings"
)

// Kind is the routing intent parsed from a client's WebSocket upgrade request.
type Kind int

const (
	// KindHost means "give me a fresh room" — the director allocates a child.
	KindHost Kind = iota
	// KindJoin means "connect me to room Code" — the director looks it up.
	KindJoin
)

// Intent is what the director needs to route a connection: whether to host or
// join, and (for a join) the room code.
type Intent struct {
	Kind Kind
	Code string
}

// ParseUpgrade reads the first line of an HTTP request (the WebSocket upgrade
// request line, e.g. "GET /?join=AB3K HTTP/1.1") and extracts the routing
// intent from its query string. A request must carry exactly one of ?host or
// ?join=CODE; anything else is an error the caller turns into a closed socket.
func ParseUpgrade(requestLine string) (Intent, error) {
	fields := strings.Fields(requestLine)
	if len(fields) < 3 || !strings.HasPrefix(fields[1], "/") {
		return Intent{}, fmt.Errorf("malformed request line: %q", requestLine)
	}
	u, err := url.ParseRequestURI(fields[1])
	if err != nil {
		return Intent{}, fmt.Errorf("bad request target %q: %w", fields[1], err)
	}
	q := u.Query()
	if q.Has("host") {
		return Intent{Kind: KindHost}, nil
	}
	if q.Has("join") {
		code := strings.ToUpper(strings.TrimSpace(q.Get("join")))
		if code == "" {
			return Intent{}, fmt.Errorf("join request with empty code")
		}
		return Intent{Kind: KindJoin, Code: code}, nil
	}
	return Intent{}, fmt.Errorf("no host/join intent in %q", fields[1])
}
