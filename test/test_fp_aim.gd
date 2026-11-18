extends SceneTree

## Headless check for first-person aim: the view looks nearly straight up and
## down (and the aim follows it), the shooter's minimap never draws the
## commander's layer (zombie fog of war, zombie markers), bullet spread is an
## angle (the sphere grows with distance from the gun), and shots leave from
## the gun's muzzle. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_fp_aim.gd

var _failures := 0
var P = load("res://scripts/test/test_player.gd")
var VM = load("res://scripts/3d/viewmodel.gd")
var Z = load("res://scripts/3d/zombie_3d.gd")


func _initialize() -> void:
	# --- the first-person city scene ---
	change_scene_to_file("res://scenes/test/camera_test_v6_small_city.tscn")
	for i in 10:
		await process_frame
	var sc := current_scene
	var hud = sc.find_children("*", "CanvasLayer", true, false).filter(func(n): return n.get_script() and n.get_script().resource_path.ends_with("test_hud.gd"))[0]
	_check("minimap skips the commander's layer (fog, zombie markers)", not (hud._map_cam.cull_mask & Z.COMMANDER_LAYER))
	var pl = sc.find_child("TestPlayer", true, false)
	_check("first person looks 85 deg up and down", pl.aim_pitch_range >= 85.0)
	pl.aim_pitch_offset = 85.0
	_check("the rig lets the view reach 85 deg up", is_equal_approx(pl._rig._hip_pitch(), 85.0))
	pl.aim_pitch_offset = -80.0
	await _secs(1.0)
	var flat := Vector2(pl.reticle_point.x - pl.global_position.x, pl.reticle_point.z - pl.global_position.z).length()
	_check("looking down, the aim is where you look (got %.1f m ahead)" % flat, flat < 2.0)

	# --- spent casings: one already freed by its 4 s timer must not break the
	# next shot (it did once 30 were out: the game froze into the debugger) ---
	var vm = sc.find_children("*", "Node3D", true, false).filter(func(n): return n.get_script() == VM)[0]
	var at := Transform3D(Basis(), pl.global_position + Vector3.UP * 3.0)
	for i in 31:
		vm._shell(at, false)
	for c in vm._shells.slice(0, 3):
		c.free()
	vm._shell(at, false)
	_check("casings stay capped", vm._shells.size() <= 31)

	# --- spread is an angle: the sphere grows with distance from the gun ---
	_check("a 10 m sphere is twice a 5 m one", is_equal_approx(P.spread_radius(2.0, 10.0), 2.0 * P.spread_radius(2.0, 5.0)))
	_check("radius = distance x tan(angle)", is_equal_approx(P.spread_radius(45.0, 3.0), 3.0))
	_check("hip spread is wider than aimed", pl.spread_deg_hip > pl.spread_deg_aim and pl.spread_deg_aim > 0.0)

	# --- the shot leaves from the muzzle, unless the barrel pokes through a wall ---
	var space := root.get_world_3d().direct_space_state
	var eye := Vector3(500, 501.6, 500)  # far from the city
	var muzzle := eye + Vector3(0.3, -0.2, -0.6)
	var none: Array[RID] = []
	_check("open air: from the muzzle", VM.shot_origin(space, eye, muzzle, none) == muzzle)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.1)
	cs.shape = box
	wall.add_child(cs)
	root.add_child(wall)
	wall.global_position = eye + Vector3(0, 0, -0.3)
	await physics_frame
	await physics_frame
	_check("barrel through a wall: from the eye", VM.shot_origin(space, eye, muzzle, none) == eye)
	wall.free()

	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _secs(t: float) -> void:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
