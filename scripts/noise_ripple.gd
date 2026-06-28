extends Node2D

## A brief, subtle world-space ripple at a gunshot, shown only when the zombie
## camera is near the shot. Self-removes after AGGRO.ripple_seconds.

var _age := 0.0

func _process(delta: float) -> void:
	_age += delta
	if _age > Balance.AGGRO.ripple_seconds:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var frac := _age / Balance.AGGRO.ripple_seconds
	var r := frac * Balance.AGGRO.ripple_radius
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(1, 1, 1, (1.0 - frac) * 0.18), 2.0)
