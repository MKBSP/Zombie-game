extends SceneTree

var _failures := 0

func _init() -> void:
	_check("pistol has a texture", WeaponVisuals.texture(Weapons.PISTOL) != null)
	_check("machinegun has a texture", WeaponVisuals.texture(Weapons.MACHINEGUN) != null)
	_check("club for melee", WeaponVisuals.texture(Weapons.MELEE) != null)
	_check("unknown id is null", WeaponVisuals.texture(-1) == null)
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)

func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
