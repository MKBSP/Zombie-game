extends Node2D

@onready var hud: Control = $HUDLayer/HUD
@onready var game_over_screen: Control = $HUDLayer/GameOverScreen
@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var building_layer: TileMapLayer = $BuildingLayer
@onready var prop_scatter: Node = $PropScatter
@onready var shooter_fog_rect: ColorRect = $HUDLayer/ShooterFogRect

var shooter_scene := preload("res://scenes/shooter/shooter.tscn")
var zombie_scene := preload("res://scenes/zombie/zombie.tscn")
var master_zombie_scene := preload("res://scenes/zombie/master_zombie.tscn")

var shooter: CharacterBody2D = null
var master_zombie: CharacterBody2D = null

var fog_shooter: FogShooter
var fog_texture: ImageTexture

func _ready() -> void:
	_create_grid()
	_spawn_shooter()
	_spawn_master_zombie()
	_spawn_standard_zombies()
	hud.setup(shooter, master_zombie)
	prop_scatter.scatter()
	_setup_fog()

func _setup_fog() -> void:
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
	if shooter == null:
		return
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
	add_child(shooter)
	shooter.player_died.connect(_on_player_died)

func _spawn_master_zombie() -> void:
	var tile := _find_clear_road_tile_near(Vector2i(43, 3))
	var spawn_pos := ground_layer.map_to_local(tile) if tile != Vector2i(-1, -1) else Vector2(2700, 300)
	master_zombie = master_zombie_scene.instantiate()
	master_zombie.global_position = spawn_pos
	add_child(master_zombie)
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
			add_child(z)
			z.set_target(shooter)
			z.zombie_died.connect(_on_zombie_died)
			spawned += 1
		attempts += 1

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
	_show_game_over("YOU WIN!")

func _on_player_died() -> void:
	_show_game_over("YOU DIED")

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
