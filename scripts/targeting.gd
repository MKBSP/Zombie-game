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


## True when `pos` is within any watcher's vision radius.
## watcher = { "pos": Vector2, "vision_px": float }
static func visible_to_any(pos: Vector2, watchers: Array) -> bool:
	for w in watchers:
		if pos.distance_to(w["pos"]) <= w["vision_px"]:
			return true
	return false


## Build visibility watchers from zombie nodes (any node with vision_range;
## falls back to 2 tiles). 64 px per tile.
static func watchers_from(zombies: Array) -> Array:
	var out: Array = []
	for z in zombies:
		if z is Node2D and is_instance_valid(z):
			var vision: int = z.vision_range if "vision_range" in z else 2
			out.append({ "pos": z.global_position, "vision_px": float(vision) * 64.0 })
	return out
