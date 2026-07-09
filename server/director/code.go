package director

import (
	"math/rand"
	"strings"
)

// Room-code shape mirrors scripts/network.gd so codes look the same to players:
// no ambiguous characters (0/O, 1/I), four chars long.
const (
	CodeChars  = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	CodeLength = 4
)

// GenCode returns a fresh room code not present in existing. existing may be nil.
// The director is the sole code authority, so collisions are avoided here rather
// than in the Godot children.
func GenCode(rng *rand.Rand, existing map[string]bool) string {
	for {
		var b strings.Builder
		for i := 0; i < CodeLength; i++ {
			b.WriteByte(CodeChars[rng.Intn(len(CodeChars))])
		}
		code := b.String()
		if existing == nil || !existing[code] {
			return code
		}
	}
}
