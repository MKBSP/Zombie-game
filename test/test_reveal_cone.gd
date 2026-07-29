extends SceneTree

func _init() -> void:
	var F = load("res://scripts/fog_zombie_controller.gd")
	var failed := 0

	var fzc = F.new()
	fzc.GRID_W = 10
	fzc.GRID_H = 10

	var out := {}
	fzc._reveal_cone(Vector2i(5, 5), Vector2.RIGHT, deg_to_rad(20.0), 4, {}, out)
	if not out.has(Vector2i(8, 5)):
		push_error("tile straight ahead should be revealed"); failed += 1
	if out.has(Vector2i(5, 8)):
		push_error("tile behind (perpendicular) should not be revealed"); failed += 1
	if out.has(Vector2i(1, 5)):
		push_error("tile beyond range should not be revealed"); failed += 1

	var blocked := {Vector2i(6, 5): true}
	var out2 := {}
	fzc._reveal_cone(Vector2i(5, 5), Vector2.RIGHT, deg_to_rad(20.0), 4, blocked, out2)
	if out2.has(Vector2i(8, 5)):
		push_error("tile behind a blocker should not be revealed"); failed += 1

	if failed == 0:
		print("test_reveal_cone: PASS"); quit(0)
	else:
		print("test_reveal_cone: FAIL (%d)" % failed); quit(1)
