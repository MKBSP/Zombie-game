extends Node2D

@onready var hud: Control = $HUDLayer/HUD
@onready var game_over_screen: Control = $HUDLayer/GameOverScreen
@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var building_layer: TileMapLayer = $BuildingLayer
@onready var prop_scatter: Node = $PropScatter

var shooter_scene := preload("res://scenes/shooter/shooter.tscn")
var zombie_scene := preload("res://scenes/zombie/zombie.tscn")
var master_zombie_scene := preload("res://scenes/zombie/master_zombie.tscn")

var shooter: CharacterBody2D = null
var master_zombie: CharacterBody2D = null

func _ready() -> void:
	_create_grid()
	_spawn_shooter()
	_spawn_master_zombie()
	_spawn_standard_zombies()
	hud.setup(shooter, master_zombie)
	# Scatter props before spawning entities
	prop_scatter.scatter()

	# Spawn entities (your Phase 1 spawning code goes here)
	_spawn_entities()

func _spawn_entities() -> void:
	# This function replaces your Phase 1 hardcoded spawn positions.
	# We'll update it in Part 8.
	pass

func _create_grid() -> void:
	var grid := GridDrawer.new()
	grid.z_index = -1
	add_child(grid)

func _spawn_shooter() -> void:
	# Find a clear road tile near the bottom-left corner
	var tile := _find_clear_road_tile_near(Vector2i(3, 43))
	var spawn_pos := ground_layer.map_to_local(tile) if tile != Vector2i(-1, -1) else Vector2(300, 2700)

	shooter = shooter_scene.instantiate()
	shooter.global_position = spawn_pos
	add_child(shooter)
	shooter.player_died.connect(_on_player_died)

func _spawn_master_zombie() -> void:
	# Find a clear road tile near the top-right corner
	var tile := _find_clear_road_tile_near(Vector2i(43, 3))
	var spawn_pos := ground_layer.map_to_local(tile) if tile != Vector2i(-1, -1) else Vector2(2700, 300)

	master_zombie = master_zombie_scene.instantiate()
	master_zombie.global_position = spawn_pos
	add_child(master_zombie)
	master_zombie.set_target(shooter)
	master_zombie.master_zombie_died.connect(_on_master_zombie_died)

func _spawn_standard_zombies() -> void:
	# Get the master zombie's tile position, then find nearby clear road tiles
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

## Searches outward from target tile for a road tile with no building on top.
func _find_clear_road_tile_near(target: Vector2i) -> Vector2i:
	for radius in range(0, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var coords := target + Vector2i(dx, dy)
				# Must be a road tile on the ground layer
				var ground_data: TileData = ground_layer.get_cell_tile_data(coords)
				if ground_data == null:
					continue
				var tile_type: String = ground_data.get_custom_data("tile_type")
				if tile_type != "road":
					continue
				# Must have no building tile on top
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

# Inner class — draws grid lines on its own Node2D
class GridDrawer extends Node2D:
	func _draw() -> void:
		var map_size := 3000
		var spacing := 64
		for x in range(0, map_size + 1, spacing):
			draw_line(Vector2(x, 0), Vector2(x, map_size), Color(1, 1, 1, 0.08), 1.0)
		for y in range(0, map_size + 1, spacing):
			draw_line(Vector2(0, y), Vector2(map_size, y), Color(1, 1, 1, 0.08), 1.0)
		draw_rect(Rect2(0, 0, map_size, map_size), Color(1, 1, 1, 0.3), false, 2.0)
