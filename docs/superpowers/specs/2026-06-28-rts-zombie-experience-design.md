# RTS Zombie Experience (Age-of-Empires-style) — Design

**Date:** 2026-06-28
**Status:** Approved, ready for implementation plan

## Summary

Deepen the **zombie controller** side of the game into a proper RTS experience,
closer to *Age of Empires*. The zombie player commands the horde from a top-down
camera and now gets: discrete attacks (zombies *hit* on a cooldown instead of
draining the shooter continuously), a stance system (orderable behaviors per
unit), smarter auto-attack targeting, per-unit health bars, a populating
minimap, sound/combat feedback on both the minimap and the world view, and
solid unit separation so units no longer stand on or pass through each other.

The **two-layer fog already exists** (`FogZombieController`, rendered via
`ZCFogRect`): `unexplored` (black) → `explored` (dimmed) → `visible` (bright).
This design *reuses* that fog data for the minimap and only verifies/polishes the
fog itself — it is not rebuilt.

All AI, combat, and targeting remain **server-authoritative** (as today); clients
only render. Every new tunable lives in `scripts/balance.gd`.

## Scope and build order

One combined design, built in dependency order as phases. Each phase is
independently verifiable in the live editor before the next begins.

| Phase | Subsystem | Depends on |
|------|-----------|-----------|
| A | Discrete combat (per-hit damage + cooldown; `hp` replication) | — |
| B | Unit separation (no overlap, no pass-through) | — |
| C | Stance state machine + auto-attack targeting | A, B |
| D | Stance toolbar UI + placement + control groups | C |
| E | Zombie health bars | A |
| F | Minimap (terrain, blips, ghost blips, under-attack, gunshot ripples, click-to-jump) | fog (exists) |
| G | World-view gunshot feedback + sound aggro | C, F-infra |
| H | Fog verify/polish | — |

A and B have no dependencies and can be done first in either order.

---

## Phase A — Discrete combat

**Problem:** `zombie.gd` and `master_zombie.gd` call
`target.take_damage(contact_dps * delta)` every physics frame while in contact —
a smooth continuous drain. We want discrete *hits*, each with a damage value.

**Change:** every attacking unit gets an attack cooldown.

- New per-variant `Balance` fields: `damage_per_hit` and `attack_interval`
  (seconds). Derived to keep DPS roughly where it is today, then tunable:
  | Unit | now (`contact_dps`) | `damage_per_hit` | `attack_interval` | ≈ DPS |
  |------|------|------|------|------|
  | standard | 12 | 15 | 1.0 | 15 |
  | fast | 18 | 12 | 0.7 | ~17 |
  | fat | 60 | 45 | 1.3 | ~35 |
  | master | 12 | 20 | 1.2 | ~17 |
  (These are starting numbers; balance is owner's call after playtest.)
- Each unit tracks `_attack_cooldown: float`, decremented each physics frame.
  When the target is within `contact_px` **and** `_attack_cooldown <= 0.0`:
  deal one hit (`target.take_damage(damage_per_hit)`), reset cooldown to
  `attack_interval`, emit a `dealt_hit` / play a brief lunge nudge toward the
  target, and the target flashes (existing shooter hurt-flash if present, else a
  short `modulate` flash).
- `contact_dps` and `_check_contact_damage` are replaced by this. The legacy
  `contact_dps` field can stay in `Balance` only if still referenced elsewhere;
  otherwise remove.

**Replication of `hp`:** health bars (Phase E) and the under-attack minimap pulse
(Phase F) must render on every peer, but zombie `hp` currently only changes
server-side. Verify whether the zombie/master scenes carry a
`MultiplayerSynchronizer` that replicates `hp`; if not, add `hp` (and `is_dead`)
to a synchronizer so clients see current health. This is a prerequisite for
Phases E and F and is owned by Phase A.

**Test:** a headless logic test for the cooldown gate (pure-math helper:
`should_hit(distance, contact_px, cooldown) -> bool`) following the
`RefCounted`-static-helper + `load()` convention. In-editor: shooter HP now
drops in steps, not a smooth slide.

---

## Phase B — Unit separation

**Problem:** zombies and NPCs can occupy the same spot and walk through each
other. We want soft RTS-style separation: units push apart and flow around one
another without sticking or jittering.

**Approach:** use `NavigationAgent2D` **avoidance** (Godot's RVO), which is built
for exactly this and produces smooth flocking rather than hard blocking.

- On zombie and NPC `NavigationAgent2D`: enable `avoidance_enabled`, set
  `radius` ≈ body radius, set an `avoidance_layers`/`avoidance_mask` so units
  see each other (and optionally the shooter as an obstacle), and route motion
  through the `velocity_computed` signal: call `set_velocity(desired)` and apply
  the **safe** velocity returned by the callback in `move_and_slide()`.
- Keep static obstacles (buildings/props) handled by the existing navigation
  mesh; avoidance is for the dynamic agent-vs-agent case.
- New `Balance.SEPARATION` block: `agent_radius`, `neighbor_distance`,
  `max_neighbors`, `time_horizon` (sane RVO defaults, tunable).

**Why avoidance over physics collision:** hard `CharacterBody2D` collisions
between many same-layer agents cause stuck clusters and jitter on shared nav
targets; RVO avoidance is the standard RTS solution and keeps the horde fluid.

**Test:** in-editor — send a large group to one point; they should pack densely
without overlapping sprites and without freezing. No `SCRIPT ERROR` on boot.

---

## Phase C — Stance state machine + auto-attack targeting

A stance is a **movement pattern × on-sight reaction**, implemented as a small
server-side state machine on each zombie. Default spawn stance = **Aggressive**
(preserves today's feel).

### Shared targeting helper

`acquire_target()` returns the **nearest visible enemy** within
`vision_range × 64px`, scanning groups `shooter` + `npcs`, skipping dead and
mid-conversion NPCs. NPCs are "attacked" by reaching them — contact already
triggers conversion via the NPC's zone (`_on_zone_body_entered`). Runs
server-side only.

### Stances

| Stance | Movement | On enemy seen |
|--------|----------|---------------|
| **Aggressive** | roam / chase acquired target | chase + attack (converts NPCs on contact) |
| **Hold** | rooted on current tile | nothing — ignores fire, never chases |
| **Patrol (Attack)** | loop A↔B | break off, chase + attack, then resume patrol from nearest point |
| **Patrol (Flee)** | loop A↔B | run to `flee_point`; resume patrol once no enemy in vision |
| **Skittish** | hold at post | bolt to `flee_point` and stay |
| **Flee-to-point** | go to point now | never engages |

### Per-unit data

`stance` (enum), `patrol_a: Vector2`, `patrol_b: Vector2`, `flee_point:
Vector2`, plus internal `_patrol_leg` toggle. `_physics_process` replaces the
current `command_mode`/`target` branch with a `match stance` evaluation that sets
the nav target and decides whether to attack.

### Move command interaction

Right-click move (`rpc_command_move`) still works and **temporarily overrides**
the stance (one-shot move), then the unit reverts to its stance on arrival.
`Balance.STANCE` holds tunables (e.g. `patrol_arrive_px`, `flee_safe_seconds`
before a Patrol-Flee unit resumes).

**Test:** logic helper for stance transitions where extractable; in-editor,
issue each stance and confirm behavior (hold ignores fire, patrol loops, skittish
flees on sight, etc.).

---

## Phase D — Stance toolbar UI

Matches the existing Fast/Fat merge-button pattern in `ZCOverlay`.

- A **stance panel** (buttons: Aggressive, Hold, Patrol (Attack), Patrol (Flee),
  Skittish, Flee-to-point), visible when ≥1 zombie is selected.
- Stances needing points enter a **placement mode**: click a stance → cursor
  shows it's awaiting a click → click pt1 (and pt2 for patrol). Sends an RPC
  mirroring `rpc_command_move` (`rpc_set_stance(names, stance, p1, p2)`).
- **Patrol/flee preview:** while placing and while a stance unit is selected,
  draw the patrol line (A↔B) or flee target marker for the selection
  (extend `selectrion_drawer.gd` or a sibling overlay drawer).
- **Stance glyph:** a tiny icon under each *selected* zombie showing its current
  stance.
- **Control groups (Ctrl+1–9):** save the current selection to a number; press
  the number to recall it. Standard RTS. Stored in `ZombieController`.

**Test:** in-editor — each button assigns the stance to the selection; placement
clicks register; control groups save/recall.

---

## Phase E — Zombie health bars

A reusable `HealthBar` Node2D drawn above each unit.

- Shown only when `hp < max_hp` **or** the unit is selected (cleanest screen for
  a large horde).
- **Counter-rotated** (or `top_level`) so it stays horizontal even though zombies
  rotate to face travel direction.
- Reads the replicated `hp` / `max_hp` (Phase A). Small green→red fill.
- Reusable across standard/fast/fat/master (and optionally NPCs later).

**Test:** in-editor — damage a zombie; bar appears and depletes in steps; hidden
again only if it heals/at full; always shown while selected.

---

## Phase F — Minimap

A clickable `Control` in a screen corner (zombie view only) that reads the
**existing** `fog_zc.tile_states` (47×47) plus live entity positions.

- **Terrain layer:** unexplored = black, explored = dim terrain tint, visible =
  bright. Derived from `tile_states` so the minimap *populates as you explore*.
- **Own units:** zombies always blipped (their own color).
- **Enemy blips (shooter / NPCs):** shown **only on currently-visible tiles**
  (`STATE_VISIBLE`). Lose sight of an area and the live blip disappears — real
  scouting tension.
- **Last-known-position ghost blips:** when an enemy leaves vision, leave a
  fading grey blip at its last-seen tile (fades over `Balance.MINIMAP.ghost_fade`
  seconds).
- **Under-attack pulse:** when a zombie takes damage (Phase A `dealt_hit` / a
  `took_damage` signal), flash a red pulsing blip at its location for a short
  window — the AoE "your units are under attack" cue.
- **Gunshot ripple:** a subtle expanding ring at a **fuzzed** position (small
  random jitter so it reads as "the general area," not a pinpoint) whenever the
  shooter fires (see Shared gunshot infra). Deliberately understated.
- **Click / drag to jump:** clicking the minimap moves `zc_camera` to the
  corresponding world position (clamped to map bounds).
- New `Balance.MINIMAP` block: corner/size, blip sizes, `ghost_fade`,
  `under_attack_seconds`, ripple opacity/speed, gunshot position jitter.

### Shared gunshot ("noise event") infrastructure

Introduced here, consumed by F and G. When the shooter fires, broadcast a noise
event `{position, strength}` to all peers (hook the existing fire path / bullet
spawn; one lightweight `@rpc("authority","call_local")`). The zombie client feeds
it to: the minimap ripple (F), the world-view ripple and sound aggro (G).

**Test:** in-editor — explore and watch terrain fill in; enemy blips appear only
while watched and leave fading ghosts; shooting shows a faint map ripple; a
damaged zombie shows a red pulse; clicking the map recenters the camera.

---

## Phase G — World-view gunshot feedback + sound aggro

Same noise event, two more consumers in the zombie's main (non-map) view:

- **World ripple:** if `zc_camera` is within `Balance.AGGRO.world_ripple_px` of a
  gunshot, render a subtle wobble/ripple emanating from the (fuzzed) shot source
  — a soft, brief distortion or expanding faint ring, not an obvious flash. Tunes
  for subtlety in `Balance`.
- **Sound aggro:** Aggressive zombies within `Balance.AGGRO.alert_radius_px` of a
  gunshot get alerted toward the shot (acquire/seek that area), rewarding stealth
  and making Hold/ambush stances meaningfully different. Non-Aggressive stances
  ignore the aggro (Hold stays put even when fired upon — by design).

New `Balance.AGGRO` block: `world_ripple_px`, ripple visuals, `alert_radius_px`,
`alert_seconds`.

**Test:** in-editor — fire near the zombie camera → faint world ripple; nearby
Aggressive zombies turn toward the shot; Hold-stance zombies do not react.

---

## Phase H — Fog verify/polish

The two-layer fog already exists and renders. This phase only:

- Confirms `ZCFogRect` covers the full map and renders all three states
  correctly at all zoom levels.
- Minor tuning of `Balance.FOG_ZC` dimming if needed (e.g. `vis_explored`).
- No rebuild.

---

## Data / balance summary (new blocks in `balance.gd`)

- Per-variant `damage_per_hit`, `attack_interval` (added to `ZOMBIE/FAST/FAT/MASTER`).
- `SEPARATION` — RVO avoidance tunables.
- `STANCE` — arrival radii, flee-safe timing.
- `MINIMAP` — placement/size, blip + ghost + under-attack + ripple tunables.
- `AGGRO` — world ripple + sound-aggro radii/visuals.

## Files touched (anticipated)

- `scenes/zombie/zombie.gd`, `scenes/zombie/master_zombie.gd` — discrete combat,
  stance state machine, avoidance velocity, health bar, `took_damage` signal.
- `scenes/zombie/*.tscn` — `NavigationAgent2D` avoidance flags, `HealthBar`
  child, `MultiplayerSynchronizer` `hp`/`is_dead` if missing.
- `scenes/npc/npc_human.gd` + `.tscn` — avoidance (separation only).
- `scripts/zombie_controller.gd` — stance commands, control groups, minimap
  click-to-jump wiring, noise-event consumers.
- `scenes/world/world.gd` — `rpc_set_stance`, gunshot noise broadcast hook.
- `scenes/world/selectrion_drawer.gd` (or sibling) — patrol/flee path preview,
  stance glyphs.
- New: `scripts/health_bar.gd`, `scripts/minimap.gd` (+ minimap `Control` in
  `ZCOverlay`), stance toolbar nodes in `world.tscn` `ZCOverlay`.
- `scripts/balance.gd` — all new tunable blocks.

## Non-goals / YAGNI

- No rebuild of the existing fog.
- No NPC health bars in this pass (component is reusable later).
- No new zombie variants or merge changes.
- No pathfinding overhaul beyond adding agent avoidance.

## Testing constraints (project-specific)

- Keep new pure logic in `extends RefCounted` static helpers and reference them
  via `load("res://...")` in `test/` files — headless runners can't resolve
  `class_name` globals that extend scene types (see `CLAUDE.md` Gotchas).
- Never run headless `--import` / `--script` while the live editor is open on
  this project (`.godot` cache wipe risk).
- Verify visuals via an owner playtest / MCP `project_run` + `logs_read` (the
  game-capture screenshot bridge is flaky).
