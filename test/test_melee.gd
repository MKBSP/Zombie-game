extends SceneTree

var _failures := 0

func _init() -> void:
	var o := Vector2.ZERO
	var face := Vector2(1, 0)
	_check("dead-ahead in range", Melee.forward_strike(o, face, 50.0, 19.0, Vector2(40, 0)))
	_check("within lateral", Melee.forward_strike(o, face, 50.0, 19.0, Vector2(40, 18)))
	_check("beyond lateral misses", not Melee.forward_strike(o, face, 50.0, 19.0, Vector2(40, 25)))
	_check("beyond range misses", not Melee.forward_strike(o, face, 50.0, 19.0, Vector2(60, 0)))
	_check("behind misses", not Melee.forward_strike(o, face, 50.0, 19.0, Vector2(-40, 0)))
	_check("3 recent hits", Melee.recent_hit_count([9.0, 9.5, 10.0], 10.0, 3.0) == 3)
	_check("old hit excluded", Melee.recent_hit_count([5.0, 9.5, 10.0], 10.0, 3.0) == 2)
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
