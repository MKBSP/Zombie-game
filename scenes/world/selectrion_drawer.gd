extends Control

## Draws the drag-selection rectangle for the Zombie Controller.

# Set by the ZombieController script each frame
var draw_rect_active: bool = false
var draw_rect_start: Vector2 = Vector2.ZERO
var draw_rect_end: Vector2 = Vector2.ZERO

# Set once by the ZombieController so we can read the current selection's stances.
var controller: Node = null


func _draw() -> void:
	if draw_rect_active:
		var top_left := Vector2(
			minf(draw_rect_start.x, draw_rect_end.x),
			minf(draw_rect_start.y, draw_rect_end.y)
		)
		var box_size := Vector2(
			absf(draw_rect_end.x - draw_rect_start.x),
			absf(draw_rect_end.y - draw_rect_start.y)
		)
		var rect := Rect2(top_left, box_size)
		draw_rect(rect, Color(0.0, 1.0, 0.0, 0.25), true)
		draw_rect(rect, Color.GREEN, false, 2.0)

	_draw_stance_preview()


## Patrol lines / flee markers for the currently-selected zombies.
func _draw_stance_preview() -> void:
	if controller == null:
		return
	var xform := get_viewport().get_canvas_transform()
	for z in controller.selected_zombies:
		if not is_instance_valid(z) or not ("movement_mode" in z):
			continue  # e.g. the master zombie has no movement mode
		var mv: int = z.movement_mode
		if mv == 2:  # PATROL
			var a: Vector2 = xform * z.patrol_a
			var b: Vector2 = xform * z.patrol_b
			draw_line(a, b, Color(1, 1, 0, 0.5), 2.0)
			draw_circle(a, 5.0, Color.YELLOW)
			draw_circle(b, 5.0, Color.YELLOW)
		elif mv == 1:  # FLEE
			var fp: Vector2 = xform * z.flee_point
			draw_circle(fp, 6.0, Color(0.4, 0.7, 1.0, 0.7))


func _process(_delta: float) -> void:
	queue_redraw()
