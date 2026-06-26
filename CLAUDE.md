# CLAUDE.md — read this first

Entry point for AI agents working on **Zombie Game** (Godot 4.6.3). Read these
three files before exploring the tree; they exist so you don't have to scan
every file each session. Keep them current as part of your work.

| File | What it answers |
|------|-----------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Where code lives, how systems fit together, conventions |
| [PROJECT.md](PROJECT.md) | What the game is, current status, how to run/test it |
| [CHANGELOG.md](CHANGELOG.md) | What was built, phase by phase |

## Fast facts
- **Engine:** Godot 4.6.3 (GL Compatibility, 2D). Main scene: `scenes/ui/main_menu.tscn`.
- **Editing:** A live editor is usually running — prefer the **godot-ai MCP**
  (`script_patch`, `node_*`, `scene_*`, `test_run`, `editor_screenshot`) over
  blind file edits. Check `editor_state` first.
- **Tuning:** `scripts/balance.gd` is the single source of truth for every
  gameplay number. Change values there, not scattered in scenes.
- **Ignore `addons/godot_ai/`** — that's the MCP plugin (tooling), not game code.
- **Design specs & plans** for each phase live in `docs/`.

## House rules
- **No `Co-Authored-By` / Claude attribution in commit messages.**
- Don't commit or push unless asked.
- After meaningful changes, add a line to CHANGELOG.md and update
  ARCHITECTURE.md / PROJECT.md if structure or status changed.

## When you finish a unit of work
1. Run the relevant headless tests (`test/`) via the MCP `test_run`.
2. Update CHANGELOG.md (and the docs above if anything structural shifted).
