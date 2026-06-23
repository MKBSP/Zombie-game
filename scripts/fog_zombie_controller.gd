extends Node
class_name FogZombieController

## Calculates tile-level visibility for the Zombie Controller's AoE2-style fog.
## Each tile has three states:
##   0 = unexplored (never seen)
##   1 = previously explored (was seen, no zombie watching now)
##   2 = currently visible (a zombie can see it right now)
##
## Call update_visibility() every frame with the list of all zombie positions and their vision ranges.
## Read the result from the `visibility_image` property.

# Grid dims + visibility levels come from Balance.FOG_ZC (assigned in _ready).
var GRID_W: int
var GRID_H: int

# Tile states (structural)
const STATE_UNEXPLORED: int = 0
const STATE_EXPLORED: int = 1
const STATE_VISIBLE: int = 2

# The persistent exploration map: once explored, stays explored (value 1 or 2)
var tile_states: Array[int] = []

# The output image: 47x47, red channel encodes visibility for the shader
var visibility_image: Image

# Visibility values for the shader (from Balance.FOG_ZC)
var VIS_UNEXPLORED: float   # fully black
var VIS_EXPLORED: float     # dimmed — terrain visible, no moving entities
var VIS_VISIBLE: float      # fully visible


func _ready() -> void:
	var b: Dictionary = Balance.FOG_ZC
	GRID_W = b.grid_w
	GRID_H = b.grid_h
	VIS_UNEXPLORED = b.vis_unexplored
	VIS_EXPLORED = b.vis_explored
	VIS_VISIBLE = b.vis_visible
	visibility_image = Image.create(GRID_W, GRID_H, false, Image.FORMAT_RGBA8)
	# Initialize all tiles as unexplored
	tile_states.resize(GRID_W * GRID_H)
	tile_states.fill(STATE_UNEXPLORED)


## Main function: recalculate visibility based on all zombie positions.
## zombies_data: Array of Dictionaries, each with:
##   "tile": Vector2i — the zombie's current tile
##   "vision": int — vision range in tiles (Manhattan distance)
func update_visibility(zombies_data: Array[Dictionary]) -> void:
	# Step 1: Downgrade all "currently visible" tiles to "previously explored"
	for i in range(tile_states.size()):
		if tile_states[i] == STATE_VISIBLE:
			tile_states[i] = STATE_EXPLORED

	# Step 2: For each zombie, mark tiles within vision range as visible
	for zdata in zombies_data:
		var ztile: Vector2i = zdata["tile"]
		var vision: int = zdata["vision"]
		_reveal_diamond(ztile, vision)

	# Step 3: Write tile states into the image
	for x in range(GRID_W):
		for y in range(GRID_H):
			var state: int = tile_states[y * GRID_W + x]
			var vis: float
			match state:
				STATE_UNEXPLORED:
					vis = VIS_UNEXPLORED
				STATE_EXPLORED:
					vis = VIS_EXPLORED
				STATE_VISIBLE:
					vis = VIS_VISIBLE
				_:
					vis = VIS_UNEXPLORED
			visibility_image.set_pixel(x, y, Color(vis, 0.0, 0.0, 1.0))


## Marks all tiles within Manhattan distance of center as currently visible.
func _reveal_diamond(center: Vector2i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if absi(dx) + absi(dy) <= radius:
				var t := center + Vector2i(dx, dy)
				if t.x >= 0 and t.x < GRID_W and t.y >= 0 and t.y < GRID_H:
					tile_states[t.y * GRID_W + t.x] = STATE_VISIBLE
