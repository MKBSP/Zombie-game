extends RefCounted
class_name MinimapMath

static func world_to_minimap(world: Vector2, world_px: float, minimap_size: float) -> Vector2:
	return (world / world_px) * minimap_size

static func minimap_to_world(local: Vector2, world_px: float, minimap_size: float) -> Vector2:
	return (local / minimap_size) * world_px

static func fuzz(pos: Vector2, jitter_px: float, rng: RandomNumberGenerator) -> Vector2:
	var ang := rng.randf() * TAU
	var dist := sqrt(rng.randf()) * jitter_px
	return pos + Vector2.from_angle(ang) * dist

## Base (undimmed) minimap color for a tile. Buildings win over ground type.
static func terrain_color(tile_type: String, has_building: bool) -> Color:
	if has_building:
		return Color(0.15, 0.15, 0.18)
	match tile_type:
		"road": return Color(0.33, 0.33, 0.35)
		"sidewalk": return Color(0.45, 0.45, 0.47)
		"grass": return Color(0.20, 0.40, 0.22)
		"parking": return Color(0.34, 0.30, 0.25)
		_: return Color(0, 0, 0)
