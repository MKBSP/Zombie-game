extends RefCounted
class_name ShooterSelect

## Pure nearest-alive selection. candidate = { "pos": Vector2, "alive": bool }.
static func nearest_alive_index(from: Vector2, candidates: Array) -> int:
	var best_i := -1
	var best_d := INF
	for i in range(candidates.size()):
		var c: Dictionary = candidates[i]
		if not c.get("alive", false):
			continue
		var d: float = from.distance_to(c["pos"])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i
