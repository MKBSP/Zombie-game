// Command director is the public entry point for the zombie-game server on
// Railway. It listens on $PORT and routes each client's WebSocket connection to
// a pooled single-match Godot server, keeping a warm buffer ready so hosting is
// instant and refilling it as games start and end. See docs/superpowers/specs.
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

func main() {
	cfg := director.LoadConfig(os.Getenv)

	pool := director.NewPool(director.Config{
		Cap:      cfg.MaxGames,
		Warm:     cfg.WarmChildren,
		BasePort: cfg.BasePort,
		Spawn:    director.SpawnGodot(cfg.GodotBin, cfg.ProjectPath),
		Rng:      rand.New(rand.NewSource(time.Now().UnixNano())),
	})

	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", cfg.PublicPort))
	if err != nil {
		log.Fatalf("[director] failed to listen on :%d — %v", cfg.PublicPort, err)
	}
	log.Printf("[director] listening on :%d — pool cap %d, warm %d, children from port %d, godot=%q path=%q",
		cfg.PublicPort, cfg.MaxGames, cfg.WarmChildren, cfg.BasePort, cfg.GodotBin, cfg.ProjectPath)

	// Pre-boot the warm buffer so the first host connects instantly.
	if err := pool.Start(); err != nil {
		log.Printf("[director] warning: could not pre-warm the pool: %v", err)
	}

	srv := director.NewServer(pool)
	if err := srv.Serve(ln); err != nil {
		log.Fatalf("[director] serve stopped: %v", err)
	}
}
