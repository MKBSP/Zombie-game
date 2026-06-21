# Shooting overhaul — Phase 1: player aiming core

Date: 2026-06-21
Status: approved, pre-implementation

This is Phase 1 of a larger shooting rework. Later phases (separate specs):
Phase 2 head/body hitboxes (headshots), Phase 3 NPC shooting under this model,
Phase 4 inventory carry-limits + melee + machine gun.

## Problem

The player currently has **perfect aim** — `shooter.shoot()` calls
`Weapons.fire(..., jitter = 0.0)` and there is no cursor, no spread, no range
falloff. We want skill-based shooting: a visible aim circle whose size reflects
accuracy, weapon-specific spread, debuffs (running / injured / recoil), a
focus buff, and damage that falls off past each weapon's effective range.

## Goals

- A visible, custom **aim cursor** (circle) for the human player; its radius =
  current spread, drawn as a cone that grows with cursor distance.
- Per-weapon spread with additive debuffs and a held-button focus buff.
- Range → damage falloff, mirrored by the cursor's **opacity**.
- All authoritative on the server; the cursor is a local readout.

Non-goals (later phases): headshots, NPC rework, inventory/melee/MG, skill tree.

## Spread model (the core)

Spread is a **cone**: a circle drawn at the cursor whose radius scales with the
distance from the gun to the cursor. Each weapon defines `aim_base` and
`aim_max` as a *fraction of that distance*.

```
debuff_total = running + injured + recoil          # additive
d            = clamp(debuff_total, 0.0, 1.0)
coeff        = aim_base + d * (aim_max - aim_base)
coeff       *= lerp(1.0, focus_min_scale, focus_fraction)
circle_radius_px = coeff * distance(gun_tip, cursor)
```

**Firing** (server, per pellet): pick a uniform random point in the disk of
radius `circle_radius_px` centred on the cursor world-position, fire a straight
bullet from `gun_tip` toward it. The bullet never changes direction and stops on
the first thing it hits (already true). Shotgun fires its 5 pellets as 5
independent random points in its (wide) circle — this **replaces** the old fixed
`spread_rad` fan.

Uniform disk sample: `r = R*sqrt(randf()); a = randf()*TAU; offset = Vector2(cos(a),sin(a))*r`.

## Debuffs (additive fractions, server-side)

| Source   | Value | Condition |
|----------|-------|-----------|
| Running  | +0.20 | movement input non-zero (`_net_dir.length() > 0.1`) |
| Injured  | +0.20 | `hp < max_hp` |
| Injured  | +0.40 | `hp < max_hp * 0.5` (replaces the +0.20 tier — worse wins) |
| Recoil   | +0.50 → 0 | set to 0.50 on each shot, decays linearly to 0 over `2 × dmg_units` s |

`dmg_units = (weapon.damage * weapon.pellets) / pistol.damage` → pistol 1 (2s),
rifle 2.5 (5s), shotgun 4 (8s). Rapid fire **refreshes** recoil to 0.50 (set,
not stacked). Recoil is part of `coeff`, so the cursor visibly grows on each
shot and shrinks as it recovers.

## Focus buff (hold Ctrl + standing still)

While the new `focus_aim` action is held **and** the player isn't moving,
`focus_timer` climbs to 5s; moving or releasing Ctrl resets it to 0.

```
focus_fraction = clamp(focus_timer / 5.0, 0.0, 1.0)
```

Per-weapon floor `focus_min_scale`: **pistol 0.75**, **rifle 0.50**,
**shotgun 1.0 (no focus)**. At full focus with no other debuff the circle is
`aim_base * focus_min_scale`. The cursor tints green while `focus_fraction > 0`.

## Range → damage + cursor opacity

Each weapon has `optimal_range_px` and `zero_range_px`. Beyond optimal, damage
falls **−40% per tile** (tile = 64px), reaching 0 at `optimal + 2.5 tiles`:

```
if dist <= optimal: mult = 1.0
else: mult = clamp(1.0 - (dist - optimal) / (zero - optimal), 0.0, 1.0)
```

- **Damage** is scaled by `mult` at bullet impact (server), using the distance
  the bullet travelled from its origin. A bullet past `zero_range_px` despawns.
- **Cursor opacity** uses the same `mult` at the cursor distance, so the player
  sees the circle fade as they aim past effective range.

> Tunable discrepancy: the original note said "0 damage at 5 tiles" but −40%/tile
> reaches 0 at ~2.5 tiles past optimal. We implement −40%/tile; revisit if the
> gentler curve feels better.

## Per-weapon defaults (all tunable)

| Weapon  | dmg | pellets | aim_base | aim_max | focus_min | optimal | zero |
|---------|-----|---------|----------|---------|-----------|---------|------|
| Pistol  | 35  | 1 | 0.10 | 0.30 | 0.75 | 10 tiles (640) | 12.5 tiles (800) |
| Rifle   | 87.5| 1 | 0.03 | 0.25 | 0.50 | 16 tiles (1024)| 18.5 tiles (1184) |
| Shotgun | 28  | 5 | 0.22 | 0.45 | 1.00 | 5 tiles (320)  | 7.5 tiles (480) |

(`aim_*` are radius/distance fractions; rifle > pistol > shotgun on range.)

## Components

- **`scripts/aim_model.gd`** (`class_name AimModel`, static, pure) — single
  source of truth: `spread_coeff(w, debuff_total, focus_fraction)`,
  `damage_mult(w, dist_px)`, `random_in_disk(r)`. Used by the server (firing +
  damage) and the client (cursor).
- **`scenes/ui/aim_cursor.gd` + `.tscn`** — Control under `HUDLayer`; draws the
  circle at the mouse, radius `= synced coeff × mouse distance`, opacity from the
  range curve, green tint while focusing. Hides the OS cursor while active,
  restores it on exit. Human role only.
- **`weapon_data.gd`** — add `aim_base, aim_max, focus_min_scale,
  optimal_range_px, zero_range_px`.
- **`weapons.gd`** — `fire()` reworked to the disk-random model:
  `fire(parent, origin, cursor_pos, radius_px, w)`, passing `origin`,
  `optimal_range_px`, `zero_range_px` to each bullet. The NPC call is adapted to
  synthesise a cursor (target pos) + radius from its existing jitter so it keeps
  working; full NPC integration is Phase 3.
- **`shooter.gd`** — server-side recoil + focus timers; computes
  `aim_spread_coeff` each physics frame via `AimModel` and **syncs** it; input
  RPC now sends the cursor world-position and the Ctrl-held flag; `shoot()` uses
  the disk model.
- **`bullet.gd`** — store `origin`, `optimal_range_px`, `zero_range_px`; scale
  damage by `AimModel.damage_mult` on hit; despawn past `zero_range_px`.
- **`shooter.tscn`** — add `aim_spread_coeff` to the `SceneReplicationConfig`.
- **`project.godot`** — add input action `focus_aim` (Ctrl, left+right).

## Data flow

```
client (human): mouse pos + Ctrl + WASD
   -> _send_input.rpc_id(1, dir, cursor_world_pos, shooting, focus_held)
server: derive angle/distance; update running/injured/recoil/focus;
        coeff = AimModel.spread_coeff(...); set aim_spread_coeff (synced)
        on fire: Weapons.fire(entities, gun_tip, cursor_world_pos,
                              coeff*distance, weapon)
        on bullet hit: damage * AimModel.damage_mult(weapon, dist_travelled)
client (human): aim_cursor draws circle from synced aim_spread_coeff + local
        mouse distance; opacity from equipped weapon's range curve
```

## Multiplayer

- `aim_spread_coeff` is one synced float; the cursor is a client-only visual.
- Firing randomisation and damage falloff run only on the server (bullets
  replicate via the existing `MultiplayerSpawner`).
- Cursor + hidden-OS-cursor apply only to the controlling **human** client;
  skipped for the zombie role and the dedicated server. Camera zoom is 1.0, so
  world-px radii draw correctly in screen space.

## Testing

- **Single-player feel:** still vs running (circle grows ~+20%); spray vs spaced
  (recoil grows then shrinks); hold Ctrl while still (pistol → 75%, rifle → 50%,
  shotgun unchanged, green tint); aim past optimal (circle fades, zombies take
  reduced/zero damage).
- **Multiplayer:** 2-window host/join; the human's shots land within the synced
  circle on both peers; damage drops with range identically.
- **Regression:** shotgun still spreads; reload/ammo/swap/drop unaffected;
  zombie role and dedicated server never spawn a cursor.

## Known limitations / deferred

- NPCs keep their current sloppy-aim approximation until Phase 3.
- Cursor assumes camera zoom 1.0.
- "Same zombie" focus tracking from the early sketch is simplified to
  "stand still + hold Ctrl"; can be tightened later.
