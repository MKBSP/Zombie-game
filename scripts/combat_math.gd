extends RefCounted
class_name CombatMath

## Pure attack-gating math, shared by zombie.gd and master_zombie.gd.

static func can_attack(distance: float, contact_px: float, cooldown_remaining: float) -> bool:
	return distance <= contact_px and cooldown_remaining <= 0.0
