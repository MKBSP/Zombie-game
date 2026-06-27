extends RefCounted
class_name Interact

## Pure nearest-interactable resolution. Each candidate carries its own reach,
## so a tight-radius type (e.g. NPC give) only wins when you're nearly on top
## of it. Returns the index of the nearest candidate within its own radius,
## or -1 if nothing is reachable.
static func choose_nearest(origin: Vector2, candidates: Array) -> int:
	var best := -1
	var best_d := INF
	for i in range(candidates.size()):
		var c: Dictionary = candidates[i]
		var d := origin.distance_to(c["pos"])
		if d <= float(c["radius"]) and d < best_d:
			best_d = d
			best = i
	return best
