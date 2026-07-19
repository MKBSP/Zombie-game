extends StaticBody2D
## Runtime-built light occluders for props (tree, car, dumpster, statue,
## fence). The footprint comes from the ColorRect visual, inset so the prop
## itself stays lit. Fences build striped segments with gaps instead, so the
## flashlight shines through with a picket-pattern shadow behind.
## occluder_light_mask = 3: casts for the shooter flashlight (layer 1) and
## the zombie-commander vision lights (layer 2) — hiding behind a prop works
## against both fogs. Tunables in Balance.PROP_OCCLUDER.


func _ready() -> void:
	var rect := get_node_or_null("ColorRect") as ColorRect
	if rect == null:
		return
	var b: Dictionary = Balance.PROP_OCCLUDER
	var tl := Vector2(rect.offset_left, rect.offset_top)
	var br := Vector2(rect.offset_right, rect.offset_bottom)
	if "Fence" in String(name):
		_build_fence_segments(tl, br, b)
	else:
		var inset: float = 1.0 - b.inset_frac
		_add_occluder(_rect_poly(tl * inset, br * inset))


func _rect_poly(tl: Vector2, br: Vector2) -> PackedVector2Array:
	return PackedVector2Array([tl, Vector2(br.x, tl.y), br, Vector2(tl.x, br.y)])


func _add_occluder(points: PackedVector2Array) -> void:
	var poly := OccluderPolygon2D.new()
	poly.closed = true
	poly.polygon = points
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	occ.occluder_light_mask = 3
	add_child(occ)


## Striped segments along the fence's long axis: solid picket, gap, picket…
## Light bleeds through the gaps, casting the chain-link shadow style.
func _build_fence_segments(tl: Vector2, br: Vector2, b: Dictionary) -> void:
	var half_t: float = b.fence_thickness_px / 2.0
	var x: float = tl.x
	while x < br.x:
		var x2: float = minf(x + b.fence_segment_px, br.x)
		_add_occluder(_rect_poly(Vector2(x, -half_t), Vector2(x2, half_t)))
		x = x2 + b.fence_gap_px
