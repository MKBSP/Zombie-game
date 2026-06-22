extends Control

## Client-side aim cursor for the human player. Draws a circle at the mouse whose
## radius = shooter.aim_spread_coeff * (gun->cursor distance), with opacity from
## the equipped weapon's range falloff. Green while the focus buff is shrinking it.
## Hides the OS cursor while active.

var _shooter: Node2D = null


func setup(shooter: Node2D) -> void:
	_shooter = shooter
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	set_process(true)


func teardown() -> void:
	_shooter = null
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(false)


func is_active() -> bool:
	return _shooter != null and is_instance_valid(_shooter)


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()


func _draw() -> void:
	if not is_active():
		return
	var gun: Vector2 = _shooter.global_position
	var tip := _shooter.get_node_or_null("GunTip")
	if tip:
		gun = tip.global_position
	var mouse := get_global_mouse_position()
	var dist := gun.distance_to(mouse)
	var coeff: float = _shooter.aim_spread_coeff
	var radius: float = maxf(coeff * dist, 2.0)

	var w := Weapons.get_data(_shooter.equipped)
	var opacity: float = clampf(AimModel.damage_mult(w, dist), 0.15, 1.0)

	# White normally; green when focus has shrunk the circle below aim_base.
	var col := Color(1, 1, 1, opacity)
	if coeff < w.aim_base - 0.0001:
		col = Color(0.3, 1.0, 0.3, opacity)

	var center := get_local_mouse_position()
	draw_arc(center, radius, 0.0, TAU, 48, col, 2.0)
	draw_circle(center, 2.0, col)
