extends RefCounted
class_name FlashlightGlow

## Pure geometry check: is `zombie_pos` within the shooter's flashlight cone
## (distance + angle from the shooter's aim) with clear tile line-of-sight?
## Used to decide whether the zombie-side flashlight glow should jump to full
## brightness — see design spec §4, "risk/reward promotion".
static func zombie_caught(
	shooter_pos: Vector2, shooter_rot: float, zombie_pos: Vector2,
	range_px: float, half_angle_rad: float,
	ground_layer: TileMapLayer, blocked: Dictionary
) -> bool:
	var to_zombie := zombie_pos - shooter_pos
	if to_zombie.length() > range_px:
		return false
	var dir := Vector2.RIGHT.rotated(shooter_rot)
	if to_zombie.length() > 0.0 and absf(to_zombie.normalized().angle_to(dir)) > half_angle_rad:
		return false
	var FZC = load("res://scripts/fog_zombie_controller.gd")
	var from_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(shooter_pos))
	var to_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(zombie_pos))
	return FZC.tile_line_clear(from_tile, to_tile, blocked)
