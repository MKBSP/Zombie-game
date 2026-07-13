extends SceneTree

func _init() -> void:
	var T = load("res://scripts/targeting.gd")
	var failed := 0
	var from := Vector2.ZERO

	var cands := [
		{ "pos": Vector2(200, 0), "eligible": true },
		{ "pos": Vector2(50, 0),  "eligible": true },
		{ "pos": Vector2(10, 0),  "eligible": false },  # closest but ineligible
	]
	# Nearest eligible within 300 is index 1 (50px), not the ineligible 10px one.
	if T.nearest_index(from, cands, 300.0) != 1:
		push_error("expected index 1"); failed += 1
	# Vision too short to reach anyone eligible -> -1
	if T.nearest_index(from, cands, 30.0) != -1:
		push_error("expected -1 for short vision"); failed += 1
	# Empty list -> -1
	if T.nearest_index(from, [], 300.0) != -1:
		push_error("expected -1 for empty"); failed += 1

	# --- visible_to_any / watchers_from ---
	var W := [
		{ "pos": Vector2(0, 0), "vision_px": 128.0 },
		{ "pos": Vector2(1000, 0), "vision_px": 64.0 },
	]
	if T.visible_to_any(Vector2(100, 0), W) != true:
		push_error("vta near"); failed += 1
	if T.visible_to_any(Vector2(500, 0), W) != false:
		push_error("vta far"); failed += 1
	if T.visible_to_any(Vector2(1060, 0), W) != true:
		push_error("vta second watcher"); failed += 1
	if T.visible_to_any(Vector2(0, 129), W) != false:
		push_error("vta edge"); failed += 1
	if T.watchers_from([]).size() != 0:
		push_error("wf empty"); failed += 1

	if failed == 0:
		print("test_targeting: PASS"); quit(0)
	else:
		print("test_targeting: FAIL (%d)" % failed); quit(1)
