package director

import (
	"testing"
	"time"
)

func TestLoadConfig_Defaults(t *testing.T) {
	cfg := LoadConfig(func(string) string { return "" })
	if cfg.PublicPort != 8910 {
		t.Errorf("PublicPort = %d, want 8910", cfg.PublicPort)
	}
	if cfg.MaxGames != 5 {
		t.Errorf("MaxGames = %d, want 5", cfg.MaxGames)
	}
	if cfg.BasePort != 8911 {
		t.Errorf("BasePort = %d, want 8911", cfg.BasePort)
	}
	if cfg.IdleTimeout != 20*time.Second {
		t.Errorf("IdleTimeout = %v, want 20s", cfg.IdleTimeout)
	}
	if cfg.GodotBin != "godot" {
		t.Errorf("GodotBin = %q, want godot", cfg.GodotBin)
	}
	if cfg.ProjectPath != "/app" {
		t.Errorf("ProjectPath = %q, want /app", cfg.ProjectPath)
	}
}

func TestLoadConfig_OverridesFromEnv(t *testing.T) {
	env := map[string]string{
		"PORT":                   "4000",
		"MAX_GAMES":              "3",
		"INTERNAL_BASE_PORT":     "9000",
		"IDLE_SPAWN_TIMEOUT_SEC": "45",
		"GODOT_BIN":              "/usr/local/bin/godot",
		"PROJECT_PATH":           "/srv/game",
	}
	cfg := LoadConfig(func(k string) string { return env[k] })
	if cfg.PublicPort != 4000 {
		t.Errorf("PublicPort = %d, want 4000", cfg.PublicPort)
	}
	if cfg.MaxGames != 3 {
		t.Errorf("MaxGames = %d, want 3", cfg.MaxGames)
	}
	if cfg.BasePort != 9000 {
		t.Errorf("BasePort = %d, want 9000", cfg.BasePort)
	}
	if cfg.IdleTimeout != 45*time.Second {
		t.Errorf("IdleTimeout = %v, want 45s", cfg.IdleTimeout)
	}
	if cfg.GodotBin != "/usr/local/bin/godot" {
		t.Errorf("GodotBin = %q", cfg.GodotBin)
	}
	if cfg.ProjectPath != "/srv/game" {
		t.Errorf("ProjectPath = %q", cfg.ProjectPath)
	}
}

func TestLoadConfig_InvalidIntFallsBackToDefault(t *testing.T) {
	cfg := LoadConfig(func(k string) string {
		if k == "MAX_GAMES" {
			return "not-a-number"
		}
		return ""
	})
	if cfg.MaxGames != 5 {
		t.Errorf("MaxGames = %d, want default 5 on invalid input", cfg.MaxGames)
	}
}
