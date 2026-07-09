package director

import "testing"

func TestParseUpgrade_Host(t *testing.T) {
	got, err := ParseUpgrade("GET /?host=1 HTTP/1.1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Kind != KindHost {
		t.Errorf("Kind = %v, want KindHost", got.Kind)
	}
	if got.Code != "" {
		t.Errorf("Code = %q, want empty for a host", got.Code)
	}
}

func TestParseUpgrade_Join(t *testing.T) {
	got, err := ParseUpgrade("GET /?join=AB3K HTTP/1.1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Kind != KindJoin {
		t.Errorf("Kind = %v, want KindJoin", got.Kind)
	}
	if got.Code != "AB3K" {
		t.Errorf("Code = %q, want AB3K", got.Code)
	}
}

func TestParseUpgrade_JoinLowercaseIsUppercased(t *testing.T) {
	got, err := ParseUpgrade("GET /?join=ab3k HTTP/1.1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Code != "AB3K" {
		t.Errorf("Code = %q, want AB3K (uppercased)", got.Code)
	}
}

func TestParseUpgrade_NoIntentIsError(t *testing.T) {
	if _, err := ParseUpgrade("GET / HTTP/1.1"); err == nil {
		t.Error("expected error for a request with no host/join intent, got nil")
	}
}

func TestParseUpgrade_JoinWithoutCodeIsError(t *testing.T) {
	if _, err := ParseUpgrade("GET /?join= HTTP/1.1"); err == nil {
		t.Error("expected error for join with an empty code, got nil")
	}
}

func TestParseUpgrade_MalformedLineIsError(t *testing.T) {
	if _, err := ParseUpgrade("not an http request line"); err == nil {
		t.Error("expected error for a malformed request line, got nil")
	}
}
