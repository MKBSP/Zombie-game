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

## Gotchas — read before running Godot from the CLI or driving the editor
- **NEVER run a headless `Godot --import` or `Godot ... --script test/x.gd`
  while the live editor is open on this project.** Two Godot processes fighting
  over `.godot/` can wipe it, triggering *"Project data folder (.godot) is
  missing — please restart editor."* It's only cache (gitignored, no
  source-of-truth), so the fix is just **Restart** in the editor — but it's
  disruptive. To run the `test/` scripts, close the editor first, or run them in
  a throwaway copy of the repo.
- **Headless `test/` scripts** (`Godot --headless --path . --script test/x.gd`,
  `SceneTree`-style, exit 0 = pass) **cannot resolve `class_name` globals that
  extend scene types** (e.g. `Pickup extends Area2D`, and `AimModel`/`Weapons`
  in some cache states) — you get `Parse Error: Identifier "X" not declared`.
  Keep pure logic in `extends RefCounted` static helpers (e.g. `LootTable`,
  `Interact`), and in test files reference helpers via `load("res://...")`, not
  the bare `class_name`. Older tests that ref class_names directly may silently
  fail to load in this state — that's pre-existing, not your regression.
- **MCP game-capture bridge is flaky:** `editor_screenshot source=game` and
  `game_manage get_scene_tree` can time out with `game_capture_ready:false` even
  when the game boots fine (logs show an `ignored mcp:hello` handshake race).
  Fall back to `logs_read source=all` (zero `SCRIPT ERROR` = clean boot) plus an
  owner playtest for visual confirmation.
- **New image assets:** the MCP `filesystem_manage reimport` only updates
  *already-known* files. A brand-new PNG needs a one-time import to generate its
  `.import` (commit the `.import`; `.godot/` itself stays gitignored). With the
  editor open, let the editor import it on focus rather than running headless
  `--import` (see the first bullet).

## When you finish a unit of work
1. Verify behavior in the **live editor** (MCP `project_run` + `logs_read`, or an
   owner playtest). For pure-logic helpers, run their `test/` scripts — but only
   with the editor closed (see Gotchas).
2. Update CHANGELOG.md (and the docs above if anything structural shifted).
