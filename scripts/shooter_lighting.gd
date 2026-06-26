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
