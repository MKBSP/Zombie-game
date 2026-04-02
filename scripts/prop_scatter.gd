extends Node

## Scatter script — places props at game start.
## Fences are fixed positions. Cars, trees, dumpsters are randomised within defined zones.

# Prop scenes to spawn
@export var car_scene: PackedScene
@export var tree_scene: PackedScene
@export var fence_scene: PackedScene
@export var dumpster_scene: PackedScene
@export var statue_scene: PackedScene

# Spawn counts
@export var car_count: int = 10
@export var tree_count: int = 10
@export var dumpster_count: int = 3

# References — set these in the Inspector
@export var ground_layer: TileMapLayer
@export var building_layer: TileMapLayer

# Statue fixed position (tile coordinates — center of the park)
@export var statue_tile_pos: Vector2i = Vector2i(35, 5)

# Internal tracking (used for dumpster/car minimum distance)
var _placed_positions: Array[Vector2] = []

func scatter() -> void:
	if ground_layer == null:
		push_error("PropScatter: ground_layer is not set!")
		return

	# 1. Place the statue at its fixed position
	if statue_scene:
		_place_at_tile(statue_scene, statue_tile_pos)

	# 2. Place fences at hardcoded positions around the two parking lots
	_place_fences()

	# 3. Scatter cars on all road and parking tiles
	var road_tiles := _get_tiles_of_type(["road", "parking"])
	_scatter_props(car_scene, road_tiles, car_count, 128.0)

	# 4. Scatter dumpsters on sidewalk tiles
	var sidewalk_tiles := _get_tiles_of_type(["sidewalk"])
	_scatter_props(dumpster_scene, sidewalk_tiles, dumpster_count, 96.0)

	# 5. Scatter trees within the two defined grass zones only
	_scatter_trees()


## Places fences at fixed tile positions around both parking lots.
## Each tile gets one fence prop placed at the centre of that tile.
## Places fences at fixed positions on tile edges, with correct rotation.
func _place_fences() -> void:
	if fence_scene == null:
		return

	var tile_size := 64.0
	var half := tile_size / 2.0  # 32.0

	# --- Parking lot 1 ---

	# Left side: fence on the LEFT edge of column 27 (between col 26 and col 27)
	# Vertical fence → rotated 90°, offset X = -half
	var left_tiles_1: Array[Vector2i] = [
		Vector2i(27, 27), Vector2i(27, 28), Vector2i(27, 29),
	]
	for tile_pos in left_tiles_1:
		_place_fence_at_edge(tile_pos, Vector2(-half, 0), PI / 2)

	# Right side: fence on the RIGHT edge of column 33 (between col 33 and col 34)
	# Vertical fence → rotated 90°, offset X = +half
	var right_tiles_1: Array[Vector2i] = [
		Vector2i(33, 27), Vector2i(33, 28), Vector2i(33, 29),
	]
	for tile_pos in right_tiles_1:
		_place_fence_at_edge(tile_pos, Vector2(half, 0), PI / 2)

	# North/top edge: fence on the TOP edge of row 27
	# Horizontal fence → no rotation, offset Y = -half
	# Excludes (30, 27)
	var top_tiles_1: Array[Vector2i] = [
		Vector2i(28, 27), Vector2i(29, 27),
		Vector2i(31, 27), Vector2i(32, 27),
		# 27,27 and 33,27 are corners — already covered by left/right above,
		# but adding them here as horizontal top-edge fences too gives a clean corner.
		Vector2i(27, 27), Vector2i(33, 27),
	]
	for tile_pos in top_tiles_1:
		_place_fence_at_edge(tile_pos, Vector2(0, -half), 0)

	# --- Parking lot 2 ---

	# Left side: fence on the LEFT edge of column 39
	var left_tiles_2: Array[Vector2i] = [
		Vector2i(39, 41), Vector2i(39, 42), Vector2i(39, 43),
	]
	for tile_pos in left_tiles_2:
		_place_fence_at_edge(tile_pos, Vector2(-half, 0), PI / 2)

	# Right side: fence on the RIGHT edge of column 41
	var right_tiles_2: Array[Vector2i] = [
		Vector2i(41, 41), Vector2i(41, 42), Vector2i(41, 43), Vector2i(41, 44),
	]
	for tile_pos in right_tiles_2:
		_place_fence_at_edge(tile_pos, Vector2(half, 0), PI / 2)


## Instances a fence at a tile position, offset to a specific edge, with a given rotation.
func _place_fence_at_edge(tile_pos: Vector2i, offset: Vector2, rot: float) -> void:
	var world_pos: Vector2 = ground_layer.map_to_local(tile_pos) + offset
	var prop: Node2D = fence_scene.instantiate()
	prop.global_position = world_pos
	prop.rotation = rot
	get_parent().add_child(prop)

## Scatters trees only within the two defined grass zones.
func _scatter_trees() -> void:
	if tree_scene == null:
		return

	# Zone 1: small grass square, tiles (6,29) to (9,30)
	var zone1: Array[Vector2i] = []
	for x in range(6, 10):       # 6, 7, 8, 9
		for y in range(29, 31):   # 29, 30
			zone1.append(Vector2i(x, y))

	# Zone 2: big park, tiles (27,2) to (44,9)
	var zone2: Array[Vector2i] = []
	for x in range(27, 45):      # 27 to 44
		for y in range(2, 10):    # 2 to 9
			zone2.append(Vector2i(x, y))

	# Filter both zones to grass tiles only (in case any tiles are road/sidewalk)
	var valid_zone1 := _filter_to_type(zone1, "grass")
	var valid_zone2 := _filter_to_type(zone2, "grass")

	# Combine zones
	var all_valid := valid_zone1 + valid_zone2
	all_valid.shuffle()

	# Place up to tree_count trees
	var placed := 0
	for tile_pos in all_valid:
		if placed >= tree_count:
			break
		var world_pos: Vector2 = ground_layer.map_to_local(tile_pos)
		if _is_too_close(world_pos, 96.0):
			continue
		var prop: Node2D = tree_scene.instantiate()
		prop.global_position = world_pos
		get_parent().add_child(prop)
		_placed_positions.append(world_pos)
		placed += 1


## Returns tiles from a given list whose tile_type matches the given string.
func _filter_to_type(tiles: Array[Vector2i], type: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords in tiles:
		var tile_data: TileData = ground_layer.get_cell_tile_data(coords)
		if tile_data == null:
			continue
		if tile_data.get_custom_data("tile_type") == type:
			result.append(coords)
	return result


## Returns all tiles on the GroundLayer whose tile_type matches any in the given list.
func _get_tiles_of_type(types: Array[String]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var used_rect: Rect2i = ground_layer.get_used_rect()
	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
		for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
			var coords := Vector2i(x, y)
			var tile_data: TileData = ground_layer.get_cell_tile_data(coords)
			if tile_data == null:
				continue
			if tile_data.get_custom_data("tile_type") in types:
				result.append(coords)
	return result


## Places a number of props randomly on valid tile positions, respecting minimum distance.
func _scatter_props(scene: PackedScene, valid_tiles: Array[Vector2i], count: int, min_distance: float) -> void:
	if scene == null or valid_tiles.is_empty():
		return
	var shuffled := valid_tiles.duplicate()
	shuffled.shuffle()
	var placed := 0
	for tile_pos in shuffled:
		if placed >= count:
			break
		var world_pos: Vector2 = ground_layer.map_to_local(tile_pos)
		if _is_too_close(world_pos, min_distance):
			continue
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


## Returns true if pos is within min_distance of any already-placed prop.
func _is_too_close(pos: Vector2, min_distance: float) -> bool:
	for placed_pos in _placed_positions:
		if pos.distance_to(placed_pos) < min_distance:
			return true
	return false
