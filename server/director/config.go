package director

import (
	"strconv"
	"time"
)

// RuntimeConfig is the director's resolved configuration.
type RuntimeConfig struct {
	PublicPort  int           // the port clients connect to (Railway's $PORT)
	MaxGames    int           // pool cap
	BasePort    int           // first internal child port
	IdleTimeout time.Duration // kill a spawned-but-never-active child after this
	GodotBin    string        // path to the Godot binary
	ProjectPath string        // path to the game project
}

// LoadConfig resolves configuration from environment variables (via the injected
// getenv), applying defaults for anything unset or malformed.
func LoadConfig(getenv func(string) string) RuntimeConfig {
	return RuntimeConfig{
		PublicPort:  envInt(getenv, "PORT", 8910),
		MaxGames:    envInt(getenv, "MAX_GAMES", 5),
		BasePort:    envInt(getenv, "INTERNAL_BASE_PORT", 8911),
		IdleTimeout: time.Duration(envInt(getenv, "IDLE_SPAWN_TIMEOUT_SEC", 20)) * time.Second,
		GodotBin:    envStr(getenv, "GODOT_BIN", "godot"),
		ProjectPath: envStr(getenv, "PROJECT_PATH", "/app"),
	}
}

func envInt(getenv func(string) string, key string, def int) int {
	if v := getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func envStr(getenv func(string) string, key, def string) string {
	if v := getenv(key); v != "" {
		return v
	}
	return def
}
