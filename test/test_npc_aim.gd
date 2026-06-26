extends SceneTree

## Headless unit test for NpcAim. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_npc_aim.gd

var _failures := 0


func _init() -> void:
	var b := {
		panic = 0.35, debuff_running = 0.20, debuff_injured = 0.20,
		debuff_hurt = 0.40, injured_hp_frac = 0.5,
	}
	_eq("panic only", NpcAim.aim_debuff(b, false, 50, 50, 0.0), 0.35)
	_eq("moving adds running", NpcAim.aim_debuff(b, true, 50, 50, 0.0), 0.55)
	_eq("injured tier (below max, above half)", NpcAim.aim_debuff(b, false, 30, 50, 0.0), 0.55)
	_eq("hurt tier (below half) - worse wins", NpcAim.aim_debuff(b, false, 20, 50, 0.0), 0.75)
	_eq("recoil adds on top", NpcAim.aim_debuff(b, false, 50, 50, 0.5), 0.85)
	_eq("recoil full at elapsed 0", NpcAim.recoil_after(0.5, 0.0, 2.0), 0.5)
	_eq("recoil half-decayed", NpcAim.recoil_after(0.5, 1.0, 2.0), 0.25)
	_eq("recoil fully decayed", NpcAim.recoil_after(0.5, 2.0, 2.0), 0.0)
	_eq("recoil with no recover window", NpcAim.recoil_after(0.5, 0.0, 0.0), 0.0)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _eq(label: String, got: float, want: float) -> void:
	if absf(got - want) > 0.0001:
		_failures += 1
		print("FAIL %s: got %f want %f" % [label, got, want])
	else:
		print("PASS %s" % label)
