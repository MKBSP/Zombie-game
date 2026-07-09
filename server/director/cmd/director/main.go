// Command director is the public entry point for the zombie-game server on
// Railway. It listens on $PORT and routes each client's WebSocket connection to
// a pooled single-match Godot server, spawning and reaping those children as
// games start and end. See docs/superpowers/specs for the design.
package main

import (
	"fmt"
	"log"
	"math/rand"
	"net"
	"os"
	"time"

	director "zombie-director"
)

const sweepInterval = 5 * time.Second

func main() {
	cfg := director.LoadConfig(os.Getenv)

	pool := director.NewPool(director.Config{
		Cap:      cfg.MaxGames,
		BasePort: cfg.BasePort,
		Idle:     cfg.IdleTimeout,
		Spawn:    director.SpawnGodot(cfg.GodotBin, cfg.ProjectPath),
		Rng:      rand.New(rand.NewSource(time.Now().UnixNano())),
	})

	// Backstop sweep for hosts that spawn a child then abandon before playing.
	go func() {
		for range time.Tick(sweepInterval) {
			pool.Sweep()
		}
	}()

	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", cfg.PublicPort))
	if err != nil {
		log.Fatalf("[director] failed to listen on :%d — %v", cfg.PublicPort, err)
	}
	log.Printf("[director] listening on :%d — pool cap %d, children from port %d, godot=%q path=%q",
		cfg.PublicPort, cfg.MaxGames, cfg.BasePort, cfg.GodotBin, cfg.ProjectPath)

	srv := director.NewServer(pool)
	if err := srv.Serve(ln); err != nil {
		log.Fatalf("[director] serve stopped: %v", err)
	}
}
