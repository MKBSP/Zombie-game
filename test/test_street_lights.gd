extends SceneTree

## Headless check for the street-light rules (scripts/3d/street_light.gd roll +
## scripts/3d/street_lights.gd kerb placement). Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_street_lights.gd

var _failures := 0
var L = load("res://scripts/3d/street_light.gd")
var P = load("res://scripts/3d/street_lights.gd")


func _init() -> void:
	# --- roll: same spot, same lamp; odds follow the calm / wrecked tables ---
	var a: Dictionary = L.roll(Vector3(12.3, 0, -40.7))
	_check("roll is deterministic", a == L.roll(Vector3(12.3, 0, -40.7)))
	_check("salt rerolls", a != L.roll(Vector3(12.3, 0, -40.7), 1))
	var calm := _tally(0.0)
	var wreck := _tally(1.0)
	_check("calm: ~70%% working (got %d)" % calm.working, absi(calm.working - 2800) < 200)
	_check("wrecked: ~34%% fallen (got %d)" % wreck.fallen, absi(wreck.fallen - 1360) < 200)
	_check("wrecked: few working (got %d)" % wreck.working, wreck.working < 400)
	for st in L.FALLEN:
		_check("fallen build %d occurs" % st, wreck.by_state.get(st, 0) > 150)
	_check("AUTO is never rolled", not calm.by_state.has(L.State.AUTO) and not wreck.by_state.has(L.State.AUTO))
	var dmg := []
	for x in range(-200, 200, 7):
		dmg.append(L.damage_at(Vector3(x * 1.3, 0, x * 0.7)))
	_check("damage noise spans calm and wrecked", dmg.min() < 0.2 and dmg.max() > 0.8)

	# --- kerb spots on a straight 100 m road along +X, 7 m wide ---
	var tris := PackedVector3Array([Vector3(0, 0, -3.5), Vector3(100, 0, -3.5), Vector3(100, 0, 3.5),
			Vector3(0, 0, -3.5), Vector3(100, 0, 3.5), Vector3(0, 0, 3.5)])
	var uvs := PackedVector2Array([Vector2(0, -3.5), Vector2(100, -3.5), Vector2(100, 3.5),
			Vector2(0, -3.5), Vector2(100, 3.5), Vector2(0, 3.5)])
	var spots: Array = P.kerb_spots(tris, uvs, 28.0, 0.6)
	var north := spots.filter(func(s): return s.pos.z < 0.0)
	var south := spots.filter(func(s): return s.pos.z > 0.0)
	_check("4 spots per kerb (got %d / %d)" % [north.size(), south.size()], north.size() == 4 and south.size() == 4)
	_check("spots behind the kerb", spots.all(func(s): return is_equal_approx(absf(s.pos.z), 4.1)))
	_check("out points away from the road", spots.all(func(s): return s.out.dot(Vector3(0, 0, signf(s.pos.z))) > 0.99))
	_check("kerbs staggered by half", is_equal_approx(absf(north[0].pos.x - south[0].pos.x), 14.0))
	_check("spots are off the road", spots.all(func(s): return not P.on_road(s.pos, tris)))
	_check("road centre is on the road", P.on_road(Vector3(50, 0, 1.2), tris))


## Lamps build in _ready, and the root joins the tree only after the first frame.
func _initialize() -> void:
	await process_frame
	# --- bullets shatter the lamp head (the glass is the target) ---
	var lit = _lamp(L.State.WORKING, Vector3(3, 0, 5))
	_check("working lamp has a lens hitbox", _lens_boxes(lit).size() == 1)
	lit.shatter()
	_check("shattered lamp goes dark", lit.kind in [L.State.DEAD, L.State.SPARKING] and (lit._light == null or not lit._light.visible))
	_check("shattered lamp loses its glass", not lit._lens.visible)
	_check("shattered lamp's hitbox is off", _lens_boxes(lit).all(func(b): return b.collision_layer == 0))
	lit.shatter()
	_check("second shot is a no-op", lit.shattered)
	var glassy := _lamp(L.State.DEAD, _spot_with_glass(true))
	_check("dead lamp with glass can still be shot", _lens_boxes(glassy).size() == 1)
	var bare := _lamp(L.State.DEAD, _spot_with_glass(false))
	_check("lamp with no glass has no lens hitbox", _lens_boxes(bare).is_empty())

	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _lamp(st: int, pos: Vector3) -> Node3D:
	var l = L.new()
	l.state = st
	l.position = pos
	root.add_child(l)
	return l


func _lens_boxes(lamp: Node) -> Array:
	return lamp.find_children("*", "StaticBody3D", true, false).filter(func(b): return b.has_method("take_hit"))


## A position whose roll keeps (or smashed) the lens glass.
func _spot_with_glass(want: bool) -> Vector3:
	for i in 500:
		var p := Vector3(i * 2.3, 0, 17.0)
		if L.roll(p).glass == want:
			return p
	return Vector3.ZERO


func _tally(damage: float) -> Dictionary:
	var out := {working = 0, fallen = 0, by_state = {}}
	for i in 4000:
		var r: Dictionary = L.roll(Vector3(i * 3.1, 0, i * -1.7), 0, damage)
		out.by_state[r.state] = out.by_state.get(r.state, 0) + 1
		if r.state == L.State.WORKING:
			out.working += 1
		if r.state in L.FALLEN:
			out.fallen += 1
	return out


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
