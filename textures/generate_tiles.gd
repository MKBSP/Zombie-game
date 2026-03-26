@tool
extends EditorScript

## Run this script from the editor: Script menu > Run (Ctrl+Shift+X)
## It generates a placeholder tileset PNG at res://textures/placeholder_tiles.png

func _run() -> void:
	# Define tile colors — each becomes one 64x64 tile in the spritesheet
	var tiles: Array[Dictionary] = [
		{"name": "road",     "color": Color("#3a3a3a")},  # tile 0
		{"name": "sidewalk", "color": Color("#7a7a7a")},  # tile 1
		{"name": "grass",    "color": Color("#2d5a1e")},  # tile 2
		{"name": "building", "color": Color("#6b4226")},  # tile 3
		{"name": "parking",  "color": Color("#555555")},  # tile 4
		{"name": "edge",     "color": Color("#000000")},  # tile 5
	]

	var tile_size := 64
	var image_width := tile_size * tiles.size()
	var image_height := tile_size

	# Create a new image
	var img := Image.create(image_width, image_height, false, Image.FORMAT_RGBA8)

	# Fill each tile region with its color
	for i in range(tiles.size()):
		var col: Color = tiles[i]["color"]
		var x_start := i * tile_size
		for x in range(x_start, x_start + tile_size):
			for y in range(0, tile_size):
				img.set_pixel(x, y, col)

		# Draw a subtle 1px border on each tile so you can see the grid
		for x in range(x_start, x_start + tile_size):
			img.set_pixel(x, 0, col.darkened(0.3))
			img.set_pixel(x, tile_size - 1, col.darkened(0.3))
		for y in range(0, tile_size):
			img.set_pixel(x_start, y, col.darkened(0.3))
			img.set_pixel(x_start + tile_size - 1, y, col.darkened(0.3))

	# Save the image
	var err := img.save_png("res://textures/placeholder_tiles.png")
	if err == OK:
		print("Tile texture saved to res://textures/placeholder_tiles.png")
	else:
		print("ERROR: Could not save tile texture. Error code: ", err)
