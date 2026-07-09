package director

import "testing"

func TestRewriteRequestLine_StripsQuery(t *testing.T) {
	got := RewriteRequestLine("GET /?join=AB3K HTTP/1.1")
	if got != "GET / HTTP/1.1" {
		t.Errorf("got %q, want %q", got, "GET / HTTP/1.1")
	}
}

func TestRewriteRequestLine_HostQueryStripped(t *testing.T) {
	got := RewriteRequestLine("GET /?host=1 HTTP/1.1")
	if got != "GET / HTTP/1.1" {
		t.Errorf("got %q, want %q", got, "GET / HTTP/1.1")
	}
}

func TestRewriteRequestLine_PreservesProtocol(t *testing.T) {
	got := RewriteRequestLine("GET /?host=1 HTTP/1.0")
	if got != "GET / HTTP/1.0" {
		t.Errorf("got %q, want %q", got, "GET / HTTP/1.0")
	}
}

func TestRewriteRequestLine_AlreadyRootUnchanged(t *testing.T) {
	got := RewriteRequestLine("GET / HTTP/1.1")
	if got != "GET / HTTP/1.1" {
		t.Errorf("got %q, want %q", got, "GET / HTTP/1.1")
	}
}
