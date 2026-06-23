# Shooting overhaul — Phase 2: center-mass headshots

Date: 2026-06-23
Status: approved, pre-implementation

This is Phase 2 of the shooting rework. Phase 1 (`2026-06-21-shooting-aim-core-design.md`)
delivered skill-based aiming: a cone aim circle whose size reflects accuracy, with
per-weapon spread, debuffs, a focus buff, and range→damage falloff. Phase 2 adds a
reward for precision: a critical hit when a shot lands in the enemy's core. Later
phases (separate specs): Phase 3 NPC shooting under this model, Phase 4 inventory
carry-limits + melee + machine gun.

## Problem

Phase 1 makes aiming a skill, but every hit on a zombie deals the same damage no
matter where it lands. There is no payoff for a pinpoint shot. We want a **critical
hit** for landing a bullet in the enemy's center of mass — a "headshot" — so that a
tight aim circle (the thing Phase 1 lets you earn) directly translates into burst
damage.

## Goals

- A bullet whose path passes through a small **center crit zone** of a zombie deals
  a critical hit: **4× the (range-adjusted) damage**.
- Tunable from `balance.gd` (crit radius + multiplier), like all other tuning.
- A clear, lightweight **"HEADSHOT!" HUD message** so the player knows they critted.
- Server-authoritative; works in multiplayer with no new synced entity state.

## Non-goals (later phases / out of scope)

- Crit zones on NPCs or the shooter — **zombies only** this phase.
- Per-weapon crit multipliers — one global 4× for now (one `Balance` value).
- Crit sound, floating damage numbers, or directional weak-points (rear/front).
- NPC combat nuance beyond "NPC bullets can also crit" (full NPC rework is Phase 3).

## Mechanic

A **critical hit** occurs when a bullet's straight travel line passes within a small
fixed radius of a zombie's center of mass. On a crit, the bullet deals `4×` the
damage it would otherwise deal.

- **Crit zone:** a fixed `5px` radius at the zombie's center, the **same on every
  zombie** regardless of size (standard / fast / fat / master). Cleanly coring a big
  fat zombie is exactly as demanding as a small one.
- **Target scope:** crit zones exist on **zombies only**. NPCs and the shooter take
  normal damage (no crit zone).
- **Bullet scope:** **any** bullet can crit — including armed-NPC allies' bullets.
  No bullet-ownership is needed for the damage rule.
- **Range still applies:** the crit multiplies the *already range-adjusted* damage
  (Phase 1 falloff). So `crit = base × range_mult × 4`. A pistol headshot is `140`
  within optimal range (10 tiles), tapering toward `0` as the shot approaches max
  range; a body shot at the same spot is `35 × range_mult`.

Resulting numbers (base × 4, at/within optimal range; all tunable in `Balance`):

| Weapon  | base dmg | headshot | vs std zombie (150 hp) |
|---------|----------|----------|------------------------|
| Pistol  | 35       | 140      | big chunk, not a one-shot |
| Rifle   | 87.5     | 350      | one-shots std/fast; not fat(750)/master(450) |
| Shotgun | 28/pellet| 112/pellet | each centered pellet crits independently |

## Detection — ray-distance (no new colliders)

Bullets already hit the whole body via `body_entered` and stop on the first
overlap; there is no sub-collider and we add none. Instead, at impact we test
whether the bullet's **straight path** passed through the core:

```
perpendicular distance from target_center to the bullet ray (origin, direction)
  ≤ crit radius  →  headshot
```

Each bullet already stores `origin` (muzzle) and `direction` (unit). The
perpendicular distance from the zombie's center `C` to that ray is the magnitude of
the 2D cross product `(C - origin) × direction`. This asks the right question —
"would this shot have gone through the 5px core?" — and has a deliberate, desirable
property: a dead-center shot still counts as a crit even though the bullet
physically stops at the zombie's near edge.

This is pure, stateless math, so it lives in `AimModel` (the shooting math
single-source-of-truth) and gets a headless unit test like the Phase-1 spread math.

## Feedback — reuse the pickup toast

Damage is computed on the server and zombies have no health bar, so without a cue
the player cannot tell a crit from a normal hit. We reuse the **existing HUD toast**
(the `ToastLabel` + the shooter's synced pickup-counter pattern that already pops a
message on weapon/ammo/medpack pickup):

- When a **player-fired** bullet crits, the server bumps a synced counter on the
  shooter (mirroring `pickup_seq` / `pickup_collected`); the controlling client's HUD
  shows **"HEADSHOT!"** on the `ToastLabel`.
- Only the human's HUD is visible (the zombie role hides it), so only the shooter
  player sees the message; it replicates for free in multiplayer.
- **Player crits only:** an NPC ally's crit still deals 4× but does not toast. The
  bullet carries a lightweight `from_player` flag (set when the shooter fires, unset
  for NPC fire) used **only** to gate the toast — it does not affect the damage rule.

## Balance values (new block)

`scripts/balance.gd`:

```gdscript
# --- Headshots (Phase 2) ---
const HEADSHOT := {
	radius_px = 5.0,   # center crit zone radius, same on every zombie
	mult = 4.0,        # crit damage multiplier (× range-adjusted damage)
}
```

## Components

- **`scripts/aim_model.gd`** — add `static func is_headshot(origin: Vector2,
  dir: Vector2, target: Vector2, radius: float) -> bool` (perpendicular ray
  distance ≤ radius). Pure; unit-tested.
- **`scenes/bullet/bullet.gd`** — in the zombie branch of `_on_body_entered`
  (server-only already), after the existing range-adjusted `_damage_for_hit()`,
  multiply by `Balance.HEADSHOT.mult` when `AimModel.is_headshot(origin, direction,
  body.global_position, Balance.HEADSHOT.radius_px)`. Add a `from_player: bool` set
  by the firing path; on a player crit, notify the shooter for the toast. NPC branch
  unchanged (zombies only).
- **`scripts/weapons.gd`** — `fire()` gains an optional `source` (the shooter node
  or null) so player-fired bullets can set `from_player` + a shooter reference;
  NPC calls pass null.
- **`scenes/shooter/shooter.gd`** — a `register_headshot()` that bumps a synced
  counter (parallels `_notify_pickup`); its setter emits a `headshot` signal.
- **`scenes/ui/hud.gd`** — connect the shooter's `headshot` signal → show
  "HEADSHOT!" via the existing toast.
- **`test/test_aim_model.gd`** — extend with `is_headshot` cases.

## Data flow

```
server (bullet hit on a zombie):
  dmg = base × AimModel.damage_mult(weapon, dist_travelled)        # Phase 1 falloff
  if AimModel.is_headshot(origin, direction, zombie.center, R):    # Phase 2
      dmg *= Balance.HEADSHOT.mult
  zombie.take_damage(dmg)
  if crit and bullet.from_player:
      shooter.register_headshot()        # synced counter -> controlling client
client (human): HUD ToastLabel shows "HEADSHOT!"
```

## Multiplayer

- Detection and damage run only on the server; bullets/zombie HP already replicate.
- No new synced state on bullets or zombies. The only synced addition is the
  shooter's headshot counter (one int, same shape as the pickup counter).
- Zombie-role client and the dedicated server never show the toast (no visible HUD).

## Testing

- **Unit (headless):** `is_headshot` — dead-center ray → true; a ray offset just
  inside the radius → true; just outside → false; a parallel near-miss → false.
  Run with the existing `test/test_aim_model.gd` harness; expect `ALL TESTS PASSED`.
- **Single-player feel (MCP):** fire at a zombie's center vs its edge and confirm
  center hits kill markedly faster (4×); confirm a crit at long range is reduced by
  falloff (range still matters); confirm the "HEADSHOT!" toast appears on a center
  hit only.
- **Multiplayer:** 2-window host/join — both peers see identical damage; the human
  sees the toast, the zombie player does not.
- **Regression:** normal (non-center) shots, range falloff, shotgun multi-pellet,
  reload/ammo/swap, and NPC fire all behave as before; NPC ally crits deal 4× but
  produce no toast.

## Known limitations / deferred

- One global crit multiplier; per-weapon crit values are a later tuning pass.
- `is_headshot` tests the infinite ray (not a forward segment); acceptable because
  it is only evaluated at the moment the bullet overlaps the target.
- No crit on NPCs/shooter, no sound, no floating numbers — future polish.
