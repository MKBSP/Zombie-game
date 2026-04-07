extends Node
class_name FogShooter

## Calculates tile-level visibility for the Shooter's flashlight fog of war.
## Call update_visibility() every frame with the shooter's tile position and facing angle.
## Read the result from the `visibility_image` property.

# Tile grid dimensions (must match your map)
const GRID_W: int = 47
const GRID_H: int = 47

# Flashlight settings
const CONE_DEPTH: int = 5        # tiles forward
const CONE_HALF_WIDTH: float = 1.5  # tiles at far end (3 wide / 2)
const DIM_RADIUS: int = 1        # tiles around shooter

# Visibility values written into the image (red channel)
const VIS_FOG: float = 0.0       # fully hidden
const VIS_DIM: float = 0.5       # dim radius — 50% visible
const VIS_FULL: float = 1.0      # flashlight — fully visible

# The output image: 47x47, one pixel per tile. Red channel = visibility.
var visibility_image: Image

# References
var ground_layer: TileMapLayer
var building_layer: TileMapLayer

# Cache: set of Vector2i positions that are occluders (buildings, edge tiles)
var _occluder_tiles: Dictionary = {}  # Vector2i -> bool

# Cache: set of Vector2i positions where props sit (cars, trees, dumpsters, statue — NOT fences)
var _occluder_prop_tiles: Dictionary = {}  # Vector2i -> bool


func _ready() -> void:
	visibility_image = Image.create(GRID_W, GRID_H, false, Image.FORMAT_RGBA8)


## Call once after the world has loaded to cache which tiles block light.
func cache_occluders() -> void:
	_occluder_tiles.clear()
	if ground_layer == null:
		return

	# Cache building and edge tiles from both layers
	for layer in [ground_layer, building_layer]:
		if layer == null:
			continue
		var used_rect: Rect2i = layer.get_used_rect()
		for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
			for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
				var coords := Vector2i(x, y)
				var td: TileData = layer.get_cell_tile_data(coords)
				if td == null:
					continue
				var tile_type: String = td.get_custom_data("tile_type")
				if tile_type == "building" or tile_type == "edge":
					_occluder_tiles[coords] = true


## Call once after props have been scattered to cache their tile positions.
## Pass in all prop nodes that block the flashlight (NOT fences).
func cache_prop_occluders(props: Array[Node2D]) -> void:
	_occluder_prop_tiles.clear()
	if ground_layer == null:
		return
	for prop in props:
		var tile_pos: Vector2i = ground_layer.local_to_map(
			ground_layer.to_local(prop.global_position)
		)
		_occluder_prop_tiles[tile_pos] = true


## Returns true if the given tile coordinate blocks the flashlight.
func _is_occluder(tile: Vector2i) -> bool:
	return _occluder_tiles.has(tile) or _occluder_prop_tiles.has(tile)


## Main function: recalculate the entire visibility image.
## shooter_tile: the tile coordinates the shooter is standing on.
## facing_angle: the shooter's facing direction in radians (from global_rotation).
func update_visibility(shooter_tile: Vector2i, facing_angle: float) -> void:
	# Clear to full fog
	visibility_image.fill(Color(0.0, 0.0, 0.0, 1.0))

	# --- Dim radius: 3x3 around shooter ---
	for dx in range(-DIM_RADIUS, DIM_RADIUS + 1):
		for dy in range(-DIM_RADIUS, DIM_RADIUS + 1):
			var t := shooter_tile + Vector2i(dx, dy)
			if t.x >= 0 and t.x < GRID_W and t.y >= 0 and t.y < GRID_H:
				visibility_image.set_pixel(t.x, t.y, Color(VIS_DIM, 0.0, 0.0, 1.0))

	# --- Flashlight cone ---
	# The cone is a triangle: starts 1 tile wide at shooter, expands to 3 tiles wide at depth 5.
	# We iterate row-by-row along the facing direction.
	var dir := Vector2.from_angle(facing_angle)
	var perp := Vector2(-dir.y, dir.x)  # perpendicular to facing direction

	for depth in range(1, CONE_DEPTH + 1):
		# Width at this depth: linearly interpolate from 0.5 at depth 1 to 1.5 at depth 5
		var half_w: float = 0.5 + (CONE_HALF_WIDTH - 0.5) * float(depth - 1) / float(CONE_DEPTH - 1)

		# Sample across the width at this depth
		# Use enough samples to not miss tiles
		var sample_count: int = int(ceil(half_w * 2.0)) + 1
		for s in range(sample_count):
			var offset: float = -half_w + (half_w * 2.0) * float(s) / float(max(sample_count - 1, 1))
			var world_offset: Vector2 = dir * float(depth) + perp * offset
			var target_tile := shooter_tile + Vector2i(roundi(world_offset.x), roundi(world_offset.y))

			# Bounds check
			if target_tile.x < 0 or target_tile.x >= GRID_W:
				continue
			if target_tile.y < 0 or target_tile.y >= GRID_H:
				continue

			# Ray from shooter to target — check for occluders
			if _ray_clear(shooter_tile, target_tile):
				visibility_image.set_pixel(
					target_tile.x, target_tile.y,
					Color(VIS_FULL, 0.0, 0.0, 1.0)
				)

	# The shooter's own tile is always fully visible
	if shooter_tile.x >= 0 and shooter_tile.x < GRID_W and shooter_tile.y >= 0 and shooter_tile.y < GRID_H:
		visibility_image.set_pixel(
			shooter_tile.x, shooter_tile.y,
			Color(VIS_FULL, 0.0, 0.0, 1.0)
		)


## Bresenham line from origin to target. Returns true if no occluder blocks the path.
## The origin tile is excluded from the check (the shooter's tile).
## The target tile itself is NOT checked — only tiles between origin and target.
func _ray_clear(origin: Vector2i, target: Vector2i) -> bool:
	var x0: int = origin.x
	var y0: int = origin.y
	var x1: int = target.x
	var y1: int = target.y

	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	var cx: int = x0
	var cy: int = y0

	while true:
		# Move one step
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy

		# Did we reach the target?
		if cx == x1 and cy == y1:
			break

		# Check if this intermediate tile is an occluder
		if _is_occluder(Vector2i(cx, cy)):
			return false

	return true
