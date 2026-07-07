extends SceneTree

func _init() -> void:
	var SS = load("res://scripts/shooter_select.gd")
	var fail := 0

	var cands := [
		{ "pos": Vector2(100, 0), "alive": true },
		{ "pos": Vector2(10, 0),  "alive": false },  # closest but dead
		{ "pos": Vector2(50, 0),  "alive": true },
	]
	var idx: int = SS.nearest_alive_index(Vector2.ZERO, cands)
	if idx != 2: push_error("expected nearest alive index 2, got %d" % idx); fail += 1

	# all dead -> -1
	if SS.nearest_alive_index(Vector2.ZERO, [{ "pos": Vector2(1, 1), "alive": false }]) != -1:
		push_error("all dead should be -1"); fail += 1

	# empty -> -1
	if SS.nearest_alive_index(Vector2.ZERO, []) != -1:
		push_error("empty should be -1"); fail += 1

	if fail == 0: print("test_shooter_select: OK")
	quit(fail)
