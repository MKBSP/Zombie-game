extends Node2D

func _draw() -> void:
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color.GREEN, 2.0)
	draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 16, Color.GREEN, 1.0)
