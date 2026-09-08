extends Node3D
## Parameterised camera rig — Brief 11, 3D camera test.
##
## Four view models share this one script so a fix lands in all of them; each
## test scene only sets `view_mode` and its own numbers.
##
##   TOP_DOWN_CURSOR  V1. Camera straight DOWN, rig yaw locked to the street,
##                    absolute world-space cursor. RMB swings to
##                    over-the-shoulder. The brief's original geometry test.
##   OVER_SHOULDER    V2. GTA5/RE4 third person — over the shoulder always,
##                    relative mouse always. RMB pulls closer and narrows.
##   TOP_DOWN_ROTATE  V3. "Hostile Process": still straight down, but the rig
##                    yaw IS the mouse — you aim by rotating the world, and the
##                    character stays locked facing up-screen. RMB leans in by
##                    dropping the camera rather than tilting it.
##   FIRST_PERSON     V4. Camera at eye height. RMB is iron sights.
##
## In the top-down modes, never add pitch to the hip pose. The lean-in that
## fills the frame with facade comes from a wide FOV throwing off-axis geometry
## outward, not from tilting the camera.
##
## Every parameter is re-read each frame so remote-inspector edits take effect
## live while playing. Do not cache them in _ready().

enum ViewMode {
	TOP_DOWN_CURSOR,
	OVER_SHOULDER,
	TOP_DOWN_ROTATE,
	FIRST_PERSON,
}

## Dominant building height on the Copenhagen greybox (metres). The splay
## readout is quoted against this.
const REFERENCE_BUILDING_HEIGHT := 20.0

@export var view_mode: ViewMode = ViewMode.TOP_DOWN_CURSOR
@export var target_path: NodePath = ^"../TestPlayer"
@export var hud_label_path: NodePath = ^"../DebugHUD/Label"
## Exponential follow rate. 0 snaps to the player exactly.
@export_range(0.0, 30.0, 0.5) var follow_smoothing: float = 8.0
## Seconds for the full hip <-> aim transition.
@export_range(0.05, 2.0, 0.01) var aim_transition: float = 0.30

@export_group("Hip pose")
## Vertical FOV (keep_aspect stays KEEP_HEIGHT).
@export_range(30.0, 110.0, 0.5) var fov: float = 70.0
## Top-down modes: metres above the player.
@export_range(2.0, 80.0, 0.1) var height: float = 28.6
## Top-down modes: player position in frame. 0 = centred, positive = lower in
## frame with more ground ahead.
@export_range(-0.8, 0.8, 0.01) var player_screen_offset: float = 0.0
## TOP_DOWN_CURSOR only: rig rotation about world Y. The street at spawn runs at
## 95 deg from -Z, so -95 puts it vertically up the screen. Per-street, not
## global. Every other mode takes its yaw from the mouse.
@export_range(-180.0, 180.0, 1.0) var camera_yaw: float = -95.0
## FIRST_PERSON only: camera height above the player's feet.
@export_range(0.5, 2.5, 0.05) var eye_height: float = 1.65

@export_group("Over-the-shoulder pose")
## V1's RMB pose and V2's resting pose. Metres above the player's feet.
@export_range(0.5, 20.0, 0.1) var aim_height: float = 2.4
## Metres behind the player.
@export_range(0.0, 20.0, 0.1) var aim_distance: float = 4.5
## Metres to the right. Without this the character sits dead centre and blocks
## the thing you are aiming at.
@export_range(-3.0, 3.0, 0.05) var aim_shoulder: float = 0.8
## Resting pitch in this pose. Negative looks down; near 0 is the horizon.
@export_range(-89.0, 10.0, 1.0) var aim_pitch: float = -10.0

@export_group("Aim / RMB")
## FOV while RMB is held.
@export_range(20.0, 110.0, 0.5) var aim_fov: float = 55.0
## OVER_SHOULDER: how far behind the player the camera sits while aiming.
@export_range(0.0, 20.0, 0.1) var ads_distance: float = 2.6
## TOP_DOWN_ROTATE: metres the camera drops while aiming, to lean into the
## street instead of tilting.
@export_range(0.0, 30.0, 0.1) var ads_drop: float = 6.0

@export_group("Camera collision")
## Brief 6 defers camera collision, but a 4.5 m pullback inside a 10.8 m street
## puts the camera through a facade constantly — the shoulder modes are
## untestable without it. Straight-down poses are never affected.
@export var aim_camera_collision: bool = true
## Height of the point the camera pulls in toward — roughly the shoulder.
@export_range(0.0, 3.0, 0.05) var camera_pivot_height: float = 1.4
## Stand-off from whatever the camera pulls in against.
@export_range(0.0, 1.5, 0.05) var camera_collision_margin: float = 0.3

@onready var _camera: Camera3D = $Camera3D

var _target: Node3D = null
var _hud: Label = null
var _focus := Vector3.ZERO
var _blend := 0.0  # 0 = hip, 1 = aim
var _clearance := 1.0  # 1 = camera reaches its desired spot, <1 = pulled in


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_hud = get_node_or_null(hud_label_path) as Label
	if _target != null:
		_focus = _target.global_position
	_apply()


## True only where the player steers with an absolute world-space cursor. Every
## other mode captures the mouse and reads relative motion.
func uses_cursor() -> bool:
	return view_mode == ViewMode.TOP_DOWN_CURSOR


func is_first_person() -> bool:
	return view_mode == ViewMode.FIRST_PERSON


func _process(delta: float) -> void:
	if _target != null:
		var goal := _target.global_position
		if follow_smoothing <= 0.0:
			_focus = goal
		else:
			_focus = _focus.lerp(goal, 1.0 - exp(-follow_smoothing * delta))
		global_position = _focus

	var want := 1.0 if _is_aiming() else 0.0
	_blend = move_toward(_blend, want, delta / maxf(aim_transition, 0.01))

	_apply()
	_update_hud()


func _is_aiming() -> bool:
	return _target != null and _target.get("aiming") == true


## Eased 0..1 so the transition starts and settles softly.
func _t() -> float:
	return smoothstep(0.0, 1.0, _blend)


## Half the ground distance visible along the view axis: d = h * tan(fov / 2).
## Top-down geometry only — meaningless once the camera pitches up.
func _ground_half_extent() -> float:
	return height * tan(deg_to_rad(fov) * 0.5)


func _player_yaw() -> float:
	if _target == null:
		return deg_to_rad(camera_yaw)
	return _target.get("aim_yaw")


## Vertical aim from mouse Y, clamped. Only the forward-looking poses use it —
## applying it to a straight-down pose would break the whole premise.
func _pitch_offset() -> float:
	if _target == null:
		return 0.0
	return _target.get("aim_pitch_offset")


func _top_down_local(h: float) -> Vector3:
	return Vector3(0.0, h, -player_screen_offset * h * tan(deg_to_rad(fov) * 0.5))


func _shoulder_local(distance: float) -> Vector3:
	return Vector3(aim_shoulder, aim_height, distance)


func _hip_local() -> Vector3:
	match view_mode:
		ViewMode.OVER_SHOULDER:
			return _shoulder_local(aim_distance)
		ViewMode.FIRST_PERSON:
			return Vector3(0.0, eye_height, 0.0)
		_:
			return _top_down_local(height)


func _aim_local() -> Vector3:
	match view_mode:
		ViewMode.TOP_DOWN_CURSOR:
			return _shoulder_local(aim_distance)
		ViewMode.OVER_SHOULDER:
			return _shoulder_local(ads_distance)
		ViewMode.FIRST_PERSON:
			return Vector3(0.0, eye_height, 0.0)
		_:
			return _top_down_local(maxf(height - ads_drop, 2.0))


func _hip_pitch() -> float:
	match view_mode:
		ViewMode.OVER_SHOULDER:
			return clampf(aim_pitch + _pitch_offset(), -89.0, 30.0)
		ViewMode.FIRST_PERSON:
			return clampf(_pitch_offset(), -89.0, 60.0)
		_:
			return -90.0


func _aim_pitch_now() -> float:
	match view_mode:
		ViewMode.TOP_DOWN_CURSOR, ViewMode.OVER_SHOULDER:
			return clampf(aim_pitch + _pitch_offset(), -89.0, 30.0)
		ViewMode.FIRST_PERSON:
			return clampf(_pitch_offset(), -89.0, 60.0)
		_:
			return -90.0


## Where the camera wants to sit, in rig-local space, before collision.
func _desired_camera_local() -> Vector3:
	return _hip_local().lerp(_aim_local(), _t())


func _pivot_local() -> Vector3:
	return Vector3(0.0, camera_pivot_height, 0.0)


func _apply() -> void:
	var t := _t()

	# V1 holds the rig to the street until RMB swings it to the aim direction.
	# Every other mode is mouse-driven in both states, so this is a no-op there.
	var hip_yaw := deg_to_rad(camera_yaw) if uses_cursor() else _player_yaw()
	rotation = Vector3(0.0, lerp_angle(hip_yaw, _player_yaw(), t), 0.0)

	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = lerpf(fov, aim_fov, t)
	# Pulled in toward the shoulder pivot when something is in the way.
	_camera.position = _pivot_local().lerp(_desired_camera_local(), _clearance)
	_camera.rotation = Vector3(deg_to_rad(lerpf(_hip_pitch(), _aim_pitch_now(), t)), 0.0, 0.0)


## Physics queries belong on the physics tick, so the result is cached here and
## consumed by _apply() on the render tick.
func _physics_process(_delta: float) -> void:
	_clearance = 1.0
	if not aim_camera_collision or _target == null:
		return
	# A straight-down camera never needs this, and running it would only risk
	# yanking the geometry test's camera down a rooftop.
	if _hip_pitch() <= -89.5 and _aim_pitch_now() <= -89.5:
		return
	var pivot := global_transform * _pivot_local()
	var desired := global_transform * _desired_camera_local()
	var full := pivot.distance_to(desired)
	if full < 0.01:
		return
	var query := PhysicsRayQueryParameters3D.create(pivot, desired)
	query.exclude = [_target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var reachable := pivot.distance_to(hit.position) - camera_collision_margin
	_clearance = clampf(reachable / full, 0.0, 1.0)


func _mode_name() -> String:
	match view_mode:
		ViewMode.OVER_SHOULDER:
			return "V2 OVER-THE-SHOULDER"
		ViewMode.TOP_DOWN_ROTATE:
			return "V3 HOSTILE PROCESS"
		ViewMode.FIRST_PERSON:
			return "V4 FIRST PERSON"
		_:
			return "V1 TOP-DOWN + GTA5 AIM"


func _is_top_down() -> bool:
	return view_mode == ViewMode.TOP_DOWN_CURSOR or view_mode == ViewMode.TOP_DOWN_ROTATE


func _update_hud() -> void:
	if _hud == null:
		return

	var state := "HIP" if _blend < 0.5 else "AIM"
	if _blend > 0.0 and _blend < 1.0:
		state = "->AIM" if _is_aiming() else "->HIP"

	var lines := ["%s  [%s]   hold RMB to aim   (macOS: ctrl+click = RMB)" % [_mode_name(), state]]

	if _is_top_down():
		var d := _ground_half_extent()
		var aspect := 16.0 / 9.0
		var rect_size := get_viewport().get_visible_rect().size
		if rect_size.y > 0.0:
			aspect = rect_size.x / rect_size.y
		var offset_distance := player_screen_offset * d
		lines.append("FOV %.1f°  |  height %.1f m  |  yaw %.0f°  |  offset %.2f" % [
			fov, height, rad_to_deg(rotation.y), player_screen_offset,
		])
		lines.append("ground visible: %.1f m along axis, %.1f m across" % [d * 2.0, d * 2.0 * aspect])
		lines.append("ahead of player: %.1f m   behind: %.1f m" % [
			d + offset_distance, d - offset_distance,
		])
		if height <= REFERENCE_BUILDING_HEIGHT:
			lines.append("splay factor: N/A — camera at %.1f m is inside %.0f m buildings" % [
				height, REFERENCE_BUILDING_HEIGHT,
			])
		else:
			lines.append("splay factor (%.0f m building): %.2fx" % [
				REFERENCE_BUILDING_HEIGHT,
				height / (height - REFERENCE_BUILDING_HEIGHT),
			])
	else:
		lines.append("FOV %.1f°  |  pitch %.0f°  |  yaw %.0f°" % [
			_camera.fov, _camera.rotation_degrees.x, rad_to_deg(rotation.y),
		])
		if view_mode == ViewMode.FIRST_PERSON:
			lines.append("eye height: %.2f m" % eye_height)
		else:
			lines.append("camera: %.1f m up, %.1f m back, %.2f m shoulder  (clearance %.2f)" % [
				aim_height, _camera.position.z, aim_shoulder, _clearance,
			])

	if _target != null:
		var p := _target.global_position
		lines.append("player pos: (%.1f, %.1f)" % [p.x, p.z])

	if _is_top_down():
		lines.append("[1] 70°/28.6m   [2] 60°/34.6m   [3] 50°/42.9m")

	_hud.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_top_down():
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_1:
			_set_preset(70.0, 28.6)
		KEY_2:
			_set_preset(60.0, 34.6)
		KEY_3:
			_set_preset(50.0, 42.9)


func _set_preset(new_fov: float, new_height: float) -> void:
	fov = new_fov
	height = new_height
	_apply()
	var splay := INF
	if height > REFERENCE_BUILDING_HEIGHT:
		splay = height / (height - REFERENCE_BUILDING_HEIGHT)
	print("[camera_rig] preset -> fov %.1f deg, height %.1f m, ground %.1f m along axis, splay %.2fx" % [
		fov, height, _ground_half_extent() * 2.0, splay,
	])
