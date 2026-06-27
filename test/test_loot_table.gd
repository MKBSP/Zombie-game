extends SceneTree

## Headless unit test for LootTable. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_table.gd

var _failures := 0
var _LootTable = load("res://scripts/loot_table.gd")


func _init() -> void:
	# --- Item count: chance_three -> 3, chance_two -> 2, else 1 ---
	_eq_i("r below chance_three is 3", _LootTable.roll_item_count(0.005, 0.20, 0.01), 3)
	_eq_i("r at chance_three boundary is 2", _LootTable.roll_item_count(0.01, 0.20, 0.01), 2)
	_eq_i("r below chance_two is 2", _LootTable.roll_item_count(0.1, 0.20, 0.01), 2)
	_eq_i("r at chance_two boundary is 1", _LootTable.roll_item_count(0.20, 0.20, 0.01), 1)
	_eq_i("high r is 1", _LootTable.roll_item_count(0.9, 0.20, 0.01), 1)

	# --- Weighted kind: cumulative walk over sorted keys {10:1, 20:3} ---
	var w := {10: 1, 20: 3}  # total 4: r<0.25 -> 10, else -> 20
	_eq_i("first bucket", _LootTable.roll_kind(0.0, w), 10)
	_eq_i("just inside first bucket", _LootTable.roll_kind(0.24, w), 10)
	_eq_i("second bucket", _LootTable.roll_kind(0.25, w), 20)
	_eq_i("top of range", _LootTable.roll_kind(0.999, w), 20)

	# --- Distribution sanity: weights roughly match counts over many rolls ---
	var counts := {10: 0, 20: 0}
	for i in range(8000):
		counts[_LootTable.roll_kind(float(i) / 8000.0, w)] += 1
	var ratio := float(counts[20]) / float(counts[10])
	_check("20-weighted kind ~3x as common as 10-weighted (got %f)" % ratio,
		absf(ratio - 3.0) < 0.2)

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


func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
