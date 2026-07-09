package director

import (
	"errors"
	"math/rand"
	"sync"
	"time"
)

// ErrPoolFull is returned by Host when the pool is already at its cap.
var ErrPoolFull = errors.New("director: game pool is full")

// Child is one running single-match Godot server. The pool only needs its port
// (to proxy to), its code (its room), a Done channel that closes when the
// process exits (so the pool can reap it), and a way to Kill it.
type Child interface {
	Port() int
	Code() string
	Done() <-chan struct{}
	Kill()
}

// SpawnFunc launches a child bound to internalPort seeded with the room code.
type SpawnFunc func(internalPort int, code string) (Child, error)

// Config configures a Pool. Spawn and Rng are required; the rest have sensible
// production defaults applied by NewPool.
type Config struct {
	Cap      int           // max concurrent children (MAX_GAMES)
	BasePort int           // first internal port; children take BasePort, BasePort+1, ...
	Idle     time.Duration // kill a spawned-but-never-active child after this long
	Spawn    SpawnFunc
	Rng      *rand.Rand
}

type entry struct {
	child     Child
	spawnedAt time.Time
	active    bool
}

// Pool manages the set of live single-match children and their room codes.
type Pool struct {
	mu        sync.Mutex
	cap       int
	basePort  int
	idle      time.Duration
	spawn     SpawnFunc
	rng       *rand.Rand
	now       func() time.Time
	entries   map[string]*entry // by room code
	usedPorts map[int]bool
}

// NewPool builds a Pool from cfg.
func NewPool(cfg Config) *Pool {
	return &Pool{
		cap:       cfg.Cap,
		basePort:  cfg.BasePort,
		idle:      cfg.Idle,
		spawn:     cfg.Spawn,
		rng:       cfg.Rng,
		now:       time.Now,
		entries:   map[string]*entry{},
		usedPorts: map[int]bool{},
	}
}

// Host allocates a fresh room: it generates a code, picks a free internal port,
// spawns a child, and registers it. Returns ErrPoolFull if at cap.
func (p *Pool) Host() (Child, string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.entries) >= p.cap {
		return nil, "", ErrPoolFull
	}
	code := GenCode(p.rng, p.existingCodesLocked())
	port := p.freePortLocked()
	child, err := p.spawn(port, code)
	if err != nil {
		return nil, "", err
	}
	p.usedPorts[port] = true
	p.entries[code] = &entry{child: child, spawnedAt: p.now()}
	go p.reapOnExit(code, child)
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

// MarkActive records that a connection was successfully proxied to code's child,
// so the idle sweep will not kill it.
func (p *Pool) MarkActive(code string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if e, ok := p.entries[code]; ok {
		e.active = true
	}
}

// Sweep kills and removes children that were spawned but never became active
// within the idle timeout — a backstop for a host that abandons before playing.
func (p *Pool) Sweep() {
	p.mu.Lock()
	toKill := []Child{}
	for code, e := range p.entries {
		if !e.active && p.now().Sub(e.spawnedAt) >= p.idle {
			toKill = append(toKill, e.child)
			p.removeLocked(code)
		}
	}
	p.mu.Unlock()
	for _, c := range toKill {
		c.Kill()
	}
}

// Count is the number of live children (for tests and diagnostics).
func (p *Pool) Count() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.entries)
}

func (p *Pool) reapOnExit(code string, child Child) {
	<-child.Done()
	p.mu.Lock()
	// Only remove if this exact child still owns the code (guard against a reused
	// code/port racing with a stale reaper).
	if e, ok := p.entries[code]; ok && e.child == child {
		p.removeLocked(code)
	}
	p.mu.Unlock()
}

func (p *Pool) removeLocked(code string) {
	if e, ok := p.entries[code]; ok {
		delete(p.usedPorts, e.child.Port())
		delete(p.entries, code)
	}
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
