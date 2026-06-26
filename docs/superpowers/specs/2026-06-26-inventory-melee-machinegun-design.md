# Shooting overhaul — Phase 4: inventory, machine gun & melee

Date: 2026-06-26
Status: approved, pre-implementation

The final phase of the shooting rework. Phases 1–3 built skill-based aiming,
headshots, and NPC shooting. Phase 4 bundles **three** related features into one
spec (by request): a three-slot weapon inventory, a full-auto **machine gun**, and a
brand-new **melee** weapon. They share the slot/category foundation, so they ship
together. Weapon *visuals* on the sprite/HUD are explicitly **Phase 5**, not here.

## Problem

The player carries a permanent pistol plus one "special" slot (rifle/shotgun). The
game's target loadout is **1 handgun + 1 heavy + 1 melee**. We need: typed carry
slots with direct selection; a sustained-fire heavy (machine gun); and a close-range
melee weapon with its own combat feel — a different damage path from bullets.

## Goals

- **Three typed slots**: pistol (permanent), heavy (swappable), melee (swappable),
  selected with number keys **1 / 2 / 3**.
- **Machine gun**: a full-auto heavy firearm under the existing aim/bullet model.
- **Melee**: a switch-to weapon with a narrow forward strike, a fixed cadence, and a
  fatigue rule that punishes spam — no bullets, no ammo, its own damage.
- All server-authoritative; tunable from `Balance`.

## Non-goals (out of scope / later)

- Weapon visuals on the character sprite or HUD icons — **Phase 5**.
- NPC melee (NPCs stay firearms-only) and swappable handguns (pistol is permanent).
- Melee knockback, combos, or charge attacks.

## Inventory / slots

Three slots on the shooter:

- **Pistol** (slot **1**) — permanent sidearm, never dropped or replaced.
- **Heavy** (slot **2**) — `RIFLE` / `SHOTGUN` / `MACHINEGUN`. Starts empty.
- **Melee** (slot **3**) — `MELEE`. Starts empty.

Behaviour:

- **Select** with `select_pistol` (1) / `select_heavy` (2) / `select_melee` (3).
  Selecting an empty slot is a no-op (you keep your current weapon).
- **Pickups**: heavy and melee weapons spawn as world pickups (extending the existing
  pickup system). Picking up a category you already hold **swaps** — the old one
  drops on the ground as a pickup (exactly how rifle/shotgun swap today).
- **Drop** drops the currently-equipped heavy or melee (the pistol can't be dropped).
- **Give-to-NPC** stays **firearms-only** and applies to the held heavy; melee is
  not givable.

This generalises today's `equipped` + `held_special` into pistol + held-heavy +
held-melee. Ammo for firearms is unchanged (pistol reserve; heavy mag/total). Melee
has no ammo.

## Machine gun (heavy, full-auto)

A new `Weapons.MACHINEGUN`, `is_special = true`. It fires like the other guns
(holding fire keeps firing; cooldown sets the rate) and takes the full aim model,
range falloff, and headshots. Starting stats (all in `Balance.MACHINEGUN`, tunable):

| field | value | note |
|---|---|---|
| damage | 22 | per bullet; spray-DPS, well below the rifle's sniper hit |
| cooldown | 0.08 | ≈12.5 rounds/sec, full-auto |
| mag_size | 40 | |
| reload_time | 4.0 | |
| pellets | 1 | |
| bullet_speed | 1300 | (post-Phase-5-bullet-tweak era) |
| total_ammo | 120 | |
| aim_base / aim_max | 0.14 / 0.40 | looser than the rifle — rewards firing into a cluster |
| focus_min_scale | 0.8 | focus helps a little |
| optimal_range_px / zero_range_px | 512 / 700 | 8 → ~11 tiles |

## Melee (switch-to weapon)

Equipped via slot 3; while it's out, **left-click swings** instead of shooting, and
the aim circle hides (melee has no spread). A new `Weapons.MELEE` with a new
`is_melee = true` flag on `WeaponData`; it carries no ammo and reads its combat
numbers from `Balance.MELEE`.

**The strike (server-side):** on a swing (if off cooldown), test every zombie against
a **narrow forward zone** aimed at the cursor — within `range_px` ahead and within
`half_width_px` laterally of the facing line (and in front, not behind). Each zombie
in the zone takes melee damage. Usually that's the one zombie directly ahead, but
stacked zombies in that strip are both hit. Melee does **not** use bullets or the
center-mass crit — it calls the target's damage directly.

**Numbers (`Balance.MELEE`, tunable):**

| field | value | meaning |
|---|---|---|
| damage | 10 | per hit (halved while fatigued) |
| cooldown | 0.6 | seconds between swings (max ~1.67/s) |
| range_px | 50 | reach just past the player's body |
| half_width_px | 19 | ≈80% of the 48px player hitbox width → narrow, straight-ahead |
| fatigue_hits | 3 | landed hits within the window that trigger fatigue |
| fatigue_window | 3.0 | seconds — 3 landed hits inside this triggers fatigue |
| fatigue_mult | 0.5 | damage multiplier while fatigued (10 → 5) |
| fatigue_recover | 10.0 | seconds without a landed hit to clear fatigue |

**Fatigue rule:** landing **3 hits within any 3-second window** sets a **fatigued**
state that halves melee damage. Fatigue persists until the player goes a **full 10
seconds without landing a melee hit** (any landed hit resets that recovery timer), so
sustained melee spam stays gimped until you lay off. "Hit" = a swing that connects
with at least one zombie (whiffs don't count).

**Feedback:** a brief swing flash (a short line/arc in the facing direction for a
fraction of a second) so the swing reads. Player-only this phase.

## Components

- `scripts/balance.gd` — `MELEE` and `MACHINEGUN` blocks.
- `scripts/weapon_data.gd` — add `is_melee: bool`.
- `scripts/weapons.gd` — add `MACHINEGUN` and `MELEE` to the enum + `get_data` (both
  sourced from `Balance`).
- `scripts/melee.gd` (new, `class_name Melee`) — pure, testable: the forward-strike
  hit test, and the fatigue trigger/recovery evaluation. Stateless; the shooter holds
  the live swing-cooldown and fatigue state.
- `scenes/shooter/shooter.gd` — three-slot inventory (pistol / held-heavy /
  held-melee), 1/2/3 selection, melee swing + fatigue, drop (heavy/melee),
  give-to-NPC (heavy only).
- `scenes/shooter/shooter.tscn` — sync the slot/melee state needed for the HUD.
- `scenes/ui/hud.gd` — show the equipped weapon for melee too (name + "melee", no
  ammo); minimal.
- `scenes/ui/aim_cursor.gd` — hide while melee is equipped.
- `scenes/pickup/pickup.gd` + the `Pickup.Kind` enum + world spawning — machine-gun
  and melee pickups.
- `project.godot` — input actions `select_pistol` (1), `select_heavy` (2),
  `select_melee` (3).

## Data flow

```
client (human): number keys -> select RPC; left-click -> fire/swing RPC (existing)
server (gun equipped): existing Weapons.fire path (MG = full-auto via cooldown)
server (melee equipped, swing off cooldown):
    for each zombie in Melee.forward_strike(pos, facing, range, half_width):
        zombie.take_damage(melee_damage * (fatigue_mult if fatigued else 1))
    record landed hit -> update fatigue (3-in-3s trigger, 10s-idle recovery)
    broadcast a brief swing-flash effect
client: HUD shows the equipped weapon; aim circle hidden for melee
```

## Multiplayer

All resolution (firing, melee swing + hits, slot changes, fatigue) runs on the
server, like today. The equipped weapon / held-heavy / held-melee / reload state sync
to the controlling client for the HUD (the same `SceneReplicationConfig` pattern the
ammo state already uses). The swing flash is a transient effect broadcast to peers
(the pattern used by the headshot toast / merge progress). No new per-frame synced
entity state beyond a couple of small slot/state fields.

## Testing

- **Unit (headless):** `Melee.forward_strike` (a target dead-ahead within range →
  hit; just outside the lateral half-width → miss; behind the player → miss; beyond
  range → miss) and the fatigue evaluation (3 hits in 3s → fatigued; a 10s idle gap →
  recovered). Existing `test_aim_model.gd` / `test_npc_aim.gd` still pass.
- **Manual feel pass:** 1/2/3 selects the right slot (empty = no-op); MG sprays
  full-auto and chews ammo; a melee swing hits the zombie directly in front for 10;
  three fast melee hits drop the damage to 5; ~10s without meleeing restores it;
  picking up a 2nd heavy/melee swaps and drops the old; drop works; give-heavy-to-NPC
  works; aim circle hides on melee.
- **Multiplayer:** 2-window host/join — slot changes, MG fire, and melee hits/flash
  replicate; the HUD reflects the equipped weapon on the human client.

## Known limitations / deferred

- No weapon visuals yet (Phase 5).
- Melee is player-only; NPCs remain firearms-only.
- Pistol is the only handgun (handgun slot not swappable).
- Melee has no knockback/combos; one global fatigue rule, not per-swing stamina.
