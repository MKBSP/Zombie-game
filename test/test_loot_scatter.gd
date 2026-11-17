extends SceneTree

## Headless check for scripts/3d/loot_scatter.gd: crates spread randomly but
## evenly (jittered grid + minimum spacing), same seed same map, blocked cells
## just give fewer. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_scatter.gd

var _failures := 0


func _init() -> void:
	var S = load("res://scripts/3d/loot_scatter.gd")
	var R := Rect2(0, 0, 250, 170)
	var all := func(p: Vector2) -> Vector2: return p
	var pts: PackedVector2Array = S.scatter(R, 14, 7, 30.0, all)
	_check("14 crates (got %d)" % pts.size(), pts.size() == 14)
	_check("inside the map", Array(pts).all(func(p): return R.has_point(p)))
	var min_d := INF
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			min_d = minf(min_d, pts[i].distance_to(pts[j]))
	_check("spread >= 30 m (min %.1f)" % min_d, min_d >= 30.0)
	for q in [Rect2(0, 0, 125, 85), Rect2(125, 0, 125, 85), Rect2(0, 85, 125, 85), Rect2(125, 85, 125, 85)]:
		var n := Array(pts).filter(func(p): return q.has_point(p)).size()
		_check("every quarter has crates (%s: %d)" % [q, n], n >= 2)
	_check("same seed, same map", S.scatter(R, 14, 7, 30.0, all) == pts)
	_check("new seed, new map", S.scatter(R, 14, 8, 30.0, all) != pts)
	var right := func(p: Vector2) -> Vector2: return p if p.x > 125 else Vector2.INF
	var half: PackedVector2Array = S.scatter(R, 14, 7, 30.0, right)
	_check("blocked cells just give fewer (%d)" % half.size(), half.size() > 0 and half.size() < 14 and Array(half).all(func(p): return p.x > 125))
	var snap := func(p: Vector2) -> Vector2: return Vector2(roundf(p.x / 10.0) * 10.0, p.y)
	var snapped: PackedVector2Array = S.scatter(R, 14, 7, 30.0, snap)
	_check("accept() may move a point; spacing holds on the moved point", Array(snapped).all(func(p): return fmod(p.x, 10.0) == 0.0))
	_check("tiny map, many crates: no hang, few points", S.scatter(Rect2(0, 0, 20, 20), 50, 1, 30.0, all).size() == 1)
	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
