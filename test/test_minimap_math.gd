extends SceneTree

func _init() -> void:
	var M = load("res://scripts/minimap_math.gd")
	var failed := 0
	# Center of a 3008px world maps to center of a 200px minimap.
	var c: Vector2 = M.world_to_minimap(Vector2(1504, 1504), 3008.0, 200.0)
	if not c.is_equal_approx(Vector2(100, 100)):
		push_error("center map wrong: %s" % c); failed += 1
	# Round-trip: world -> minimap -> world is identity.
	var w := Vector2(800, 2200)
	var back: Vector2 = M.minimap_to_world(M.world_to_minimap(w, 3008.0, 200.0), 3008.0, 200.0)
	if not back.is_equal_approx(w):
		push_error("round trip wrong: %s" % back); failed += 1
	# Fuzz stays within jitter radius.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var f: Vector2 = M.fuzz(Vector2(500, 500), 40.0, rng)
	if f.distance_to(Vector2(500, 500)) > 40.0:
		push_error("fuzz out of range"); failed += 1
	# Terrain colors: building wins, known types map, unknown is black.
	if M.terrain_color("road", false) != Color(0.33, 0.33, 0.35):
		push_error("road color"); failed += 1
	if M.terrain_color("grass", true) != Color(0.15, 0.15, 0.18):
		push_error("building overrides ground"); failed += 1
	if M.terrain_color("nope", false) != Color(0, 0, 0):
		push_error("unknown is black"); failed += 1
	if failed == 0:
		print("test_minimap_math: PASS"); quit(0)
	else:
		print("test_minimap_math: FAIL (%d)" % failed); quit(1)
