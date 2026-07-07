extends CPUParticles2D

## One-shot particle burst reused for red blood, green blood, and sparks. The
## caller sets position, then calls play(preset, dir). Self-frees when done.

func _ready() -> void:
	emitting = false
	one_shot = true
	explosiveness = 1.0
	finished.connect(queue_free)

func play(preset: int, dir: Vector2) -> void:
	var c: Dictionary = FxPresets.config(preset)
	amount = c.amount
	lifetime = c.lifetime
	color = c.color
	spread = c.spread_deg
	initial_velocity_min = c.vel_min
	initial_velocity_max = c.vel_max
	scale_amount_min = c.scale_min
	scale_amount_max = c.scale_max
	gravity = Vector2(0, c.gravity)
	direction = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	restart()
	emitting = true
