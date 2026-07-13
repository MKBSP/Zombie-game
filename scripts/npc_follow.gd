extends RefCounted
class_name NpcFollow

## Pure math for NPC trail-following and combat formation (see npc_human.gd).
## Kept engine-free so it stays headless-testable, like StanceLogic/NpcAim.


## The point `back_dist` px behind the trail's newest end, walking
## newest -> oldest along arc length. trail[0] is the oldest breadcrumb.
## Returns Vector2.INF for an empty trail; clamps to the oldest point.
static func trail_point(trail: PackedVector2Array, back_dist: float) -> Vector2:
	var n := trail.size()
	if n == 0:
		return Vector2.INF
	var remaining := back_dist
	for i in range(n - 1, 0, -1):
		var seg := trail[i].distance_to(trail[i - 1])
		if seg >= remaining and seg > 0.0:
			return trail[i] + (trail[i - 1] - trail[i]) * (remaining / seg)
		remaining -= seg
	return trail[0]


## Formation slot for follower `slot_index` (0-based, armed NPCs first in the
## order). `threat_dir` is the normalized shooter->threat direction. Armed
## NPCs claim the side slots (2 armed: one per flank; 1 armed: behind, offset
## to one side); unarmed stack in a single-file column straight behind —
## never between the shooter and the threat.
static func formation_slot(shooter_pos: Vector2, threat_dir: Vector2,
		slot_index: int, armed_count: int, back_px: float, side_px: float) -> Vector2:
	var back := -threat_dir
	var side := Vector2(-threat_dir.y, threat_dir.x)
	if armed_count >= 2 and slot_index < 2:
		var s := 1.0 if slot_index == 0 else -1.0
		return shooter_pos + side * s * side_px + back * back_px * 0.5
	if armed_count == 1 and slot_index == 0:
		return shooter_pos + back * back_px + side * side_px
	var unarmed_rank := slot_index - mini(armed_count, 2)
	return shooter_pos + back * (back_px * float(unarmed_rank + 2))
