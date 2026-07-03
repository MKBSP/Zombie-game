extends Node2D

## Expanding command marker (right-click move / rally). Self-animates then frees.
var color: Color = Color.GREEN
var max_radius: float = 48.0
var duration: float = 0.8
var _age: float = 0.0

func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var t: float = _age / duration
	var a: float = 1.0 - t
	draw_arc(Vector2.ZERO, max_radius * t, 0.0, TAU, 40, Color(color, a), 3.0)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 20, Color(color, a), 2.0)
	draw_line(Vector2(-14, 0), Vector2(14, 0), Color(color, a), 2.0)
	draw_line(Vector2(0, -14), Vector2(0, 14), Color(color, a), 2.0)
