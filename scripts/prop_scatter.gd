extends Node

## Scatter script — randomly places props on valid tile positions at game start.
## Attach this as a child node of the World scene root, or call scatter() from world.gd.

# Prop scenes to spawn
@export var car_scene: PackedScene
@export var tree_scene: PackedScene
@export var fence_scene: PackedScene
@export var dumpster_scene: PackedScene
@export var statue_scene: PackedScene

# Spawn counts
@export var car_count_min: int = 8
@export var car_count_max: int = 12
@export var tree_count_min: int = 6
@export var tree_count_max: int = 10
@export var fence_count_min: int = 4
@export var fence_count_max: int = 8
@export var dumpster_count_min: int = 3
@export var dumpster_count_max: int = 6

# Minimum distance between props of the same type (in pixels)
@export var min_car_distance: float = 128.0
@export var min_tree_distance: float = 96.0

# References — set these in the Inspector or via code
@export var ground_layer: TileMapLayer
@export var building_layer: TileMapLayer

# Statue fixed position (tile coordinates — center of the park)
@export var statue_tile_pos: Vector2i = Vector2i(5, 18)

# Internal tracking
var _placed_positions: Array[Vector2] = []

func scatter() -> void:
	if ground_layer == null:
		push_error("PropScatter: ground_layer is not set!")
		return

	# Place the statue first (fixed position)
	if statue_scene:
		_place_at_tile(statue_scene, statue_tile_pos)

	# Scatter cars on road and parking tiles
	var road_tiles := _get_tiles_of_type(["road", "parking"])
	_scatter_props(car_scene, road_tiles, randi_range(car_count_min, car_count_max), min_car_distance)

	# Scatter trees on grass tiles
	var grass_tiles := _get_tiles_of_type(["grass"])
	_scatter_props(tree_scene, grass_tiles, randi_range(tree_count_min, tree_count_max), min_tree_distance)

	# Scatter dumpsters on sidewalk tiles
	var sidewalk_tiles := _get_tiles_of_type(["sidewalk"])
	_scatter_props(dumpster_scene, sidewalk_tiles, randi_range(dumpster_count_min, dumpster_count_max), 64.0)

	# Scatter fences on sidewalk tiles adjacent to buildings
	var fence_candidates := _get_sidewalk_tiles_near_buildings(sidewalk_tiles)
	_scatter_props(fence_scene, fence_candidates, randi_range(fence_count_min, fence_count_max), 128.0)


## Returns an array of tile coordinates (Vector2i) whose custom data "tile_type" matches any in the given list.
func _get_tiles_of_type(types: Array[String]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var used_rect: Rect2i = ground_layer.get_used_rect()

	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
		for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
			var coords := Vector2i(x, y)
			var tile_data: TileData = ground_layer.get_cell_tile_data(coords)
			if tile_data == null:
				continue
			var tile_type: String = tile_data.get_custom_data("tile_type")
			if tile_type in types:
				result.append(coords)
	return result


## Returns sidewalk tiles that have at least one adjacent building tile.
func _get_sidewalk_tiles_near_buildings(sidewalk_tiles: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var neighbors := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

	for tile_pos in sidewalk_tiles:
		for offset in neighbors:
			var neighbor_pos := tile_pos + offset
			# Check if the neighbor is a building tile on the BuildingLayer
			if building_layer:
				var building_data: TileData = building_layer.get_cell_tile_data(neighbor_pos)
				if building_data != null:
					result.append(tile_pos)
					break  # One adjacent building is enough
	return result


## Places a number of props randomly on valid tile positions, respecting minimum distance.
func _scatter_props(scene: PackedScene, valid_tiles: Array[Vector2i], count: int, min_distance: float) -> void:
	if scene == null or valid_tiles.is_empty():
		return

	# Shuffle the valid tiles for randomness
	var shuffled := valid_tiles.duplicate()
	shuffled.shuffle()

	var placed := 0
	for tile_pos in shuffled:
		if placed >= count:
			break

		# Convert tile coordinates to world (pixel) position
		var world_pos: Vector2 = ground_layer.map_to_local(tile_pos)

		# Check minimum distance from other placed props
		if _is_too_close(world_pos, min_distance):
			continue

		# Place the prop
		var prop: Node2D = scene.instantiate()
		prop.global_position = world_pos
		get_parent().add_child(prop)
		_placed_positions.append(world_pos)
		placed += 1


## Places a single prop at a specific tile position.
func _place_at_tile(scene: PackedScene, tile_pos: Vector2i) -> void:
	var world_pos: Vector2 = ground_layer.map_to_local(tile_pos)
	var prop: Node2D = scene.instantiate()
	prop.global_position = world_pos
	get_parent().add_child(prop)
	_placed_positions.append(world_pos)


## Returns true if the given position is too close to any already-placed prop.
func _is_too_close(pos: Vector2, min_distance: float) -> bool:
	for placed_pos in _placed_positions:
		if pos.distance_to(placed_pos) < min_distance:
			return true
	return false
