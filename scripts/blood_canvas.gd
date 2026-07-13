extends Sprite2D
class_name BloodCanvas

## One world-sized Image/ImageTexture that accumulates permanent blood drops.
## Same baked-texture technique as fog_zombie_controller. One draw call total.

var _image: Image
var _tex: ImageTexture
var _world_origin: Vector2
var _world_size_px: Vector2
var _img_size: Vector2i

## world_origin/world_size_px describe the ground bounds in world space.
func setup(world_origin: Vector2, world_size_px: Vector2) -> void:
	_world_origin = world_origin
	_world_size_px = world_size_px
	var ds: int = max(1, int(Balance.FX.canvas_downscale))
	# Integer division intended: image dimensions are whole pixels.
	@warning_ignore("integer_division")
	_img_size = Vector2i(int(world_size_px.x) / ds, int(world_size_px.y) / ds)
	_image = Image.create(_img_size.x, _img_size.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_image)
	texture = _tex
	centered = false
	global_position = _world_origin
	# Stretch the (possibly downscaled) texture back over the full world.
	scale = Vector2(_world_size_px.x / _img_size.x, _world_size_px.y / _img_size.y)

func stamp(world_pos: Vector2) -> void:
	if _image == null:
		return
	var center := DecalMath.world_to_image(world_pos, _world_origin, _world_size_px, _img_size)
	var r: int = maxi(1, int(Balance.FX.bleed_drop_radius_px / maxi(1, int(Balance.FX.canvas_downscale))))
	var col: Color = Balance.FX.bleed_color
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var px := center.x + dx
			var py := center.y + dy
			if px < 0 or py < 0 or px >= _img_size.x or py >= _img_size.y:
				continue
			_image.set_pixel(px, py, col)
	_tex.update(_image)
