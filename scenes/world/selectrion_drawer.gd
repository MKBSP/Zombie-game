extends Control

## Draws the drag-selection rectangle for the Zombie Controller.

# Set by the ZombieController script each frame
var draw_rect_active: bool = false
var draw_rect_start: Vector2 = Vector2.ZERO
var draw_rect_end: Vector2 = Vector2.ZERO


func _draw() -> void:
	if not draw_rect_active:
		return

	var top_left := Vector2(
		minf(draw_rect_start.x, draw_rect_end.x),
		minf(draw_rect_start.y, draw_rect_end.y)
	)
	var size := Vector2(
		absf(draw_rect_end.x - draw_rect_start.x),
		absf(draw_rect_end.y - draw_rect_start.y)
	)
	var rect := Rect2(top_left, size)

	# Semi-transparent green fill
	draw_rect(rect, Color(0.0, 1.0, 0.0, 0.25), true)
	# Green border
	draw_rect(rect, Color.GREEN, false, 2.0)


func _process(_delta: float) -> void:
	queue_redraw()
