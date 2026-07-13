extends SceneTree

func _init() -> void:
	var F = load("res://scripts/fog_zombie_controller.gd")
	var failed := 0
	var blocked := { Vector2i(2, 0): true }
	if F.tile_line_clear(Vector2i(0, 0), Vector2i(4, 0), blocked) != false:
		push_error("straight blocked"); failed += 1
	if F.tile_line_clear(Vector2i(0, 0), Vector2i(4, 4), blocked) != true:
		push_error("diagonal clear"); failed += 1
	if F.tile_line_clear(Vector2i(0, 0), Vector2i(2, 0), blocked) != true:
		push_error("endpoint not a blocker"); failed += 1
	if F.tile_line_clear(Vector2i(2, 0), Vector2i(4, 0), blocked) != true:
		push_error("start not a blocker"); failed += 1
	if F.tile_line_clear(Vector2i(0, 0), Vector2i(0, 0), {}) != true:
		push_error("self"); failed += 1
	if F.tile_line_clear(Vector2i(4, 0), Vector2i(0, 0), blocked) != false:
		push_error("reverse blocked"); failed += 1
	if failed == 0:
		print("test_fog_los: PASS"); quit(0)
	else:
		print("test_fog_los: FAIL (%d)" % failed); quit(1)
