# Two-Axis Stances (Combat × Movement) — Design

**Date:** 2026-07-03
**Status:** Approved, building directly (replaces the single-enum stance system)

## Summary

Replace the single `Zombie.Stance` enum with two independent axes so behaviors
compose: a **combat stance** (how it fights) and a **movement mode** (where it
goes, with a flee trigger). Enables all movement modes including Patrol.

## Model (per zombie)

- **combat_stance**: `AGGRESSIVE` (default) | `HOLD`
- **movement_mode**: `FREE` (default) | `FLEE` | `PATROL`
- **flee_trigger** (used when FLEE): `ON_SIGHT` | `ON_DAMAGE` | `IDLE`
- points: `flee_point`, `patrol_a`, `patrol_b`
- latches: `_fled` (true once a flee has triggered — parks at the point for the
  rest of the match), `_patrol_leg`, `_damaged_timer` (counts down after a hit)

## Combat rules (apply in every movement mode)

- **Aggressive:** acquire nearest visible enemy (shooter/npcs within
  `vision_range × 64`), chase & bite at `contact_px`. Sound/damage aggro: a
  gunshot within `AGGRO.alert_radius_px` (which is what a hit implies, since
  bullets come from shots) pulls it toward that spot via `alert_to()`.
- **Hold:** never chases; bites only an enemy within `STANCE.hold_attack_px`
  (~64px = 1 tile). No target acquisition beyond that range.
- Bite range = `hold_attack_px` for Hold, else `contact_px` (`_attack_range()`).

## Movement rules

- **FREE:** Aggressive → chase the acquired enemy, or seek the aggro point if
  alerted, else idle. Hold → stay put (bite within 1 tile only).
- **PATROL (A↔B):** walk the loop. Aggressive → break off to chase a seen enemy,
  resume patrol when none. Hold → keep walking the route, 1-tile bites only.
- **FLEE (trigger, 1 point):** behaves as FREE until the trigger fires, then runs
  to `flee_point` and **parks there permanently** (`_fled = true`).
  - `ON_SIGHT`: an enemy is within vision.
  - `ON_DAMAGE`: `_damaged_timer > 0` (set on `take_damage`).
  - `IDLE`: no enemy within vision (→ garrison at the point).
  - While parked: Aggressive engages enemies that come within `STANCE.leash_px`
    of the point (defends the area, returns to the point otherwise); Hold only
    1-tile bites. Movement target is the flee point.

## UI — two-row toolbar (runtime-built in `ZombieController`)

Built in code (like the minimap/rally button) under `ZCOverlay`, replacing the
old `.tscn` StancePanel buttons:

- **Combat row:** `Aggressive` · `Hold` (0 clicks → `rpc_set_combat`).
- **Movement row:** `Free` (0 clicks) · `Flee: on sight` · `Flee: on hit` ·
  `Flee: idle` (each 1 click) · `Patrol` (2 clicks) → `rpc_set_movement`.
- Placement flow reuses the existing pending-points capture; Free/combat need 0.
- The two axes are set independently; combat doesn't reset movement or vice versa.
- Panel visible only when zombies are selected.

## Commands / RPCs (world.gd)

Replace `rpc_set_stance` with:
- `rpc_set_combat(names: Array, combat: int)` → `z.set_combat(combat)`
- `rpc_set_movement(names: Array, mode: int, trigger: int, p1: Vector2, p2: Vector2)`
  → `z.set_movement(mode, trigger, p1, p2)`

Both server-guarded, `call_local`, mirroring the old command.

## Preview / glyph (selectrion_drawer.gd + zombie.gd)

- Draw patrol A↔B line when `movement_mode == PATROL`; flee marker when
  `movement_mode == FLEE`. Guard non-zombies (master has no `movement_mode`).
- Glyph under selected zombies colored by `combat_stance` (Aggressive red / Hold
  grey), with a small movement tick (Free/Flee/Patrol).

## Balance additions (`Balance.STANCE`)

- `hold_attack_px = 64.0` (Hold's 1-tile bite range)
- `leash_px = 120.0` (Aggressive engage radius around a parked flee point)
- `damage_flee_window = 0.4` (seconds `_damaged_timer` stays up after a hit)
- keep `arrive_px`.

## Non-goals

- No new replication (combat/movement state is server-side, same caveat as before:
  preview/glyph accurate for host/single-player commander).
- No change to merge, minimap, health bars, or the rally command.

## Testing

- Extend `StanceLogic` if a pure helper falls out (e.g. flee-trigger evaluation
  kept pure); otherwise verify in-editor (clean boot) + owner playtest per axis.
