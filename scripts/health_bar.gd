extends Node2D
class_name HealthBar

## Small health bar drawn above a unit. Stays upright even though the parent
## rotates to face its travel direction. Driven by set_fraction().

const WIDTH := 26.0
const HEIGHT := 4.0
var fraction: float = 1.0

func set_fraction(f: float) -> void:
	fraction = clampf(f, 0.0, 1.0)
	queue_redraw()

func _process(_delta: float) -> void:
	# Stay horizontal even though the parent rotates.
	global_rotation = 0.0

func _draw() -> void:
	var origin := Vector2(-WIDTH * 0.5, 0.0)
	draw_rect(Rect2(origin, Vector2(WIDTH, HEIGHT)), Color(0, 0, 0, 0.6))
	var col := Color(0.2, 0.9, 0.2).lerp(Color(0.9, 0.2, 0.2), 1.0 - fraction)
	draw_rect(Rect2(origin, Vector2(WIDTH * fraction, HEIGHT)), col)
