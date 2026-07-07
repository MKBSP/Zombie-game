extends RefCounted
class_name DecalMath

## Pure mapping from world space to a canvas Image pixel. Kept separate from the
## canvas node so it can be unit-tested without a live tree.
static func world_to_image(world_pos: Vector2, world_origin: Vector2, world_size_px: Vector2, img_size: Vector2i) -> Vector2i:
	var fx := (world_pos.x - world_origin.x) / world_size_px.x
	var fy := (world_pos.y - world_origin.y) / world_size_px.y
	var px := int(fx * img_size.x)
	var py := int(fy * img_size.y)
	px = clampi(px, 0, img_size.x - 1)
	py = clampi(py, 0, img_size.y - 1)
	return Vector2i(px, py)
