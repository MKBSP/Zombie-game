class_name RoughFillStyleBox
extends StyleBox
## Jagged-leading-edge progress-bar fill — GDScript port of the mockup's
## <RoughBar>. Godot gives a "fill" StyleBox only the currently-filled
## sub-rect (already sized to the bar's value), so a triangular notch on
## the right edge reproduces the mockup's lumpy fill silhouette.

var bg_color: Color = Color.WHITE

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var w := rect.size.x
	var h := rect.size.y
	var jag := minf(h * 0.6, 4.0)
	var p := rect.position
	var points := PackedVector2Array([
		p,
		p + Vector2(w, 0),
		p + Vector2(w + jag, h * 0.5),
		p + Vector2(w, h),
		p + Vector2(0, h),
	])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([bg_color]))
	# Leading-edge highlight sliver, matching the mockup's white glint.
	var hi := PackedVector2Array([p + Vector2(w - 1.0, 0), p + Vector2(w, 0),
		p + Vector2(w, h), p + Vector2(w - 1.0, h)])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, hi, PackedColorArray([Color(1, 1, 1, 0.12)]))
