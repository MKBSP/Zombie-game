package director

import (
	"math/rand"
	"strings"
	"testing"
)

func TestGenCode_LengthAndAlphabet(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	code := GenCode(rng, nil)
	if len(code) != CodeLength {
		t.Fatalf("len(code) = %d, want %d", len(code), CodeLength)
	}
	for _, c := range code {
		if !strings.ContainsRune(CodeChars, c) {
			t.Errorf("code %q contains char %q not in alphabet", code, c)
		}
	}
}

func TestGenCode_AvoidsCollisions(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	existing := map[string]bool{}
	for i := 0; i < 200; i++ {
		code := GenCode(rng, existing)
		if existing[code] {
			t.Fatalf("GenCode returned %q which is already in use", code)
		}
		existing[code] = true
	}
}
