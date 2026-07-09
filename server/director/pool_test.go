package director

import (
	"math/rand"
	"sync"
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
	c.exit()
}

// exit simulates the process exiting on its own (room emptied / match ended).
func (c *fakeChild) exit() {
	select {
	case <-c.done:
	default:
		close(c.done)
	}
}

// spawnRecorder records the children a pool spawns. Thread-safe because the
// pool's reaper goroutine spawns replacements concurrently with test reads.
type spawnRecorder struct {
	mu       sync.Mutex
	children []*fakeChild
}

func (r *spawnRecorder) add(c *fakeChild) {
	r.mu.Lock()
	r.children = append(r.children, c)
	r.mu.Unlock()
}
func (r *spawnRecorder) len() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.children)
}
func (r *spawnRecorder) get(i int) *fakeChild {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.children[i]
}
func (r *spawnRecorder) last() *fakeChild {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.children[len(r.children)-1]
}

func newTestPool(cap int) (*Pool, *spawnRecorder) {
	rec := &spawnRecorder{}
	spawn := func(port int, code string) (Child, error) {
		fc := &fakeChild{port: port, code: code, done: make(chan struct{})}
		rec.add(fc)
		return fc, nil
	}
	p := NewPool(Config{
		Cap:      cap,
		Warm:     1,
		BasePort: 8911,
		Spawn:    spawn,
		Rng:      rand.New(rand.NewSource(1)),
	})
	return p, rec
}

// waitFor polls cond until true or the deadline, to observe reaper goroutines.
func waitFor(t *testing.T, cond func() bool, msg string) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal(msg)
		}
		time.Sleep(time.Millisecond)
	}
}

func TestPool_StartSpawnsWarmBuffer(t *testing.T) {
	p, _ := newTestPool(5)
	if err := p.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	if p.Count() != 1 {
		t.Errorf("warm buffer = %d children, want 1", p.Count())
	}
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
	got, ok := p.Join(code)
	if !ok {
		t.Fatal("Join failed for a freshly hosted code")
	}
	if got != child {
		t.Error("Join returned a different child than Host")
	}
}

func TestPool_HostUsesWarmChildInstantly(t *testing.T) {
	p, rec := newTestPool(5)
	if err := p.Start(); err != nil {
		t.Fatalf("Start: %v", err)
	}
	warm := rec.get(0)
	child, _, err := p.Host()
	if err != nil {
		t.Fatalf("Host: %v", err)
	}
	if child != warm {
		t.Error("Host did not hand out the pre-warmed child")
	}
}

func TestPool_JoinUnknownCode(t *testing.T) {
	p, _ := newTestPool(5)
	if _, ok := p.Join("ZZZZ"); ok {
		t.Error("Join succeeded for an unknown code")
	}
}

func TestPool_HostGivesDistinctPorts(t *testing.T) {
	p, _ := newTestPool(5)
	a, _, _ := p.Host()
	b, _, _ := p.Host()
	if a.Port() == b.Port() {
		t.Errorf("two hosted children share port %d", a.Port())
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

func TestPool_ReapOnExitRemovesAndRefills(t *testing.T) {
	p, rec := newTestPool(5)
	_, code, _ := p.Host() // spawns the hosted child + refills a warm one
	rec.get(0).exit()      // the hosted child ends

	waitFor(t, func() bool {
		_, ok := p.Join(code)
		return !ok
	}, "hosted child was not reaped after it exited")

	// The warm buffer is kept topped up after a reap.
	waitFor(t, func() bool { return p.Count() >= 1 }, "warm buffer not refilled after reap")
}

func TestPool_PortReusedAfterReap(t *testing.T) {
	p, rec := newTestPool(3)
	if err := p.Start(); err != nil { // warm child on 8911
		t.Fatalf("Start: %v", err)
	}
	firstPort := rec.get(0).Port()
	rec.get(0).exit() // free 8911

	// The refill spawns a replacement, which should reuse the freed port.
	waitFor(t, func() bool {
		return rec.len() >= 2 && rec.last().Port() == firstPort
	}, "freed port was not reused by the refill spawn")
}
