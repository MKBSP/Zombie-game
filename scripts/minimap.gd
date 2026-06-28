extends Control

## AoE-style minimap for the Zombie Controller. Reads the existing fog
## (FogZombieController.tile_states) for terrain, plus live entity positions.
## Enemy blips only show on currently-visible tiles. Click/drag to jump camera.

var fog_zc: FogZombieController
var camera: Camera2D
var ground_layer: TileMapLayer

func setup(p_fog: FogZombieController, p_cam: Camera2D) -> void:
	fog_zc = p_fog
	camera = p_cam

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var s: float = Balance.MINIMAP.size_px
	var wpx: float = Balance.MINIMAP.world_px
	# Terrain from fog tile_states.
	if fog_zc:
		var gw: int = fog_zc.GRID_W
		var gh: int = fog_zc.GRID_H
		var cw: float = s / gw
		var ch: float = s / gh
		for x in range(gw):
			for y in range(gh):
				var st: int = fog_zc.tile_states[y * gw + x]
				var col: Color
				match st:
					FogZombieController.STATE_UNEXPLORED: col = Color(0, 0, 0, 1)
					FogZombieController.STATE_EXPLORED:   col = Color(0.18, 0.18, 0.2, 1)
					_:                                    col = Color(0.32, 0.34, 0.38, 1)
				draw_rect(Rect2(Vector2(x * cw, y * ch), Vector2(cw + 1, ch + 1)), col)
	# Own zombies (always blipped).
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D:
			draw_circle(MinimapMath.world_to_minimap(z.global_position, wpx, s),
				Balance.MINIMAP.zombie_blip, Color(0.6, 0.1, 0.1))
	# Enemies only where currently visible.
	for grp in ["shooter", "npcs"]:
		for e in get_tree().get_nodes_in_group(grp):
			if e is Node2D and _tile_visible(e.global_position):
				draw_circle(MinimapMath.world_to_minimap(e.global_position, wpx, s),
					Balance.MINIMAP.enemy_blip, Color(1, 1, 0.2))

func _tile_visible(world: Vector2) -> bool:
	if fog_zc == null or ground_layer == null:
		return true
	var t: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world))
	if t.x < 0 or t.y < 0 or t.x >= fog_zc.GRID_W or t.y >= fog_zc.GRID_H:
		return false
	return fog_zc.tile_states[t.y * fog_zc.GRID_W + t.x] == FogZombieController.STATE_VISIBLE

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_jump_camera(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_jump_camera(event.position)

func _jump_camera(local_pos: Vector2) -> void:
	if camera == null:
		return
	var world := MinimapMath.minimap_to_world(local_pos, Balance.MINIMAP.world_px, Balance.MINIMAP.size_px)
	camera.global_position = world.clamp(Vector2.ZERO, Vector2(Balance.MINIMAP.world_px, Balance.MINIMAP.world_px))
