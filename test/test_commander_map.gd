extends SceneTree

## Headless check for the zombie commander's view (scripts/3d/commander.gd):
## zoom from every input a Mac sends (wheel, trackpad two-finger scroll, pinch,
## -/= keys), and the minimap (scripts/3d/commander_map.gd): world <-> map
## mapping, the explored share, LMB moves the camera there, RMB sends the
## selection there, and a gunshot draws a ring the size of zombie hearing. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_commander_map.gd

var _failures := 0
var C = load("res://scripts/3d/commander.gd")
var M = load("res://scripts/3d/commander_map.gd")


func _initialize() -> void:
	# --- zoom ---
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	_check("wheel up zooms in", C.zoom_factor(wheel) < 1.0)
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	_check("wheel down zooms out", C.zoom_factor(wheel) > 1.0)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0, 1)
	_check("trackpad scroll down zooms out, like the wheel", C.zoom_factor(pan) > 1.0)
	pan.delta = Vector2(0, -1)
	_check("trackpad scroll up zooms in", C.zoom_factor(pan) < 1.0)
	pan.delta = Vector2(0, -400)
	_check("a fast swipe is a capped step", C.zoom_factor(pan) > 0.5)
	var pinch := InputEventMagnifyGesture.new()
	pinch.factor = 1.25
	_check("pinch apart zooms in", is_equal_approx(C.zoom_factor(pinch), 0.8))
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_EQUAL
	_check("= zooms in", C.zoom_factor(key) < 1.0)
	key.keycode = KEY_MINUS
	_check("- zooms out", C.zoom_factor(key) > 1.0)
	key.keycode = KEY_W
	_check("other keys don't zoom", C.zoom_factor(key) == 1.0)

	# --- map math ---
	var r := Rect2(-100, -50, 200, 100)
	var s := Vector2(300, 150)
	_check("map corner", M.to_map(Vector3(-100, 5, -50), r, s).is_equal_approx(Vector2.ZERO))
	_check("map centre", M.to_map(Vector3.ZERO, r, s).is_equal_approx(Vector2(150, 75)))
	_check("back to the world", M.to_world(Vector2(225, 30), r, s).is_equal_approx(Vector3(50, 0, -30)))
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	img.fill_rect(Rect2i(0, 0, 10, 3), Color.WHITE)
	_check("explored share", is_equal_approx(M.explored_frac(img), 0.3))

	# --- in the city ---
	change_scene_to_file("res://scenes/test/camera_test_v6_small_city.tscn")
	for i in 10:
		await process_frame
	while get_nodes_in_group("zombies").size() == 0:
		await process_frame
	var sc := current_scene
	var cmd = sc.find_children("*", "Node3D", true, false).filter(func(n): return n.get_script() == C)[0]
	cmd.set_active(true)
	await process_frame
	var map = cmd._map
	_check("the map shows the whole city", map.rect == cmd._fog.rect and map.size.x > 100 and map.visible)
	var target := Vector3(map.rect.position.x + 30, 0, map.rect.position.y + 20)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = M.to_map(target, map.rect, map.size)
	map._gui_input(click)
	_check("LMB on the map moves the camera there", Vector2(cmd._focus.x, cmd._focus.z).distance_to(Vector2(target.x, target.z)) < 0.5)
	var z = cmd._units()[0]
	cmd._select([z])
	click.button_index = MOUSE_BUTTON_RIGHT
	map._gui_input(click)
	_check("RMB on the map sends the selection there", z.command_mode and Vector2(z.command_target.x, z.command_target.z).distance_to(Vector2(target.x, target.z)) < 2.0)
	# the shooter's own view (torch beam, aim sphere, bullet cone) must not give
	# them away to the commander: only the first-person camera draws them
	var pl = sc.find_child("TestPlayer", true, false)
	var vm = sc.find_children("*", "Node3D", true, false).filter(func(n): return n.get_script() and n.get_script().resource_path.ends_with("viewmodel.gd"))[0]
	var fp_cam: Camera3D = vm.get_parent()
	for g in [[vm._beam, "torch beam"], [pl._sphere, "aim sphere"], [pl._cone, "bullet cone"]]:
		var base: int = g[0].get_meta("fog_layers", g[0].layers)  # the fog swaps layers while unseen
		_check("commander can't see the shooter's %s, even when seen" % g[1], base & cmd._cam.cull_mask == 0)
		_check("the shooter still sees their %s" % g[1], base & fp_cam.cull_mask != 0)
	cmd.hear_gunshot(Vector3.ZERO)
	_check("a gunshot draws a ring on the map", map.rings.size() == 1)
	_check("the ring is zombie hearing", is_equal_approx(map.ring_px(), Balance.ZOMBIE_3D.hearing_m / map.rect.size.x * map.size.x))
	await _secs(M.RING_S + 0.5)
	_check("the ring fades away", map.rings.is_empty())

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
