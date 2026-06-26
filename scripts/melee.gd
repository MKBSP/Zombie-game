extends RefCounted
class_name Melee

## Pure math for the player's melee weapon — the narrow forward-strike test and the
## recent-hit count behind the fatigue rule. Stateless; the shooter holds the live
## swing-cooldown and fatigue state.

## True when `target` is within the narrow forward strike: ahead of `origin` along
## `facing`, within `range_px` forward and `half_width` laterally.
static func forward_strike(origin: Vector2, facing: Vector2, range_px: float, half_width: float, target: Vector2) -> bool:
	var f := facing.normalized()
	if f == Vector2.ZERO:
		return false
	var rel := target - origin
	var forward := rel.dot(f)
	if forward <= 0.0 or forward > range_px:
		return false
	return absf(rel.cross(f)) <= half_width

## How many of `hit_times` fall within `window` seconds before `now`.
static func recent_hit_count(hit_times: Array, now: float, window: float) -> int:
	var n := 0
	for t in hit_times:
		if now - t <= window:
			n += 1
	return n
