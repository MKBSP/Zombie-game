extends SceneTree

## Headless check for the 3D zombie / commander numbers (scripts/3d/zombie_3d.gd,
## scripts/3d/commander.gd): 3D speed / sight / hearing rules, melee reach from 2D
## px, and group orders spread out. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_zombie_3d.gd

var _failures := 0
var Z = load("res://scripts/3d/zombie_3d.gd")
var C = load("res://scripts/3d/commander.gd")


func _init() -> void:
	# --- 3D speeds: fast = shooter sprint + 1%, the rest from Balance.ZOMBIE_3D ---
	_check("fast = sprint 6.0 + 1%% (got %.3f)" % Z.speed_for(Z.Variant.FAST, 6.0), is_equal_approx(Z.speed_for(Z.Variant.FAST, 6.0), 6.06))
	_check("fast follows a retuned sprint", is_equal_approx(Z.speed_for(Z.Variant.FAST, 7.0), 7.07))
	for v in [Z.Variant.STANDARD, Z.Variant.FAT, Z.Variant.MASTER]:
		_check("%s slower than a walking shooter (3 m/s)" % Z.NAMES[v], Z.speed_for(v, 6.0) < 3.0)
	_check("vision for every variant", Z.NAMES.all(func(n): return Balance.ZOMBIE_3D.vision_m.get(n, 0.0) >= 10.0))
	_check("momentum for every variant", Z.NAMES.all(func(n): return Balance.ZOMBIE_3D.accel_mps2.get(n, 0.0) > 0.0))
	_check("reaction slower than one frame", Balance.ZOMBIE_3D.reaction_s > 0.1 and Balance.ZOMBIE_3D.notice_s > 0.1)
	_check("hearing beyond sight", Balance.ZOMBIE_3D.hearing_m > Balance.ZOMBIE_3D.vision_m.master)
	# melee reach still converts from 2D px (spec §5)
	_check("melee reach ~1.09 m", absf(Z.m(Z.STATS[0].contact_px) - 1.09) < 0.01)
	_check("one stat block + body per variant", Z.STATS.size() == 4 and Z.BODY.size() == 4 and Z.TINT.size() == 4)

	# --- group move: sunflower offsets never stack two units ---
	var pts := []
	for i in 20:
		pts.append(C._spiral(i, 0.9))
	var closest := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			closest = minf(closest, pts[i].distance_to(pts[j]))
	_check("group offsets >= 0.7 m apart (got %.2f)" % closest, closest >= 0.7)
	_check("first unit goes to the click", pts[0] == Vector3.ZERO)

	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
