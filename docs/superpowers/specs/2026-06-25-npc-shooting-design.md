# Shooting overhaul — Phase 3: NPC shooting under the aim model

Date: 2026-06-25
Status: approved, pre-implementation

This is Phase 3 of the shooting rework. Phase 1 gave the player skill-based aiming
(`2026-06-21-shooting-aim-core-design.md`); Phase 2 added center-mass headshots
(`2026-06-23-shooting-headshots-design.md`). Phase 3 brings armed NPCs under the
same spread model with their own, independently-tunable accuracy, plus a new
engagement behaviour and a fire-rate cap. Phase 4 (separate spec): inventory
carry-limits + melee + machine gun.

## Problem

Armed NPCs already fire — the player hands an NPC a weapon and it shoots the
nearest zombie within ~6 tiles, but only while the player holds fire. Their
accuracy is a placeholder: a flat `NPC_AIM_JITTER = 0.25` spread (25% of the
gun→target distance), identical regardless of weapon, movement, injury, or recoil.
We want NPCs to shoot under the real `AimModel` — weapon-dependent, condition-aware
— but **clearly worse than the player** (panicky civilians), and we want a more
useful engagement rule than "only while the player is firing."

## Goals

- NPC spread comes from `AimModel.spread_coeff` using the NPC's equipped weapon,
  plus a panic floor and the same condition set the player has (moving / injured /
  recoil), **no focus**.
- NPC accuracy is **fully separate** from the player's — its own code path and its
  own `Balance.NPC` knobs — so it can be tuned and upgraded independently. The
  player's `shooter.gd` aim code is **not touched**.
- A new **engagement** rule: the player's shot sparks the NPC, which then fights
  autonomously until no zombie is in its sight.
- A **fire-rate cap**: no faster than 1.5 shots/second.

## Non-goals

- No change to the player's aiming code or values.
- No targeting smarts (still nearest visible zombie), no target leading.
- No change to friendly fire — NPC bullets **still** damage other NPCs (kept on).
- No NPC "HEADSHOT!" toast (player-only, unchanged). NPC bullets still crit zombies
  and still take range falloff — both already true from Phase 1/2.
- No shared-helper extraction between player and NPC; the only shared piece is the
  per-weapon `AimModel.spread_coeff` formula (a weapon trait, not player behaviour).

## Accuracy model

The NPC computes its own debuff total and feeds it to the shared weapon-spread
formula with focus fixed at 0:

```
npc_debuff_total = panic + moving + injured + recoil      # additive, NPC-owned
coeff            = AimModel.spread_coeff(weapon, npc_debuff_total, 0.0)
radius_px        = coeff * distance(muzzle, target)
```

Condition terms (all from `Balance.NPC`, NPC-local state — never reads the
player's values):

| Term    | Value (default) | Condition |
|---------|-----------------|-----------|
| Panic   | `panic` = 0.35  | always (a calm, still NPC still sits ~35% toward the weapon's `aim_max`) |
| Moving  | `debuff_running` = 0.20 | NPC velocity above a small threshold |
| Injured | `debuff_injured` = 0.20 | `hp < max_hp` |
| Injured | `debuff_hurt` = 0.40 | `hp < max_hp * injured_hp_frac` (replaces the +0.20 tier — worse wins) |
| Recoil  | `recoil_initial` = 0.50 → 0 | set on each shot, decays to 0 over `recoil_recover_factor × dmg_units` s |

`dmg_units = (weapon.damage × weapon.pellets) / Balance.NPC.dmg_ref` (NPC-owned
`dmg_ref` = 35.0). This mirrors the player's recoil shape but uses NPC constants,
so the player and NPC can diverge later. `spread_coeff` clamps the total to 1.0,
so the worst case is the weapon's `aim_max`. "Moderate" feel: a still, healthy
pistol NPC lands close zombies but sprays at range; moving or post-shot, it widens
toward `aim_max`.

Firing reuses the existing path: bullets spawn from a muzzle offset toward the
target's current position (no leading), via `Weapons.fire(get_parent(), origin,
target.global_position, radius_px, w)` with **no `source`** — so `from_player`
stays false (no toast, friendly fire on, crits still apply).

## Engagement behaviour

Each armed NPC holds a server-side `_engaged` flag (idle by default):

- **Idle → Engaged** when *both*: a zombie is within the NPC's vision (`vision_px`)
  **and** the player is firing (`shooter.is_firing()`). The player's shot is the
  spark.
- **While Engaged:** every tick, pick the nearest visible zombie and fire at it
  (gated by the fire-rate cap, ammo, and reload) — **independent of whether the
  player is still firing**.
- **Engaged → Idle** when no zombie is within the NPC's vision (the player ran the
  fight out of sight, or the zombies died).
- **Re-engaging** requires the spark again: the player firing while a zombie is
  visible. (An NPC that goes idle stays quiet until the player shoots near zombies
  again.)

This replaces the current "fire only while `shooter.is_firing()`" check.

## Fire-rate cap

No faster than 1.5 shots/second. Per-shot cooldown becomes
`max(weapon.cooldown, Balance.NPC.min_shot_interval)` with `min_shot_interval =
0.667` (= 1 / 1.5). Reloads still use `weapon.reload_time`. (Mainly caps the
pistol's 0.28s cadence; rifle/shotgun are reload-gated already.)

## Balance.NPC changes

Remove `aim_jitter`. Add (NPC-owned, initially mirroring the player's numbers but
independent):

```gdscript
const NPC := {
	# ... existing speed/hp/hide/follow/vision_px/muzzle_offset ...
	panic = 0.35,
	debuff_running = 0.20,
	debuff_injured = 0.20,
	debuff_hurt = 0.40,
	injured_hp_frac = 0.5,
	recoil_initial = 0.50,
	recoil_recover_factor = 2.0,
	dmg_ref = 35.0,
	min_shot_interval = 0.667,   # 1.5 shots/sec cap
}
```

## Components

- **`scenes/npc/npc_human.gd`** — the only behaviour file changed:
  - New server-side state: `_engaged: bool`, recoil (`_recoil`, `_recoil_elapsed`,
    `_recoil_recover`).
  - `_npc_debuff_total() -> float` (panic + moving + injured + recoil, NPC values).
  - `_npc_update_recoil(delta)` (decays `_recoil`, same shape as the player's).
  - Engagement: update `_engaged` from vision + `shooter.is_firing()`; fire while
    engaged regardless of the player.
  - `_process_shooting()` replaces the `NPC_AIM_JITTER` radius with
    `AimModel.spread_coeff(w, _npc_debuff_total(), 0.0) * dist`, applies the
    recoil kick per shot, and uses the `min_shot_interval` cap.
- **`scripts/balance.gd`** — `Balance.NPC` edits above.
- **`scripts/aim_model.gd`** — unchanged (NPC reuses `spread_coeff`).
- **`scenes/shooter/shooter.gd`** — unchanged.

## Multiplayer

NPC AI is server-only already; `_engaged` and recoil are server-side state. Spread
is computed at fire-time on the server. No new synced state — bullets replicate via
the existing `MultiplayerSpawner`, identical to today.

## Testing

- **Regression (headless):** the existing `test/test_aim_model.gd` still passes
  (`spread_coeff` unchanged) and the project compiles clean.
- **Manual feel pass (play the game):** arm an NPC, then watch its accuracy respond
  to the model —
  - tighter shots when the NPC is standing still and healthy; wider while it's
    moving or just after it fires (recoil);
  - a rifle NPC tighter than a shotgun NPC;
  - it starts firing only after you shoot near a visible zombie, keeps firing on its
    own once engaged, and goes quiet when the zombies leave its sight (re-sparks when
    you fire again);
  - it never fires faster than ~1.5 shots/sec.
- **Multiplayer:** 2-window host/join — NPC bullets and damage replicate identically;
  the NPC fires on the server and both peers see it.

## Known limitations / deferred

- NPCs aim at the target's current position (no leading) — fast zombies can be
  outrun by their own shots at range; acceptable, revisit if needed.
- The engagement spark uses `shooter.is_firing()`; in multiplayer this is the human
  shooter's state (the only shooter), which is correct for the current 1-shooter
  game. Multi-shooter (roadmap Phase 7) would generalise "any nearby player fired."
- Panic/recoil constants are duplicated in shape from the player's but intentionally
  separate, per the goal of independent NPC tuning/upgrades.
