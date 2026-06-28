extends SceneTree

func _init() -> void:
	var S = load("res://scripts/stance_logic.gd")
	var failed := 0
	if S.flip_leg(0) != 1: push_error("0->1"); failed += 1
	if S.flip_leg(1) != 0: push_error("1->0"); failed += 1
	if S.arrived(5.0, 8.0) != true: push_error("arrived true"); failed += 1
	if S.arrived(20.0, 8.0) != false: push_error("arrived false"); failed += 1
	if failed == 0:
		print("test_stance_logic: PASS"); quit(0)
	else:
		print("test_stance_logic: FAIL (%d)" % failed); quit(1)
