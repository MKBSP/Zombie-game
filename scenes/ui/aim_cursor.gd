extends Control

## Client-side aim cursor for the human player. Draws a circle at the mouse whose
## radius = shooter.aim_spread_coeff * (gun->cursor distance), with opacity from
## the equipped weapon's range falloff. Green while the focus buff is shrinking it.
## Hides the OS cursor while active.

## Faintest the ring ever gets, when the cursor is at/over the weapon's
## zero-range. It never fully disappears so the player can still aim far.
# Faintest the ring ever gets lives in Balance.AIM.min_opacity.

var _shooter: Node2D = null
var _gun_tip: Node2D = null


func setup(shooter: Node2D) -> void:
	_shooter = shooter
	_gun_tip = shooter.get_node_or_null("GunTip")
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	set_process(true)


func teardown() -> void:
	_shooter = null
	_gun_tip = null
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
	var gun: Vector2 = _gun_tip.global_position if (_gun_tip and is_instance_valid(_gun_tip)) else _shooter.global_position
	# Measure in WORLD space. The shooter's mouse position is world-space, while
	# this Control lives on a CanvasLayer (screen space) — mixing the two is what
	# pinned the old distance near-constant. This is the same gun->cursor distance
	# the server fires with, so the ring now matches the real bullet spread.
	var world_mouse := _shooter.get_global_mouse_position()
	var dist := gun.distance_to(world_mouse)
	var coeff: float = _shooter.aim_spread_coeff
	# World px -> screen px. Shooter camera is zoom 1.0 today; scaling by the zoom
	# keeps the drawn ring correct if that ever changes.
	var cam := _shooter.get_node_or_null("Camera2D") as Camera2D
	var zoom: float = cam.zoom.x if cam else 1.0
	var radius: float = maxf(coeff * dist * zoom, 2.0)

	var w := Weapons.get_data(_shooter.equipped)
	# Range falloff: full strength within optimal range, dimming toward MIN_OPACITY
	# as the cursor passes the weapon's zero-range. The ring never vanishes — past
	# optimal range it turns dashed and faint so the player can still aim far.
	var range_factor: float = clampf(AimModel.damage_mult(w, dist), 0.0, 1.0)
	var opacity: float = lerpf(Balance.AIM.min_opacity, 1.0, range_factor)
	var in_range: bool = dist <= w.optimal_range_px

	# White normally; green when focus has shrunk the circle below aim_base.
	var col := Color(1, 1, 1, opacity)
	if coeff < w.aim_base - 0.0001:
		col = Color(0.3, 1.0, 0.3, opacity)

	var center := get_local_mouse_position()
	if in_range:
		draw_arc(center, radius, 0.0, TAU, 48, col, 2.0)
	else:
		_draw_dashed_ring(center, radius, col)
	draw_circle(center, 2.0, col)


## Dotted ring (every other arc segment) — flags an out-of-optimal-range shot.
func _draw_dashed_ring(center: Vector2, radius: float, col: Color) -> void:
	var segments := 40
	var step := TAU / segments
	for i in range(0, segments, 2):
		var a0: float = i * step
		draw_arc(center, radius, a0, a0 + step, 4, col, 2.0)
