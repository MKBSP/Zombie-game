extends SceneTree

## Headless unit test for Interact.choose_nearest. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_interact_pick.gd

var _failures := 0
var _Interact = load("res://scripts/interact_pick.gd")


func _init() -> void:
	var origin := Vector2.ZERO

	# Out of range on all -> -1
	_eq_i("none in range", _Interact.choose_nearest(origin, [
		{ "pos": Vector2(100, 0), "radius": 50.0 },
	]), -1)

	# Single in range -> 0
	_eq_i("single in range", _Interact.choose_nearest(origin, [
		{ "pos": Vector2(40, 0), "radius": 50.0 },
	]), 0)

	# Nearest wins even when both in range
	_eq_i("nearest of two", _Interact.choose_nearest(origin, [
		{ "pos": Vector2(50, 0), "radius": 64.0 },
		{ "pos": Vector2(20, 0), "radius": 64.0 },
	]), 1)

	# Tight radius excludes a closer-but-out-of-its-radius candidate:
	# index 0 is closer (30) but its radius is 22 -> out; index 1 (50) within 64.
	_eq_i("per-type radius gating", _Interact.choose_nearest(origin, [
		{ "pos": Vector2(30, 0), "radius": 22.0 },
		{ "pos": Vector2(50, 0), "radius": 64.0 },
	]), 1)

	# Empty list -> -1
	_eq_i("empty list", _Interact.choose_nearest(origin, []), -1)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _eq_i(label: String, got: int, want: int) -> void:
	if got != want:
		_failures += 1
		print("FAIL %s: got %d want %d" % [label, got, want])
	else:
		print("PASS %s" % label)
