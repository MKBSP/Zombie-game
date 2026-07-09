package director

import "strings"

// RewriteRequestLine replaces the request target with "/" so the Godot child
// sees a vanilla root-path upgrade, identical to today's single-server setup —
// the routing query (?host / ?join) is the director's business, not the child's.
// A line that can't be split into three fields is returned unchanged (the caller
// has already validated it via ParseUpgrade).
func RewriteRequestLine(requestLine string) string {
	fields := strings.Fields(requestLine)
	if len(fields) < 3 {
		return requestLine
	}
	return fields[0] + " / " + fields[2]
}
