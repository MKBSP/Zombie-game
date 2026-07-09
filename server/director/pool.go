package director

import (
	"errors"
	"math/rand"
	"sync"
)

// ErrPoolFull is returned by Host when every slot is already in use.
var ErrPoolFull = errors.New("director: game pool is full")

// Child is one running single-match Godot server. The pool needs its port (to
// proxy to), its code (its room), a Done channel that closes when the process
// exits (so the pool can reap it), and a way to Kill it.
type Child interface {
	Port() int
	Code() string
	Done() <-chan struct{}
	Kill()
}

// SpawnFunc launches a child bound to internalPort seeded with the room code.
// It returns quickly (the process boots asynchronously); the director dials the
// child with retry, so a not-yet-booted child is fine.
type SpawnFunc func(internalPort int, code string) (Child, error)

// Config configures a Pool. Spawn and Rng are required.
type Config struct {
	Cap      int // max concurrent children (MAX_GAMES)
	Warm     int // ready-and-waiting children to keep for instant hosting (>=1)
	BasePort int // first internal child port; children take BasePort, BasePort+1, ...
	Spawn    SpawnFunc
	Rng      *rand.Rand
}

type entry struct {
	child  Child
	hosted bool // a host has claimed this child (vs. an idle warm one)
}

// Pool keeps a small buffer of pre-booted children ready so hosting is instant,
// spawns on demand up to the cap, and refills the buffer as children are taken
// or exit. Children are never simulated here — Spawn/Child are injected.
type Pool struct {
	mu        sync.Mutex
	cap       int
	warm      int
	basePort  int
	spawn     SpawnFunc
	rng       *rand.Rand
	entries   map[string]*entry // by room code
	usedPorts map[int]bool
}

// NewPool builds a Pool from cfg (Warm is clamped to [1, Cap]).
func NewPool(cfg Config) *Pool {
	warm := cfg.Warm
	if warm < 1 {
		warm = 1
	}
	if warm > cfg.Cap {
		warm = cfg.Cap
	}
	return &Pool{
		cap:       cfg.Cap,
		warm:      warm,
		basePort:  cfg.BasePort,
		spawn:     cfg.Spawn,
		rng:       cfg.Rng,
		entries:   map[string]*entry{},
		usedPorts: map[int]bool{},
	}
}

// Start spawns the initial warm buffer so the first host connects instantly.
func (p *Pool) Start() error {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.prewarmLocked()
}

// Host claims a room: it hands out a ready warm child if one exists, else spawns
// one on demand (reached via dial-retry once it boots). Returns ErrPoolFull when
// every slot is in use. After taking a warm child it refills the buffer.
func (p *Pool) Host() (Child, string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for code, e := range p.entries {
		if !e.hosted {
			e.hosted = true
			_ = p.prewarmLocked() // refill for the next host
			return e.child, code, nil
		}
	}
	if len(p.entries) >= p.cap {
		return nil, "", ErrPoolFull
	}
	child, code, err := p.spawnChildLocked()
	if err != nil {
		return nil, "", err
	}
	p.entries[code].hosted = true
	return child, code, nil
}

// Join returns the live child owning code, if any.
func (p *Pool) Join(code string) (Child, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	e, ok := p.entries[code]
	if !ok {
		return nil, false
	}
	return e.child, true
}

// Count is the number of live children (for tests and diagnostics).
func (p *Pool) Count() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.entries)
}

// prewarmLocked tops the warm buffer up to Warm ready children, without exceeding
// the pool cap.
func (p *Pool) prewarmLocked() error {
	for p.freeCountLocked() < p.warm && len(p.entries) < p.cap {
		if _, _, err := p.spawnChildLocked(); err != nil {
			return err
		}
	}
	return nil
}

func (p *Pool) freeCountLocked() int {
	n := 0
	for _, e := range p.entries {
		if !e.hosted {
			n++
		}
	}
	return n
}

func (p *Pool) spawnChildLocked() (Child, string, error) {
	code := GenCode(p.rng, p.existingCodesLocked())
	port := p.freePortLocked()
	child, err := p.spawn(port, code)
	if err != nil {
		return nil, "", err
	}
	p.usedPorts[port] = true
	p.entries[code] = &entry{child: child}
	go p.reapOnExit(code, child)
	return child, code, nil
}

func (p *Pool) reapOnExit(code string, child Child) {
	<-child.Done()
	p.mu.Lock()
	// Only remove if this exact child still owns the code (guard a stale reaper
	// racing a reused code/port).
	if e, ok := p.entries[code]; ok && e.child == child {
		delete(p.usedPorts, child.Port())
		delete(p.entries, code)
	}
	_ = p.prewarmLocked() // replace the departed child to keep the buffer warm
	p.mu.Unlock()
}

func (p *Pool) existingCodesLocked() map[string]bool {
	m := make(map[string]bool, len(p.entries))
	for code := range p.entries {
		m[code] = true
	}
	return m
}

func (p *Pool) freePortLocked() int {
	for port := p.basePort; ; port++ {
		if !p.usedPorts[port] {
			return port
		}
	}
}
