extends RefCounted
class_name Targeting

## Returns the index of the nearest eligible candidate within vision_px, or -1.
## candidate = { "pos": Vector2, "eligible": bool }
static func nearest_index(from: Vector2, candidates: Array, vision_px: float) -> int:
	var best_i := -1
	var best_d := vision_px
	for i in range(candidates.size()):
		var c: Dictionary = candidates[i]
		if not c.get("eligible", false):
			continue
		var d: float = from.distance_to(c["pos"])
		if d <= best_d:
			best_d = d
			best_i = i
	return best_i
