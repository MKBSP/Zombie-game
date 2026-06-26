extends SceneTree

var _failures := 0
var ShooterLighting = load("res://scripts/shooter_lighting.gd")

func _init() -> void:
	_test_cone()
	_test_radial()
	_test_square()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)

func _alpha_at(tex: ImageTexture, x: int, y: int) -> int:
	return int(round(tex.get_image().get_pixel(x, y).a * 255.0))

func _test_cone() -> void:
	var size := 512
	var tex: ImageTexture = ShooterLighting.make_cone_texture(size, deg_to_rad(22.0))
	var c := size / 2
	# A point just forward (+X) of the apex is inside the cone -> lit.
	_check("cone forward lit", _alpha_at(tex, c + 20, c) > 200)
	# Straight up from the apex (-90 deg) is outside a 22-deg half-angle.
	_check("cone up dark", _alpha_at(tex, c, c - 100) == 0)
	# Behind the apex (-X) is outside the cone.
	_check("cone behind dark", _alpha_at(tex, c - 100, c) == 0)
	# The far corner is beyond the radius -> dark.
	_check("cone corner dark", _alpha_at(tex, size - 1, size - 1) == 0)

func _test_radial() -> void:
	var size := 256
	var tex: ImageTexture = ShooterLighting.make_radial_texture(size)
	var c := size / 2
	_check("radial center bright", _alpha_at(tex, c, c) > 230)
	_check("radial edge dark", _alpha_at(tex, c, 0) == 0)
	_check("radial mid partial", _alpha_at(tex, c, c - size / 4) > 80 and _alpha_at(tex, c, c - size / 4) < 200)

func _test_square() -> void:
	var poly: OccluderPolygon2D = ShooterLighting.make_square_occluder_polygon(28.0)
	var pts: PackedVector2Array = poly.polygon
	_check("square has 4 points", pts.size() == 4)
	_check("square corner correct", pts[0].is_equal_approx(Vector2(-14, -14)))
	_check("square closed", poly.closed)

func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
