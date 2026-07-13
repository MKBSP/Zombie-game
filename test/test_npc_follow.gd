extends SceneTree

func _init() -> void:
	var NF = load("res://scripts/npc_follow.gd")
	var failed := 0

	# --- trail_point: walk back from the newest point along arc length ---
	var trail := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)])
	if NF.trail_point(trail, 50.0) != Vector2(150, 0):
		push_error("tp mid"); failed += 1
	if NF.trail_point(trail, 150.0) != Vector2(50, 0):
		push_error("tp across segment"); failed += 1
	if NF.trail_point(trail, 500.0) != Vector2(0, 0):
		push_error("tp clamp to oldest"); failed += 1
	if NF.trail_point(PackedVector2Array(), 50.0) != Vector2.INF:
		push_error("tp empty"); failed += 1
	if NF.trail_point(PackedVector2Array([Vector2(7, 7)]), 50.0) != Vector2(7, 7):
		push_error("tp single"); failed += 1

	# --- formation_slot: threat to the right -> slots behind/left-right ---
	var S := Vector2.ZERO
	var D := Vector2.RIGHT  # back = (-1,0), side = (0,1)
	if NF.formation_slot(S, D, 0, 2, 56.0, 48.0) != Vector2(-28, 48):
		push_error("fs armed2 slot0"); failed += 1
	if NF.formation_slot(S, D, 1, 2, 56.0, 48.0) != Vector2(-28, -48):
		push_error("fs armed2 slot1"); failed += 1
	if NF.formation_slot(S, D, 0, 1, 56.0, 48.0) != Vector2(-56, 48):
		push_error("fs armed1 slot0"); failed += 1
	if NF.formation_slot(S, D, 0, 0, 56.0, 48.0) != Vector2(-112, 0):
		push_error("fs unarmed rank0"); failed += 1
	if NF.formation_slot(S, D, 1, 0, 56.0, 48.0) != Vector2(-168, 0):
		push_error("fs unarmed rank1"); failed += 1
	if NF.formation_slot(S, D, 2, 2, 56.0, 48.0) != Vector2(-112, 0):
		push_error("fs unarmed behind armed"); failed += 1

	if failed == 0:
		print("test_npc_follow: PASS"); quit(0)
	else:
		print("test_npc_follow: FAIL (%d)" % failed); quit(1)
