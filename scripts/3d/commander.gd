extends Node3D
## Zombie commander over the 3D test city (Phase 10 S7 slice): a tilted,
## rotating RTS camera with the 2D commander's controls and stances ported from
## scripts/zombie_controller.gd. TAB swaps between it and the first-person
## shooter in the same scene, so one person can test both sides. Bakes the
## navmesh and spawns the horde (scripts/3d/zombie_3d.gd) itself for now.
## Fog of war: scripts/3d/commander_fog.gd. Not here yet: minimap, networking,
## the real HUD.
##
## Camera  WASD / arrows / screen edge pan, Q/E (hold) or middle-drag rotate freely
##         (90-degree snaps didn't line up with the street grid), HOME back to
##         north, wheel zoom; the camera tilts toward top-down as it zooms out.
## Select  LMB click or drag a box (SHIFT adds), CTRL+A all, ESC clear / cancel
## Orders  RMB move, or attack the enemy under the cursor
## Groups  CTRL+1-9 save, 1-9 recall
## Stance  Z aggressive, X hold, C free, V patrol (2 LMB points), B flee (1 point;
##         trigger from the buttons), F merge 2 -> fast, T merge 3 -> fat,
##         G then RMB rally the whole horde
## A building between the camera and a zombie dissolves (city_building.gdshader
## `fade`); zombies also show a rim silhouette through anything still in front.

const Z := preload("res://scripts/3d/zombie_3d.gd")
const Fog := preload("res://scripts/3d/commander_fog.gd")
const B := preload("res://scripts/balance.gd")
const VIEWMODEL_LAYER := 2
const PITCH_NEAR := 0.87     # ~50 deg below the horizon, zoomed in
const PITCH_FAR := 1.26      # ~72 deg, zoomed out
const DIST_MIN := 10.0
const DIST_MAX := 110.0
const EDGE_PX := 24.0
const PICK_PX := 28.0
const FADE_TO := 0.9         # spec D3: ~90% transparent
const ROOF_CLEAR := 4.0      # camera keeps this far above the roof under it

@export var player_path: NodePath = ^"../TestPlayer"
@export var fp_rig_path: NodePath = ^"../CameraRig"
@export var city_path: NodePath = ^"../City"
@export var lights_path: NodePath = ^"../StreetLights"  # standing poles go into the navmesh
@export var horde_size := 15            # Balance.WORLD.base_zombie_count; + 1 master
@export var spawn_point := Vector3(-35, 0, -4)  # on the long diagonal street, ~45 m from the shooter
@export var start_active := false

var active := false
var selected: Array = []
var _cam: Camera3D
var _fp_cam: Camera3D
var _player: Node3D
var _rig: Node
var _focus := Vector3.ZERO
var _yaw := 0.0
var _yaw_target := 0.0      # 0 = looking north (-Z); eased toward by _yaw
var _dist := 45.0
var _groups := {}
var _drag_from := Vector2.ZERO
var _dragging := false
var _pressing := false
var _pending := -1          # Z.Movement waiting for points (-1 = none)
var _pending_trigger := 0
var _pending_pts: Array = []
var _rally_armed := false
var _merges: Array = []     # {zombies, kind, t (-1 walking), dur, point}
var _fade := {}             # building MeshInstance3D -> current fade
var _fp_layers: Array = []
var _hud: CanvasLayer
var _status: Label
var _event: Label
var _banner: Label
var _box: Panel
var _region: NavigationRegion3D
var _fog: Fog
var _event_t := 0.0


func _ready() -> void:
	add_to_group("noise_listeners")
	_player = get_node_or_null(player_path)
	_rig = get_node_or_null(fp_rig_path)
	_fp_cam = get_viewport().get_camera_3d()
	if _fp_cam:
		_fp_cam.cull_mask &= ~Z.COMMANDER_LAYER  # the shooter never sees commander markers
	if _player:
		_player.add_to_group("shooter")
		if _player.has_signal("died"):
			_player.died.connect(func(): _banner.text = "SHOOTER DOWN\nthe zombies win")
		if _player is CollisionObject3D:
			_player.set_collision_mask_value(2, true)  # bump into zombies
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 400.0
	_cam.cull_mask = 0xFFFFF & ~VIEWMODEL_LAYER
	var env := get_world_3d().environment
	if env:  # the commander sees the night city clearly: no fog, more ambient
		env = env.duplicate()
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.4, 0.45, 0.6)  # cold "tactical moonlight"
		env.ambient_light_energy = 1.0
		_cam.environment = env
	add_child(_cam)
	_build_hud()
	_bake_nav()
	var city := get_node_or_null(city_path)
	if city:
		_fog = Fog.new()
		add_child(_fog)
		_fog.setup(city, _cam)
	set_active(start_active)


func _bake_nav() -> void:
	var city := get_node_or_null(city_path)
	if city == null:
		push_warning("commander: no city at %s" % city_path)
		return
	city.add_to_group("nav_source")
	var lights := get_node_or_null(lights_path)
	if lights:  # street_lights.gd places its lamps on the first physics frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		lights.add_to_group("nav_source")
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav_source"
	nm.geometry_collision_mask = 1  # lamp debris (layer 5) stays walkable
	nm.agent_radius = 0.5
	nm.agent_height = 1.75   # whole 0.25 m cells (cell_height), or the baker warns
	nm.agent_max_climb = 0.25
	_region = NavigationRegion3D.new()
	_region.navigation_mesh = nm
	add_child(_region)
	_region.bake_finished.connect(_spawn_horde)
	_region.bake_navigation_mesh(true)


func _spawn_horde() -> void:
	# The map picks the new mesh up a few frames after the bake (async
	# iterations); until then every query answers (0, 0, 0).
	var map := get_world_3d().navigation_map
	for f in 300:
		if NavigationServer3D.map_get_closest_point(map, spawn_point) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	for i in horde_size + 1:
		var z := Z.new()
		z.variant = Z.Variant.MASTER if i == 0 else Z.Variant.STANDARD
		z.position = NavigationServer3D.map_get_closest_point(map, spawn_point + _spiral(i, 1.2))
		add_child(z)
		_hook(z)
		if i == 0:
			z.died.connect(_on_master_died)
	_say("Horde ready: %d + master" % horde_size)


func _on_master_died(_z: Node) -> void:
	_banner.text = "MASTER ZOMBIE DOWN\nshooters win"


func _hook(z: Node) -> void:
	z.died.connect(func(dz): selected.erase(dz))
	z.bit.connect(func(_z, t, dmg):
		_ping(t.global_position, Color(1, 0.1, 0.1), 1.0)
		_say("%s bitten (-%d)" % [t.name, dmg]))


## TAB: commander <-> first-person shooter.
func set_active(on: bool) -> void:
	active = on
	if _player:
		_player.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if _rig:
		_rig.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if _fp_layers.is_empty():
		for cl in get_tree().current_scene.find_children("*", "CanvasLayer", true, false):
			if cl != _hud:
				_fp_layers.append(cl)
	for cl in _fp_layers:
		cl.visible = not on
	# First person hides its own body; the commander needs to see it. "Body" is
	# the character model (adventurer.glb), else the placeholder capsule.
	var body: Node3D = null
	if _player:
		body = _player.get_node_or_null("Body")
		if body == null:
			body = _player.get_node_or_null("MeshInstance3D")
	if body:
		body.visible = on
	_hud.visible = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _player and selected.is_empty():
			_focus = _player.global_position
		_cam.current = true
	else:
		_pending = -1
		_rally_armed = false
		_dragging = false
		_box.visible = false
		for mi in _fade:
			if is_instance_valid(mi):
				mi.set_instance_shader_parameter("fade", 0.0)
		_fade.clear()
		if _fp_cam:
			_fp_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		set_active(not active)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	get_viewport().set_input_as_handled()  # the frozen shooter's HUD keys stay quiet
	if event is InputEventKey and event.pressed and not event.echo:
		_key(event)
	elif event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_yaw_target -= event.relative.x * 0.008
		elif _pressing and not _dragging and event.position.distance_to(_drag_from) > 6.0:
			_dragging = true
		if _dragging:
			_box.position = Vector2(minf(_drag_from.x, event.position.x), minf(_drag_from.y, event.position.y))
			_box.size = (event.position - _drag_from).abs()
			_box.visible = true


func _key(e: InputEventKey) -> void:
	var k := e.keycode
	if k >= KEY_1 and k <= KEY_9:
		if e.ctrl_pressed:
			_groups[k - KEY_0] = selected.duplicate()
			_say("Group %d saved (%d)" % [k - KEY_0, selected.size()])
		elif _groups.has(k - KEY_0):
			_select(_groups[k - KEY_0].filter(func(z): return is_instance_valid(z)))
		return
	match k:
		KEY_A when e.ctrl_pressed: _select(_units())
		KEY_ESCAPE: _escape()
		KEY_Z: _combat(Z.Combat.AGGRESSIVE)
		KEY_X: _combat(Z.Combat.HOLD)
		KEY_C: _movement(Z.Movement.FREE, 0)
		KEY_V: _movement(Z.Movement.PATROL, 0)
		KEY_B: _movement(Z.Movement.FLEE, Z.FleeTrigger.ON_SIGHT)
		KEY_F: _merge(Z.Variant.FAST)
		KEY_T: _merge(Z.Variant.FAT)
		KEY_G:
			_rally_armed = true
			_say("Rally: right-click where the horde goes")
		KEY_HOME: _yaw_target = roundf(_yaw / TAU) * TAU


func _mouse_button(e: InputEventMouseButton) -> void:
	if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
		_dist = maxf(_dist * 0.9, DIST_MIN)
	elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_dist = minf(_dist / 0.9, DIST_MAX)
	elif e.button_index == MOUSE_BUTTON_LEFT:
		if _pending >= 0:  # placing patrol / flee points, not selecting
			if e.pressed:
				_place_point(_ground(e.position))
			return
		if e.pressed:
			_pressing = true
			_drag_from = e.position
			_dragging = false
			return
		_pressing = false
		var add := Input.is_key_pressed(KEY_SHIFT)
		if _dragging:
			_dragging = false
			_box.visible = false
			var rect := Rect2(_box.position, _box.size)
			var hit := _units().filter(func(z): return _on_screen(z) and rect.has_point(_screen(z)))
			_select(selected + hit.filter(func(z): return not z in selected) if add else hit)
		else:
			var z := _pick(e.position, _units())
			if z and add:
				_select(selected.filter(func(s): return s != z) if z in selected else selected + [z])
			elif z:
				_select([z])
			elif not add:
				_select([])
	elif e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		var p := _ground(e.position)
		if _rally_armed:
			_rally_armed = false
			_select(_units())
			_order_move(p, Color(1.0, 0.84, 0.0))
			return
		if selected.is_empty():
			return
		var enemy := _pick(e.position, _fog.visible_enemies if _fog else _enemies())
		if enemy:
			for z in _free_units():
				z.set_attack_target(enemy)
			_ping(enemy.global_position, Color(1, 0.15, 0.1), 1.4)
		else:
			_order_move(p, Color(0.3, 1.0, 0.35))


func _process(delta: float) -> void:
	_update_merges(delta)
	_event_t -= delta
	if _event_t <= 0.0:
		_event.text = ""
	if not active:
		return
	_pan(delta)
	_yaw = lerpf(_yaw, _yaw_target, minf(delta * 8.0, 1.0))
	var pitch := lerpf(PITCH_NEAR, PITCH_FAR, inverse_lerp(DIST_MIN, DIST_MAX, _dist))
	var pos := _focus + Basis(Vector3.UP, _yaw) * Vector3(0, sin(pitch), cos(pitch)) * _dist
	# Stay above the roofline (spec D2): never inside a building when zoomed in.
	var roof := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(Vector3(pos.x, 300.0, pos.z), Vector3(pos.x, -1.0, pos.z), 1))
	if not roof.is_empty():
		pos.y = maxf(pos.y, roof.position.y + ROOF_CLEAR)
	_cam.global_position = _cam.global_position.lerp(pos, minf(delta * 12.0, 1.0)) if _cam.current else pos
	_cam.look_at(_focus, Vector3.UP)
	_update_fades(delta)
	_update_status()


func _pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_Q):
		_yaw_target += delta * 1.6
	if Input.is_key_pressed(KEY_E):
		_yaw_target -= delta * 1.6
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport().get_visible_rect().size
	if DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, vs).has_point(mp) and not _dragging:
		if mp.x < EDGE_PX: dir.x -= 1
		if mp.x > vs.x - EDGE_PX: dir.x += 1
		if mp.y < EDGE_PX: dir.y -= 1
		if mp.y > vs.y - EDGE_PX: dir.y += 1
	if dir != Vector2.ZERO:
		var v := Basis(Vector3.UP, _yaw) * Vector3(dir.x, 0, dir.y).normalized()
		_focus += v * _dist * 0.9 * delta


# --- orders -----------------------------------------------------------------------

func _order_move(p: Vector3, col: Color) -> void:
	var units := _free_units()
	for i in units.size():
		units[i].set_command(p + _spiral(i, 0.9))
	_ping(p, col, 1.6)


func _combat(c: int) -> void:
	for z in _free_units():
		z.set_combat(c)
	_say("Aggressive" if c == Z.Combat.AGGRESSIVE else "Hold")


func _movement(mode: int, trigger: int) -> void:
	if selected.is_empty():
		return
	if mode == Z.Movement.FREE:
		for z in _free_units():
			z.set_movement(mode, 0, Vector3.ZERO, Vector3.ZERO)
		_say("Free")
		return
	_pending = mode
	_pending_trigger = trigger
	_pending_pts.clear()
	_say("Patrol: click 2 points" if mode == Z.Movement.PATROL else "Flee: click the point")


func _place_point(p: Vector3) -> void:
	_pending_pts.append(p)
	_ping(p, Color(1.0, 0.9, 0.2), 1.0)
	if _pending_pts.size() < (2 if _pending == Z.Movement.PATROL else 1):
		return
	for z in _free_units():
		z.set_movement(_pending, _pending_trigger, _pending_pts[0], _pending_pts[-1])
	_pending = -1


func _escape() -> void:
	if _pending >= 0 or _rally_armed:
		_pending = -1
		_rally_armed = false
		_say("Cancelled")
		return
	for mg in _merges.duplicate():  # ESC cancels the selection's walking merges
		if mg.t < 0.0 and mg.zombies.any(func(z): return z in selected):
			_end_merge(mg)
	_select([])


# --- merging (2D merge_manager.gd: walk together, lock 2 s per zombie) ---------------

func _merge(kind: int) -> void:
	var need := 2 if kind == Z.Variant.FAST else 3
	var std := _free_units().filter(func(z): return z.variant == Z.Variant.STANDARD)
	if std.size() < need:
		_say("Select %d standard zombies" % need)
		return
	var best: Array = []
	var best_d := INF
	for a in std:  # tightest group: an anchor plus its nearest neighbours
		var near := std.duplicate()
		near.sort_custom(func(p, q): return a.global_position.distance_to(p.global_position) < a.global_position.distance_to(q.global_position))
		var grp := near.slice(0, need)
		var d := 0.0
		for z in grp:
			d += a.global_position.distance_to(z.global_position)
		if d < best_d:
			best_d = d
			best = grp
	var mid := Vector3.ZERO
	for z in best:
		mid += z.global_position / need
	for z in best:
		z.set_merging(true, mid)
	_merges.append({zombies = best, kind = kind, t = -1.0, dur = 0.0, point = mid})
	_say("Merging %d -> %s" % [need, Z.NAMES[kind]])


func _update_merges(delta: float) -> void:
	var touch := Z.m(B.MERGE.touch_distance)
	for mg in _merges.duplicate():
		var alive: Array = mg.zombies.filter(func(z): return is_instance_valid(z) and not z.is_dead)
		if alive.size() < mg.zombies.size():
			_end_merge(mg)
			continue
		if mg.t < 0.0:
			var close := true
			for i in alive.size():
				for j in range(i + 1, alive.size()):
					close = close and Z._flat(alive[i].global_position, alive[j].global_position) <= touch + 0.6
			if close:  # lock in: one stays visible and pulses, the rest vanish into it
				mg.t = 0.0
				mg.dur = B.MERGE.lock_seconds_per_zombie * alive.size()
				for z in alive.slice(1):
					z.visible = false
					z.collision_layer = 0
		else:
			mg.t += delta
			alive[0].set_merge_progress(mg.t / mg.dur)
			if mg.t >= mg.dur:
				var was_selected: bool = alive.any(func(z): return z in selected)
				var nz := Z.new()
				nz.variant = mg.kind
				nz.position = alive[0].global_position
				for z in alive:
					selected.erase(z)
					z.queue_free()
				add_child(nz)
				_hook(nz)
				_merges.erase(mg)
				if was_selected:
					_select(selected + [nz])
				_say("New %s zombie" % Z.NAMES[mg.kind])


func _end_merge(mg: Dictionary) -> void:
	for z in mg.zombies:
		if is_instance_valid(z):
			z.visible = true
			z.collision_layer = 2
			z.set_merging(false)
	_merges.erase(mg)


# --- noise --------------------------------------------------------------------------

## Gunshot from the first-person weapons (scripts/3d/viewmodel.gd): the
## commander hears it anywhere, as in 2D (ripple), even through the fog.
func hear_gunshot(pos: Vector3) -> void:
	_ping(pos, Color(1.0, 0.55, 0.1), 5.0)
	_say("Gunshot")


# --- view ---------------------------------------------------------------------------

## Buildings between the camera and its focus point or any of our zombies dissolve.
func _update_fades(delta: float) -> void:
	var want := {}
	var space := get_world_3d().direct_space_state
	var from := _cam.global_position
	var looks: Array = [[_focus, []]]  # the point the camera orbits, plus every zombie on screen
	for z in _units():
		if _on_screen(z):
			looks.append([z.global_position + Vector3.UP, [z.get_rid()]])
	for l in looks:
		var ex: Array[RID] = []
		ex.assign(l[1])
		for k in 4:
			var q := PhysicsRayQueryParameters3D.create(from, l[0], 1)
			q.exclude = ex
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				break
			ex.append(hit.rid)
			var mi = hit.collider.get_parent()
			if mi is MeshInstance3D and String(mi.name).begins_with("Building"):
				want[mi] = true
	for mi in want:
		if not _fade.has(mi):
			_fade[mi] = 0.0
	for mi in _fade.keys():
		var f := move_toward(_fade[mi], FADE_TO if want.has(mi) else 0.0, delta * 4.0)
		mi.set_instance_shader_parameter("fade", f)
		if f <= 0.0:
			_fade.erase(mi)
		else:
			_fade[mi] = f


func _ping(pos: Vector3, col: Color, radius: float) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = col
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.layers = Z.COMMANDER_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3.UP * 0.1
	mi.scale = Vector3(radius * 0.3, 0.05, radius * 0.3)
	add_child(mi)
	var tw := create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 0.05, radius), 0.5)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(mi.queue_free)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 6
	add_child(_hud)
	var help := Label.new()
	help.position = Vector2(14, 10)
	help.text = "ZOMBIE COMMANDER  (TAB: shooter)\nWASD/edge pan · Q/E or MMB-drag rotate · HOME north · wheel zoom\nLMB select / box (SHIFT add) · CTRL+A all · RMB move / attack\nCTRL+1-9 save group · 1-9 recall · ESC clear"
	_outline(help)
	_hud.add_child(help)
	_status = Label.new()
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = 14
	_status.offset_top = -70
	_outline(_status)
	_hud.add_child(_status)
	_event = Label.new()
	_event.anchor_top = 1.0
	_event.anchor_bottom = 1.0
	_event.offset_left = 14
	_event.offset_top = -100
	_outline(_event)
	_event.modulate = Color(1, 0.85, 0.4)
	_hud.add_child(_event)
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_font_size_override("font_size", 40)
	_outline(_banner)
	_hud.add_child(_banner)
	var col := VBoxContainer.new()
	col.anchor_left = 1.0
	col.anchor_right = 1.0
	col.anchor_top = 1.0
	col.anchor_bottom = 1.0
	col.offset_left = -190
	col.offset_right = -14
	col.offset_top = -390
	col.offset_bottom = -14
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(col)
	for b in [
		["Aggressive (Z)", func(): _combat(Z.Combat.AGGRESSIVE)],
		["Hold (X)", func(): _combat(Z.Combat.HOLD)],
		["Free (C)", func(): _movement(Z.Movement.FREE, 0)],
		["Patrol (V)", func(): _movement(Z.Movement.PATROL, 0)],
		["Flee: sight (B)", func(): _movement(Z.Movement.FLEE, Z.FleeTrigger.ON_SIGHT)],
		["Flee: hit", func(): _movement(Z.Movement.FLEE, Z.FleeTrigger.ON_DAMAGE)],
		["Flee: idle", func(): _movement(Z.Movement.FLEE, Z.FleeTrigger.IDLE)],
		["Merge 2 > fast (F)", func(): _merge(Z.Variant.FAST)],
		["Merge 3 > fat (T)", func(): _merge(Z.Variant.FAT)],
		["Rally all (G)", func(): _key_rally()],
	]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		col.add_child(btn)
	_box = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 1.0, 0.35, 0.12)
	sb.border_color = Color(0.3, 1.0, 0.35, 0.9)
	sb.set_border_width_all(1)
	_box.add_theme_stylebox_override("panel", sb)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	_hud.add_child(_box)


func _key_rally() -> void:
	_rally_armed = true
	_say("Rally: right-click where the horde goes")


func _update_status() -> void:
	var n := {}
	var hp := 0.0
	for z in selected:
		n[Z.NAMES[z.variant]] = n.get(Z.NAMES[z.variant], 0) + 1
		hp += float(z.hp) / z.max_hp
	var parts := []
	for k in n:
		parts.append("%d %s" % [n[k], k])
	var facing: String = ["N", "NW", "W", "SW", "S", "SE", "E", "NE"][posmod(roundi(_yaw / (PI / 4)), 8)]
	var t := "Facing %s · horde %d · selected %d" % [facing, _units().size(), selected.size()]
	if not selected.is_empty():
		var z0 = selected[0]
		t += " (%s) · HP %d%% · %s · %s" % [", ".join(parts), roundi(hp / selected.size() * 100.0),
				"Aggressive" if z0.combat_stance == Z.Combat.AGGRESSIVE else "Hold",
				["Free", "Flee", "Patrol"][z0.movement_mode]]
	for mg in _merges:
		if mg.t >= 0.0:
			t += "\nMerging -> %s %d%%" % [Z.NAMES[mg.kind], roundi(mg.t / mg.dur * 100.0)]
	_status.text = t


# --- helpers ------------------------------------------------------------------------

func _select(units: Array) -> void:
	for z in selected:
		if is_instance_valid(z):
			z.set_selected(false)
	selected = units.filter(func(z): return is_instance_valid(z) and not z.is_dead)
	for z in selected:
		z.set_selected(true)


func _units() -> Array:
	return get_tree().get_nodes_in_group("zombies").filter(func(z): return not z.is_dead and z.visible)


## Selected units that can take orders (merging ones are committed).
func _free_units() -> Array:
	return selected.filter(func(z): return is_instance_valid(z) and not z.merging)


func _enemies() -> Array:
	return get_tree().get_nodes_in_group("shooter") + get_tree().get_nodes_in_group("npcs")


func _screen(n: Node3D) -> Vector2:
	return _cam.unproject_position(n.global_position + Vector3.UP)


func _on_screen(n: Node3D) -> bool:
	return not _cam.is_position_behind(n.global_position) \
			and get_viewport().get_visible_rect().has_point(_screen(n))


func _pick(sp: Vector2, nodes: Array) -> Node3D:
	var best: Node3D = null
	var best_d := PICK_PX
	for n in nodes:
		if _on_screen(n) and _screen(n).distance_to(sp) < best_d:
			best_d = _screen(n).distance_to(sp)
			best = n
	return best


## World point under the cursor (falls back to the y = 0 plane).
func _ground(sp: Vector2) -> Vector3:
	var from := _cam.project_ray_origin(sp)
	var dir := _cam.project_ray_normal(sp)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, 1))
	if not hit.is_empty():
		return hit.position
	var p = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return p if p != null else _focus


## Sunflower offsets so a group order spreads instead of fighting for one spot.
static func _spiral(i: int, spacing: float) -> Vector3:
	var a := i * 2.39996
	return Vector3(cos(a), 0, sin(a)) * spacing * sqrt(i)


func _say(t: String) -> void:
	_event.text = t
	_event_t = 2.5


func _outline(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
