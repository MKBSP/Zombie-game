extends Control

## AoE-style minimap for the Zombie Controller. Reads the existing fog
## (FogZombieController.tile_states) for terrain, plus live entity positions.
## Enemy blips only show on currently-visible tiles. Click/drag to jump camera.

var fog_zc: FogZombieController
var camera: Camera2D
var ground_layer: TileMapLayer
var building_layer: TileMapLayer

var rally_armed: bool = false
signal rally_point_picked(world_pos: Vector2)

var _terrain_colors: PackedColorArray = PackedColorArray()
var _ghosts: Dictionary = {}          # instance_id -> { pos: Vector2, t: float }
var _attacks: Array = []              # [{ pos: Vector2, t: float }]
var _attack_connected: Dictionary = {}
var _ripples: Array = []              # [{ pos: Vector2, t: float }]
var _markers: Array = []              # [{ pos: Vector2, t: float, c: Color }]
var _noise_rng := RandomNumberGenerator.new()

func setup(p_fog: FogZombieController, p_cam: Camera2D) -> void:
	fog_zc = p_fog
	camera = p_cam

func _process(_delta: float) -> void:
	_connect_new_zombies()
	queue_redraw()


## Lazily connect each zombie's took_damage so a hit pulses the minimap.
func _connect_new_zombies() -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		var id := z.get_instance_id()
		if not _attack_connected.has(id) and z.has_signal("took_damage"):
			z.took_damage.connect(func(_zb, _amt): register_attack(z.global_position))
			_attack_connected[id] = true


func register_attack(world_pos: Vector2) -> void:
	_attacks.append({ "pos": world_pos, "t": Time.get_ticks_msec() / 1000.0 })


## A brief command-destination blip on the map (move = green, rally = gold).
func register_move_marker(world_pos: Vector2, marker_color: Color = Color.GREEN) -> void:
	_markers.append({ "pos": world_pos, "t": Time.get_ticks_msec() / 1000.0, "c": marker_color })


## A gunshot ripple at a fuzzed ("general area") position.
func register_noise(world_pos: Vector2) -> void:
	_ripples.append({
		"pos": MinimapMath.fuzz(world_pos, Balance.MINIMAP.gunshot_jitter_px, _noise_rng),
		"t": Time.get_ticks_msec() / 1000.0,
	})

func _draw() -> void:
	var s: float = Balance.MINIMAP.size_px
	var wpx: float = Balance.MINIMAP.world_px
	# Opaque black backing so unexplored stays black (not see-through).
	draw_rect(Rect2(Vector2.ZERO, Vector2(s, s)), Color(0, 0, 0, 1))
	# Terrain + buildings (cached), dimmed by fog state.
	if fog_zc:
		var gw: int = fog_zc.GRID_W
		var gh: int = fog_zc.GRID_H
		if _terrain_colors.size() != gw * gh:
			_build_terrain_cache()
		var cw: float = s / gw
		var ch: float = s / gh
		for x in range(gw):
			for y in range(gh):
				var idx := y * gw + x
				var st: int = fog_zc.tile_states[idx]
				if st == FogZombieController.STATE_UNEXPLORED:
					continue
				var dim: float = 0.4 if st == FogZombieController.STATE_EXPLORED else 1.0
				var base: Color = _terrain_colors[idx]
				var c := Color(base.r * dim, base.g * dim, base.b * dim, 1.0)
				draw_rect(Rect2(Vector2(x * cw, y * ch), Vector2(cw + 1, ch + 1)), c)
	# Discovered static features (shown anywhere explored; they don't move).
	for p in get_tree().get_nodes_in_group("props"):
		if p is Node2D and _tile_explored(p.global_position):
			var pc := Color(0.25, 0.7, 0.25) if "Tree" in str(p.name) else Color(0.5, 0.5, 0.5)
			draw_circle(MinimapMath.world_to_minimap(p.global_position, wpx, s), 1.8, pc)
	for b in get_tree().get_nodes_in_group("loot_boxes"):
		if b is Node2D and _tile_explored(b.global_position):
			var bpos := MinimapMath.world_to_minimap(b.global_position, wpx, s)
			draw_rect(Rect2(bpos - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.84, 0.0))
	# Own zombies (always blipped) — uniform acid green per the design system.
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D:
			draw_circle(MinimapMath.world_to_minimap(z.global_position, wpx, s),
				Balance.MINIMAP.zombie_blip, UIStyle.INFECTION)
	# Enemies only where currently visible; remember last-seen for ghost blips.
	# Player shooters cyan (their role color), NPC survivors yellow.
	var now := Time.get_ticks_msec() / 1000.0
	for grp in ["shooter", "npcs"]:
		var blip_color: Color = UIStyle.FAST_CYAN if grp == "shooter" else Color(1, 1, 0.2)
		for e in get_tree().get_nodes_in_group(grp):
			if e is Node2D and _tile_visible(e.global_position):
				_ghosts[e.get_instance_id()] = { "pos": e.global_position, "t": now }
				draw_circle(MinimapMath.world_to_minimap(e.global_position, wpx, s),
					Balance.MINIMAP.enemy_blip, blip_color)
	# Fading grey ghost blips at last-seen positions.
	for id in _ghosts.keys():
		var g: Dictionary = _ghosts[id]
		var age: float = now - g["t"]
		if age <= 0.05:
			continue  # seen live this frame, already drawn
		if age > Balance.MINIMAP.ghost_fade:
			_ghosts.erase(id)
			continue
		var a: float = 1.0 - age / Balance.MINIMAP.ghost_fade
		draw_circle(MinimapMath.world_to_minimap(g["pos"], wpx, s),
			Balance.MINIMAP.enemy_blip, Color(0.7, 0.7, 0.7, a * 0.8))
	# Under-attack red pulses (AoE-style).
	for i in range(_attacks.size() - 1, -1, -1):
		var aage: float = now - _attacks[i]["t"]
		if aage > Balance.MINIMAP.under_attack_seconds:
			_attacks.remove_at(i)
			continue
		var pulse: float = 0.5 + 0.5 * sin(aage * 18.0)
		draw_circle(MinimapMath.world_to_minimap(_attacks[i]["pos"], wpx, s),
			Balance.MINIMAP.enemy_blip + 2.0, Color(1, 0.1, 0.1, pulse))
	# Gunshot ripples (subtle expanding rings at fuzzed positions).
	for i in range(_ripples.size() - 1, -1, -1):
		var rage: float = now - _ripples[i]["t"]
		if rage > Balance.MINIMAP.ripple_seconds:
			_ripples.remove_at(i)
			continue
		var frac: float = rage / Balance.MINIMAP.ripple_seconds
		var center: Vector2 = MinimapMath.world_to_minimap(_ripples[i]["pos"], wpx, s)
		draw_arc(center, 3.0 + frac * 16.0, 0.0, TAU, 20, Color(1, 1, 1, (1.0 - frac) * 0.4), 1.5)
	# Command destination markers (move / rally).
	for mi in range(_markers.size() - 1, -1, -1):
		var mage: float = now - _markers[mi]["t"]
		if mage > 0.9:
			_markers.remove_at(mi)
			continue
		var mt: float = mage / 0.9
		var mp: Vector2 = MinimapMath.world_to_minimap(_markers[mi]["pos"], wpx, s)
		draw_arc(mp, 2.0 + mt * 9.0, 0.0, TAU, 20, Color(_markers[mi]["c"], 1.0 - mt), 1.5)
	# Frame: hairline green normally, gold while a rally click is armed.
	if rally_armed:
		draw_rect(Rect2(Vector2.ZERO, Vector2(s, s)), Color(1, 0.84, 0, 0.9), false, 2.0)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(s, s)), UIStyle.BORDER, false, 1.0)

func _tile_visible(world: Vector2) -> bool:
	if fog_zc == null or ground_layer == null:
		return true
	var t: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world))
	if t.x < 0 or t.y < 0 or t.x >= fog_zc.GRID_W or t.y >= fog_zc.GRID_H:
		return false
	return fog_zc.tile_states[t.y * fog_zc.GRID_W + t.x] == FogZombieController.STATE_VISIBLE


func _tile_explored(world: Vector2) -> bool:
	if fog_zc == null or ground_layer == null:
		return true
	var t: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world))
	if t.x < 0 or t.y < 0 or t.x >= fog_zc.GRID_W or t.y >= fog_zc.GRID_H:
		return false
	return fog_zc.tile_states[t.y * fog_zc.GRID_W + t.x] != FogZombieController.STATE_UNEXPLORED


func _build_terrain_cache() -> void:
	var gw: int = fog_zc.GRID_W
	var gh: int = fog_zc.GRID_H
	_terrain_colors.resize(gw * gh)
	for x in range(gw):
		for y in range(gh):
			var tile := Vector2i(x, y)
			var has_bld: bool = building_layer != null and building_layer.get_cell_tile_data(tile) != null
			var ttype := ""
			if ground_layer:
				var td: TileData = ground_layer.get_cell_tile_data(tile)
				if td:
					ttype = td.get_custom_data("tile_type")
			_terrain_colors[y * gw + x] = MinimapMath.terrain_color(ttype, has_bld)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if rally_armed:
			rally_armed = false
			rally_point_picked.emit(_local_to_world(event.position))
		else:
			_jump_camera(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not rally_armed:
			_jump_camera(event.position)

func _local_to_world(local_pos: Vector2) -> Vector2:
	return MinimapMath.minimap_to_world(local_pos, Balance.MINIMAP.world_px, Balance.MINIMAP.size_px)

func _jump_camera(local_pos: Vector2) -> void:
	if camera == null:
		return
	var world := _local_to_world(local_pos)
	camera.global_position = world.clamp(Vector2.ZERO, Vector2(Balance.MINIMAP.world_px, Balance.MINIMAP.world_px))
