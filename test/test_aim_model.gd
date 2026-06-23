extends SceneTree

## Headless unit test for AimModel. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd

var _failures := 0


func _init() -> void:
	var pistol := Weapons.get_data(Weapons.PISTOL)
	_eq("base", AimModel.spread_coeff(pistol, 0.0, 0.0), pistol.aim_base)
	_eq("max", AimModel.spread_coeff(pistol, 1.0, 0.0), pistol.aim_max)
	_eq("half", AimModel.spread_coeff(pistol, 0.5, 0.0),
		pistol.aim_base + 0.5 * (pistol.aim_max - pistol.aim_base))
	_eq("debuff clamps at 1.0", AimModel.spread_coeff(pistol, 2.0, 0.0), pistol.aim_max)
	_eq("focus floor", AimModel.spread_coeff(pistol, 0.0, 1.0),
		pistol.aim_base * pistol.focus_min_scale)
	_eq("within optimal", AimModel.damage_mult(pistol, pistol.optimal_range_px - 1.0), 1.0)
	_eq("at zero range", AimModel.damage_mult(pistol, pistol.zero_range_px), 0.0)
	_eq("range midpoint", AimModel.damage_mult(pistol,
		(pistol.optimal_range_px + pistol.zero_range_px) / 2.0), 0.5)
	var ok := true
	for _i in range(1000):
		if AimModel.random_in_disk(50.0).length() > 50.0001:
			ok = false
			break
	_check("random_in_disk within radius", ok)

	# --- Headshot ray-distance (Phase 2) ---
	_check("dead-center is a headshot",
		AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 0), 5.0))
	_check("just inside the radius is a headshot",
		AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 4.9), 5.0))
	_check("just outside the radius is not",
		not AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 5.1), 5.0))
	_check("a parallel near-miss is not",
		not AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 50), 5.0))
	_check("works with an un-normalised direction",
		AimModel.is_headshot(Vector2.ZERO, Vector2(10, 0), Vector2(100, 3), 5.0))

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


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
