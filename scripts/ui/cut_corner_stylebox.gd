class_name CutCornerStyleBox
extends StyleBox
## Octagonal "cut corner" panel background — GDScript port of the mockup's
## `clip-path: polygon(...)` panels (CUT_SM/CUT_MD in App.tsx). Godot's
## StyleBoxFlat only supports rounded corners, not angled cuts, so this
## draws the octagon directly via the low-level CanvasItem polygon API.

var bg_color: Color = Color.BLACK
var border_color: Color = Color.TRANSPARENT
var border_width: float = 1.0
var cut: float = 5.0
## StyleBox (unlike StyleBoxFlat) has no shadow_color/shadow_size — this is
## our own simple glow: a second, larger octagon drawn behind the main one.
var glow_color: Color = Color.TRANSPARENT
var glow_size: float = 0.0

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var c: float = minf(cut, minf(rect.size.x, rect.size.y) * 0.5)
	var p := rect.position
	var s := rect.size
	if glow_size > 0.0 and glow_color.a > 0.0:
		var gp := p - Vector2(glow_size, glow_size)
		var gs := s + Vector2(glow_size, glow_size) * 2.0
		var gc: float = minf(c + glow_size, minf(gs.x, gs.y) * 0.5)
		var glow_points := PackedVector2Array([
			gp + Vector2(gc, 0),           gp + Vector2(gs.x - gc, 0),
			gp + Vector2(gs.x, gc),        gp + Vector2(gs.x, gs.y - gc),
			gp + Vector2(gs.x - gc, gs.y), gp + Vector2(gc, gs.y),
			gp + Vector2(0, gs.y - gc),    gp + Vector2(0, gc),
		])
		RenderingServer.canvas_item_add_polygon(to_canvas_item, glow_points, PackedColorArray([glow_color]))
	var points := PackedVector2Array([
		p + Vector2(c, 0),         p + Vector2(s.x - c, 0),
		p + Vector2(s.x, c),       p + Vector2(s.x, s.y - c),
		p + Vector2(s.x - c, s.y), p + Vector2(c, s.y),
		p + Vector2(0, s.y - c),   p + Vector2(0, c),
	])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([bg_color]))
	if border_width > 0.0 and border_color.a > 0.0:
		var loop := points.duplicate()
		loop.append(points[0])
		RenderingServer.canvas_item_add_polyline(
			to_canvas_item, loop, PackedColorArray([border_color]), border_width, true)

func _get_minimum_size() -> Vector2:
	return Vector2(cut * 2.0, cut * 2.0)
