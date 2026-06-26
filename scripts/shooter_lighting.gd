extends Node
class_name ShooterLighting

## Stateless helpers that build the shooter's 2D-light fog of war:
## generated cone / halo textures, occluder polygons, and the assembly of
## CanvasModulate + lights + static occluders for the HUMAN role.


## Hard-edged cone light texture. Apex at the texture center, opening toward
## local +X (the shooter's forward/aim direction). Alpha is a crisp 0/255 edge.
static func make_cone_texture(tex_size: int, half_angle_rad: float) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := float(tex_size) / 2.0
	var radius := float(tex_size) / 2.0
	for y in range(tex_size):
		for x in range(tex_size):
			var dx := float(x) + 0.5 - center
			var dy := float(y) + 0.5 - center
			var dist := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)  # 0 = +X (forward)
			var lit: bool = dist <= radius and absf(ang) <= half_angle_rad
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if lit else 0.0))
	return ImageTexture.create_from_image(img)


## Soft radial light texture: alpha 1 at the center, linearly to 0 at the edge.
static func make_radial_texture(tex_size: int) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := float(tex_size) / 2.0
	var radius := float(tex_size) / 2.0
	for y in range(tex_size):
		for x in range(tex_size):
			var dx := float(x) + 0.5 - center
			var dy := float(y) + 0.5 - center
			var dist := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - dist / radius, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## A closed square occluder polygon, size x size, centered on the origin.
static func make_square_occluder_polygon(size: float) -> OccluderPolygon2D:
	var half := size / 2.0
	var poly := OccluderPolygon2D.new()
	poly.closed = true
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	return poly


## World-space centers of every tile that blocks the flashlight (buildings and
## map-edge tiles on either layer) plus every prop. Mirrors the old FogShooter
## occluder detection.
static func collect_static_occluder_positions(
	ground_layer: TileMapLayer,
	building_layer: TileMapLayer,
	props: Array[Node2D]
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if ground_layer == null:
		return out
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
					out.append(layer.to_global(layer.map_to_local(coords)))
	for prop in props:
		out.append(prop.global_position)
	return out


## Spawn one square LightOccluder2D per position under `parent`. Returns count.
static func build_static_occluders(parent: Node, positions: Array[Vector2], tile_size: float) -> int:
	var poly := make_square_occluder_polygon(tile_size)
	for pos in positions:
		var occ := LightOccluder2D.new()
		occ.occluder = poly
		parent.add_child(occ)
		occ.global_position = pos
	return positions.size()


## Build the full shooter fog: dark CanvasModulate over the world, a cone
## flashlight + radial halo parented to the shooter, and static occluders.
## Call once, on the HUMAN-role instance only.
static func setup(
	world: Node2D,
	shooter: Node2D,
	ground_layer: TileMapLayer,
	building_layer: TileMapLayer,
	props: Array[Node2D]
) -> void:
	var b: Dictionary = Balance.FOG_SHOOTER

	# 1. Darken the world (the "fog"). HUD is on its own CanvasLayer -> stays bright.
	var modulate := CanvasModulate.new()
	modulate.color = b.ambient_darkness
	world.add_child(modulate)

	# 2. Flashlight cone — child of the shooter so it tracks position + aim.
	var cone := PointLight2D.new()
	cone.texture = make_cone_texture(b.cone_tex_size, deg_to_rad(b.flashlight_half_angle_deg))
	cone.texture_scale = b.flashlight_range / (float(b.cone_tex_size) / 2.0)
	cone.energy = b.flashlight_energy
	cone.color = b.flashlight_color
	cone.shadow_enabled = b.shadows_enabled
	shooter.add_child(cone)

	# 3. Personal halo — small soft radial light, no aim dependence.
	var halo := PointLight2D.new()
	halo.texture = make_radial_texture(b.halo_tex_size)
	halo.texture_scale = b.halo_radius / (float(b.halo_tex_size) / 2.0)
	halo.energy = b.halo_energy
	halo.color = b.halo_color
	halo.shadow_enabled = b.shadows_enabled
	shooter.add_child(halo)

	# 4. Static occluders (buildings, edges, props).
	var tile_size: float = ground_layer.tile_set.tile_size.x
	var positions := collect_static_occluder_positions(ground_layer, building_layer, props)
	build_static_occluders(world, positions, tile_size)
