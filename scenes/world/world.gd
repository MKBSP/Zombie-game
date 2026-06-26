extends Node2D

@onready var hud: Control = $HUDLayer/HUD
@onready var game_over_screen: Control = $HUDLayer/GameOverScreen
@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var building_layer: TileMapLayer = $BuildingLayer
@onready var prop_scatter: Node = $PropScatter
@onready var shooter_fog_rect: ColorRect = $HUDLayer/ShooterFogRect
@onready var zc_node: ZombieController = $ZombieControllerNode
@onready var zc_camera: Camera2D = $ZCCamera
@onready var entities: Node2D = $Entities
@onready var merge_manager: MergeManager = $MergeManager
@onready var aim_cursor: Control = $HUDLayer/AimCursor

var shooter_scene := preload("res://scenes/shooter/shooter.tscn")
var zombie_scene := preload("res://scenes/zombie/zombie.tscn")
var master_zombie_scene := preload("res://scenes/zombie/master_zombie.tscn")
var npc_scene := preload("res://scenes/npc/npc_human.tscn")
var pickup_scene := preload("res://scenes/pickup/pickup.tscn")

# From Balance.WORLD (assigned in _ready).
var npc_count: int
## Testing switch: skip the fog-of-war overlay entirely.
var fog_enabled: bool

var shooter: CharacterBody2D = null
var master_zombie: CharacterBody2D = null

var fog_shooter: FogShooter
var fog_texture: ImageTexture

var _client_ready: bool = false

func _ready() -> void:
	npc_count = Balance.WORLD.npc_count
	fog_enabled = Balance.WORLD.fog_enabled
	# Shared seed so static scenery (props) looks identical on both peers.
	# Must run BEFORE any other RNG use so both peers consume it in step.
	if GameState.multiplayer_active:
		seed(GameState.world_seed)
	_create_grid()
	prop_scatter.scatter()

	if multiplayer.is_server():
		# Server (also single player): spawn and simulate everything.
		_spawn_shooter()
		_spawn_master_zombie()
		_spawn_standard_zombies()
		_spawn_npcs()
		_spawn_items()
		if GameState.is_dedicated_server:
			# Authoritative server only — no local player, no view to set up.
			# The shooter is driven by the HUMAN client; the zombie controller
			# is driven by the ZOMBIE client.
			shooter.controls_enabled = false
			zc_node.deactivate()
		else:
			hud.setup(shooter, master_zombie)
			_setup_fog()
			_apply_role()
	else:
		# Client: entities arrive via the MultiplayerSpawner.
		$MultiplayerSpawner.spawned.connect(_on_entity_spawned)
		for child in entities.get_children():
			_on_entity_spawned(child)


## Client-side: wire up references as replicated entities arrive.
func _on_entity_spawned(node: Node) -> void:
	if node.is_in_group("shooter"):
		shooter = node
	elif node.is_in_group("master_zombie"):
		master_zombie = node
		if _client_ready:
			hud.master_zombie = master_zombie
	if not _client_ready and shooter != null:
		_client_ready = true
		hud.setup(shooter, master_zombie)
		_setup_fog()
		_apply_role()
		print("[net] client ready - role=", GameState.role, " entities=", entities.get_child_count())


## Configure controls, cameras, fog and UI for this window's role.
func _apply_role() -> void:
	var shooter_cam: Camera2D = shooter.get_node("Camera2D")
	if GameState.role == GameState.Role.HUMAN:
		shooter.controls_enabled = true
		shooter_cam.enabled = true
		shooter_cam.make_current()
		shooter_fog_rect.visible = fog_enabled
		zc_node.deactivate()
		aim_cursor.setup(shooter)
	else:
		shooter.controls_enabled = false
		shooter_cam.enabled = false
		shooter_fog_rect.visible = false
		hud.visible = false
		zc_node.activate()
		zc_camera.make_current()
		aim_cursor.teardown()


func _setup_fog() -> void:
	if not fog_enabled:
		return  # testing: fog overlay disabled
	fog_shooter = FogShooter.new()
	add_child(fog_shooter)
	fog_shooter.ground_layer = ground_layer
	fog_shooter.building_layer = building_layer
	fog_shooter.cache_occluders()

	# Cache prop occluders — anything in the "occluders" group
	var prop_occluders: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("occluders"):
		if node is Node2D:
			prop_occluders.append(node)
	fog_shooter.cache_prop_occluders(prop_occluders)

	fog_texture = ImageTexture.create_from_image(fog_shooter.visibility_image)
	var shader_material: ShaderMaterial = shooter_fog_rect.material as ShaderMaterial
	shader_material.set_shader_parameter("visibility_tex", fog_texture)

func _process(_delta: float) -> void:
	if shooter == null or fog_shooter == null:
		return
	if GameState.role != GameState.Role.HUMAN:
		return  # Shooter fog is hidden in zombie role; skip the per-frame update
	var shooter_tile: Vector2i = ground_layer.local_to_map(
		ground_layer.to_local(shooter.global_position)
	)
	var facing_angle: float = shooter.global_rotation
	fog_shooter.update_visibility(shooter_tile, facing_angle)
	fog_texture.update(fog_shooter.visibility_image)

	# Update camera position in the shader
	var camera: Camera2D = shooter.get_node("Camera2D")
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var cam_center: Vector2 = camera.get_screen_center_position()
	var cam_top_left: Vector2 = cam_center - vp_size / 2.0

	var shader_material: ShaderMaterial = shooter_fog_rect.material as ShaderMaterial
	shader_material.set_shader_parameter("camera_top_left", cam_top_left)
	shader_material.set_shader_parameter("viewport_size", vp_size)

func _create_grid() -> void:
	var grid := GridDrawer.new()
	grid.z_index = -1
	add_child(grid)

func _spawn_shooter() -> void:
	var tile := _find_clear_road_tile_near(Vector2i(3, 43))
	var spawn_pos := ground_layer.map_to_local(tile) if tile != Vector2i(-1, -1) else Vector2(300, 2700)
	shooter = shooter_scene.instantiate()
	shooter.global_position = spawn_pos
	entities.add_child(shooter, true)
	shooter.player_died.connect(_on_player_died)

func _spawn_master_zombie() -> void:
	var tile := _find_clear_road_tile_near(Vector2i(43, 3))
	var spawn_pos := ground_layer.map_to_local(tile) if tile != Vector2i(-1, -1) else Vector2(2700, 300)
	master_zombie = master_zombie_scene.instantiate()
	master_zombie.global_position = spawn_pos
	entities.add_child(master_zombie, true)
	master_zombie.set_target(shooter)
	master_zombie.master_zombie_died.connect(_on_master_zombie_died)

func _spawn_standard_zombies() -> void:
	var master_tile := ground_layer.local_to_map(master_zombie.global_position)
	var spawned := 0
	var attempts := 0
	while spawned < 5 and attempts < 100:
		var offset := Vector2i(randi_range(-5, 5), randi_range(-5, 5))
		var candidate := master_tile + offset
		var tile := _find_clear_road_tile_near(candidate)
		if tile != Vector2i(-1, -1):
			var z := zombie_scene.instantiate()
			z.global_position = ground_layer.map_to_local(tile)
			entities.add_child(z, true)
			z.set_target(shooter)
			z.zombie_died.connect(_on_zombie_died)
			spawned += 1
		attempts += 1

func _spawn_npcs() -> void:
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	var spawned := 0
	var attempts := 0
	while spawned < npc_count and attempts < 200:
		attempts += 1
		var candidate := Vector2i(randi_range(1, 45), randi_range(1, 45))
		var td: TileData = ground_layer.get_cell_tile_data(candidate)
		if td == null or not td.get_custom_data("tile_type") in walkable:
			continue
		if building_layer.get_cell_tile_data(candidate) != null:
			continue
		var world_pos: Vector2 = ground_layer.map_to_local(candidate)
		# Keep NPCs at least 5 tiles (320px) from the shooter and all zombies
		var too_close := false
		if shooter and world_pos.distance_to(shooter.global_position) < 320.0:
			too_close = true
		if not too_close:
			for z in get_tree().get_nodes_in_group("zombies"):
				if z is Node2D and world_pos.distance_to(z.global_position) < 320.0:
					too_close = true
					break
		if too_close:
			continue
		var npc: Node2D = npc_scene.instantiate()
		npc.global_position = world_pos
		npc.ground_layer = ground_layer
		npc.building_layer = building_layer
		npc.shooter = shooter
		npc.converted.connect(_on_npc_converted)
		entities.add_child(npc, true)
		spawned += 1

## Scatter weapon/ammo/medpack pickups on walkable tiles, away from the shooter.
## Server-only; pickups replicate to the client via the MultiplayerSpawner.
func _spawn_items() -> void:
	var counts := {
		Pickup.Kind.AMMO_MAG: 3,
		Pickup.Kind.RIFLE: 1,
		Pickup.Kind.SHOTGUN: 1,
		Pickup.Kind.MACHINEGUN: 1,
		Pickup.Kind.MELEE: 1,
		Pickup.Kind.MEDPACK: 2,
	}
	for kind in counts:
		for _i in range(counts[kind]):
			# Keep the special guns close to the shooter so they're findable
			# during testing; everything else scatters across the map.
			var near_player: bool = kind == Pickup.Kind.RIFLE or kind == Pickup.Kind.SHOTGUN or kind == Pickup.Kind.MACHINEGUN or kind == Pickup.Kind.MELEE
			var pos := _find_item_spawn(near_player)
			if pos == Vector2.INF:
				continue
			var p: Node2D = pickup_scene.instantiate()
			p.kind = kind
			p.global_position = pos
			entities.add_child(p, true)

## Pick a walkable tile for an item. When `near` is true, bias toward tiles
## within ~8 tiles of the shooter; otherwise just keep clear of the spawn.
func _find_item_spawn(near_player: bool = false) -> Vector2:
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	for _attempt in range(200):
		var candidate := Vector2i(randi_range(1, 45), randi_range(1, 45))
		var td: TileData = ground_layer.get_cell_tile_data(candidate)
		if td == null or not td.get_custom_data("tile_type") in walkable:
			continue
		if building_layer.get_cell_tile_data(candidate) != null:
			continue
		var world_pos: Vector2 = ground_layer.map_to_local(candidate)
		if shooter:
			var dist := world_pos.distance_to(shooter.global_position)
			if dist < 200.0:
				continue  # never right on top of the spawn
			if near_player and dist > 512.0:
				continue  # specials stay within ~8 tiles for testing
		return world_pos
	return Vector2.INF

func _on_npc_converted(zombie: Node2D) -> void:
	if zombie.has_signal("zombie_died"):
		zombie.zombie_died.connect(_on_zombie_died)


# --- Zombie Controller commands (sent by whichever peer plays ZOMBIE) ---

@rpc("any_peer", "call_local", "reliable")
func rpc_command_move(zombie_names: Array, world_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	for n in zombie_names:
		var z := entities.get_node_or_null(NodePath(String(n)))
		if z and z.has_method("set_command"):
			z.set_command(world_pos)

@rpc("any_peer", "call_local", "reliable")
func rpc_request_merge(zombie_names: Array, type: String) -> void:
	if not multiplayer.is_server():
		return
	var zombies: Array[Node2D] = []
	for n in zombie_names:
		var z := entities.get_node_or_null(NodePath(String(n)))
		if z is Node2D:
			zombies.append(z)
	var required: int = 2 if type == "fast" else 3
	if zombies.size() < required:
		return
	merge_manager.start_merge(zombies, type)

@rpc("any_peer", "call_local", "reliable")
func rpc_cancel_merge() -> void:
	if not multiplayer.is_server():
		return
	merge_manager.cancel_merge()


func _find_clear_road_tile_near(target: Vector2i) -> Vector2i:
	for radius in range(0, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var coords := target + Vector2i(dx, dy)
				var ground_data: TileData = ground_layer.get_cell_tile_data(coords)
				if ground_data == null:
					continue
				var tile_type: String = ground_data.get_custom_data("tile_type")
				if tile_type != "road":
					continue
				var building_data: TileData = building_layer.get_cell_tile_data(coords)
				if building_data != null:
					continue
				return coords
	return Vector2i(-1, -1)

func _on_zombie_died(_zombie: Node2D) -> void:
	pass

func _on_master_zombie_died() -> void:
	if multiplayer.is_server():
		_game_over.rpc(true)

func _on_player_died() -> void:
	if multiplayer.is_server():
		_game_over.rpc(false)

## Broadcast by the server; each peer renders the message for its own role.
@rpc("authority", "call_local", "reliable")
func _game_over(master_died: bool) -> void:
	# Dedicated server: no UI and never pause the authoritative tree. Reset the
	# room so the same players can rematch (or a new host can take over).
	if multiplayer.is_server() and GameState.is_dedicated_server:
		Net.server_on_match_ended()
		return
	var msg: String
	if master_died:
		msg = "YOU LOSE" if GameState.role == GameState.Role.ZOMBIE else "YOU WIN!"
	else:
		msg = "YOU WIN!" if GameState.role == GameState.Role.ZOMBIE else "YOU DIED"
	_show_game_over(msg)

func _show_game_over(message: String) -> void:
	game_over_screen.show_message(message)

class GridDrawer extends Node2D:
	func _draw() -> void:
		var map_size := 3000
		var spacing := 64
		for x in range(0, map_size + 1, spacing):
			draw_line(Vector2(x, 0), Vector2(x, map_size), Color(1, 1, 1, 0.08), 1.0)
		for y in range(0, map_size + 1, spacing):
			draw_line(Vector2(0, y), Vector2(map_size, y), Color(1, 1, 1, 0.08), 1.0)
		draw_rect(Rect2(0, 0, map_size, map_size), Color(1, 1, 1, 0.3), false, 2.0)
