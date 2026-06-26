extends RefCounted
class_name NpcAim

## Pure aim math for armed NPCs — kept separate from the player's (shooter.gd) and
## from the shared weapon spread (AimModel), so NPC accuracy can be tuned and
## upgraded on its own. Stateless; the NPC instance holds the live recoil state.

## Additive aim debuff: panic + moving + injured/hurt (worse tier wins) + recoil.
## Unclamped — AimModel.spread_coeff clamps the total to 1.0.
static func aim_debuff(b: Dictionary, moving: bool, hp: int, max_hp: int, recoil: float) -> float:
	var total: float = b.panic
	if moving:
		total += b.debuff_running
	if hp < int(max_hp * b.injured_hp_frac):
		total += b.debuff_hurt
	elif hp < max_hp:
		total += b.debuff_injured
	total += recoil
	return total


## Current recoil given the per-shot kick `initial` and how far it has decayed
## (`elapsed` seconds into a `recover`-second window). 0 when the window is closed.
static func recoil_after(initial: float, elapsed: float, recover: float) -> float:
	if recover <= 0.0:
		return 0.0
	return initial * clampf(1.0 - elapsed / recover, 0.0, 1.0)
