extends SceneTree
# Run in a THROWAWAY copy (editor closed there):
#   Godot --headless --path . --script test/test_decal_math.gd

func _init() -> void:
	var DM = load("res://scripts/decal_math.gd")
	var failed := 0
	var origin := Vector2(0, 0)
	var world := Vector2(3008, 3008)
	var img := Vector2i(3008, 3008)

	if DM.world_to_image(Vector2(0, 0), origin, world, img) != Vector2i(0, 0):
		push_error("top-left mapping wrong"); failed += 1
	if DM.world_to_image(Vector2(1504, 1504), origin, world, img) != Vector2i(1504, 1504):
		push_error("center mapping wrong"); failed += 1
	# Off-map points clamp into bounds (never out of range).
	if DM.world_to_image(Vector2(9999, -50), origin, world, img) != Vector2i(3007, 0):
		push_error("clamp mapping wrong"); failed += 1
	# Non-zero origin + half-res canvas.
	var half := Vector2i(1504, 1504)
	if DM.world_to_image(Vector2(1504, 0), Vector2(1504, 0), world, half) != Vector2i(0, 0):
		push_error("origin-offset mapping wrong"); failed += 1

	if failed == 0:
		print("test_decal_math: PASS")
		quit(0)
	else:
		print("test_decal_math: FAIL (%d)" % failed)
		quit(1)
