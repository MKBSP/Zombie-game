extends SceneTree

## Headless check for the 3D shooter's health (scripts/test/test_player.gd):
## 2D rules — whole-point damage with fractions carried, hurt widens the
## reticle, death at 0 fires `died` once. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_shooter_health.gd

var _failures := 0


func _init() -> void:
	var p = load("res://scripts/test/test_player.gd").new()
	var deaths := [0]
	p.died.connect(func(): deaths[0] += 1)
	_check("starts at Balance.SHOOTER.max_hp", p.hp == Balance.SHOOTER.max_hp and p.hp == 100)
	_check("unhurt: no reticle growth", is_equal_approx(p.hurt_spread(), 1.0))
	p.take_damage(0.6)
	_check("fraction carried, no damage yet", p.hp == 100)
	p.take_damage(0.6)
	_check("fractions add up to 1 point", p.hp == 99)
	_check("lightly hurt: +debuff_injured", is_equal_approx(p.hurt_spread(), 1.0 + Balance.SHOOTER.debuff_injured))
	p.take_damage(50)
	_check("badly hurt below half: +debuff_hurt", is_equal_approx(p.hurt_spread(), 1.0 + Balance.SHOOTER.debuff_hurt))
	p.take_damage(500)
	_check("dead at 0, never negative", p.is_dead and p.hp == 0)
	p.take_damage(15)
	_check("died fires once", deaths[0] == 1)
	p.free()
	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
