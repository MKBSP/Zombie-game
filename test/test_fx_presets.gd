extends SceneTree
# Run in a THROWAWAY copy (editor closed there):
#   Godot --headless --path . --script test/test_fx_presets.gd

func _init() -> void:
	var Bal = load("res://scripts/balance.gd")
	var FxPresets = load("res://scripts/fx_presets.gd")
	var failed := 0

	var red: Dictionary = FxPresets.config(FxPresets.RED_BLOOD)
	if red != Bal.FX.presets["red_blood"]:
		push_error("red_blood config mismatch"); failed += 1
	if red.color != Color(0.65, 0.02, 0.02):
		push_error("red_blood color mismatch"); failed += 1
	if red.amount != 14:
		push_error("red_blood amount mismatch"); failed += 1

	var sparks: Dictionary = FxPresets.config(FxPresets.SPARKS)
	if sparks.lifetime != 0.20:
		push_error("sparks lifetime mismatch"); failed += 1
	if sparks.vel_max != 320.0:
		push_error("sparks vel_max mismatch"); failed += 1

	if failed == 0:
		print("test_fx_presets: PASS")
		quit(0)
	else:
		print("test_fx_presets: FAIL (%d)" % failed)
		quit(1)
