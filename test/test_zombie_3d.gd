extends SceneTree

## Headless check for the 3D zombie / commander numbers (scripts/3d/zombie_3d.gd,
## scripts/3d/commander.gd): 2D px stats convert at Balance.FP.px_per_m to the
## spec §5 table, and group orders spread out. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_zombie_3d.gd

var _failures := 0
var Z = load("res://scripts/3d/zombie_3d.gd")
var C = load("res://scripts/3d/commander.gd")


func _init() -> void:
	# --- spec §5: speeds and reach in metres ---
	var want := [1.21, 3.14, 1.09, 0.86]
	for v in 4:
		var got: float = Z.m(Z.STATS[v].speed)
		_check("%s speed %.2f m/s (got %.2f)" % [Z.NAMES[v], want[v], got], absf(got - want[v]) < 0.01)
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
