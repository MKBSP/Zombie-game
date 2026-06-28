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
