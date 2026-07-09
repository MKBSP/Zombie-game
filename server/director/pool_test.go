package director

import (
	"math/rand"
	"testing"
	"time"
)

// fakeChild stands in for a real Godot child process in tests.
type fakeChild struct {
	port   int
	code   string
	done   chan struct{}
	killed bool
}

func (c *fakeChild) Port() int             { return c.port }
func (c *fakeChild) Code() string          { return c.code }
func (c *fakeChild) Done() <-chan struct{} { return c.done }
func (c *fakeChild) Kill() {
	c.killed = true
	select {
	case <-c.done:
	default:
		close(c.done)
	}
}

// exit simulates the process exiting on its own (room emptied).
func (c *fakeChild) exit() {
	select {
	case <-c.done:
	default:
		close(c.done)
	}
}

func newTestPool(cap int) (*Pool, *[]*fakeChild) {
	spawned := &[]*fakeChild{}
	spawn := func(port int, code string) (Child, error) {
		fc := &fakeChild{port: port, code: code, done: make(chan struct{})}
		*spawned = append(*spawned, fc)
		return fc, nil
	}
	p := NewPool(Config{
		Cap:      cap,
		BasePort: 8911,
		Idle:     time.Minute,
		Spawn:    spawn,
		Rng:      rand.New(rand.NewSource(1)),
	})
	return p, spawned
}

func TestPool_HostAllocatesJoinableRoom(t *testing.T) {
	p, _ := newTestPool(5)
	child, code, err := p.Host()
	if err != nil {
		t.Fatalf("Host: %v", err)
	}
	if code == "" {
		t.Fatal("Host returned an empty code")
	}
	if child.Port() != 8911 {
		t.Errorf("first child port = %d, want 8911", child.Port())
	}
	got, ok := p.Join(code)
	if !ok {
		t.Fatal("Join failed for a freshly hosted code")
	}
	if got != child {
		t.Error("Join returned a different child than Host")
	}
}

func TestPool_JoinUnknownCode(t *testing.T) {
	p, _ := newTestPool(5)
	if _, ok := p.Join("ZZZZ"); ok {
		t.Error("Join succeeded for an unknown code")
	}
}

func TestPool_DistinctPortsPerChild(t *testing.T) {
	p, _ := newTestPool(5)
	a, _, _ := p.Host()
	b, _, _ := p.Host()
	if a.Port() == b.Port() {
		t.Errorf("two children share port %d", a.Port())
	}
}

func TestPool_HostAtCapIsRefused(t *testing.T) {
	p, _ := newTestPool(2)
	if _, _, err := p.Host(); err != nil {
		t.Fatalf("Host 1: %v", err)
	}
	if _, _, err := p.Host(); err != nil {
		t.Fatalf("Host 2: %v", err)
	}
	if _, _, err := p.Host(); err == nil {
		t.Error("Host at cap should be refused, got nil error")
	}
}

func TestPool_ReapOnChildExit(t *testing.T) {
	p, spawned := newTestPool(5)
	_, code, _ := p.Host()
	(*spawned)[0].exit()

	// The reaper runs in a goroutine; wait briefly for the registry to clear.
	deadline := time.Now().Add(time.Second)
	for {
		if _, ok := p.Join(code); !ok {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("child was not reaped after it exited")
		}
		time.Sleep(time.Millisecond)
	}
}

func TestPool_PortReusedAfterReap(t *testing.T) {
	p, spawned := newTestPool(5)
	a, _, _ := p.Host()
	firstPort := a.Port()
	(*spawned)[0].exit()

	deadline := time.Now().Add(time.Second)
	for p.Count() != 0 {
		if time.Now().After(deadline) {
			t.Fatal("child not reaped")
		}
		time.Sleep(time.Millisecond)
	}
	b, _, _ := p.Host()
	if b.Port() != firstPort {
		t.Errorf("reused port = %d, want the freed %d", b.Port(), firstPort)
	}
}

func TestPool_SweepKillsIdleUnmarkedChild(t *testing.T) {
	p, spawned := newTestPool(5)
	_, code, _ := p.Host()

	now := time.Now()
	p.now = func() time.Time { return now.Add(2 * time.Minute) } // past the 1m idle
	p.Sweep()

	if !(*spawned)[0].killed {
		t.Error("idle unmarked child was not killed by Sweep")
	}
	if _, ok := p.Join(code); ok {
		t.Error("idle child still joinable after Sweep")
	}
}

func TestPool_SweepSparesActiveChild(t *testing.T) {
	p, spawned := newTestPool(5)
	_, code, _ := p.Host()
	p.MarkActive(code)

	now := time.Now()
	p.now = func() time.Time { return now.Add(2 * time.Minute) }
	p.Sweep()

	if (*spawned)[0].killed {
		t.Error("active child was killed by Sweep")
	}
	if _, ok := p.Join(code); !ok {
		t.Error("active child no longer joinable after Sweep")
	}
}
