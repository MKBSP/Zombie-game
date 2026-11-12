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
##                    character stays locked facing up-screen.
##   FIRST_PERSON     V4. Camera at eye height. RMB is iron sights.
##
## In the top-down modes, never add pitch to the hip pose. The lean-in that
## fills the frame with facade comes from a wide FOV throwing off-axis geometry
## outward, not from tilting the camera.
##
## The one exception is COVER: a straight-down camera simply loses the player
## under any roof, so the top-down modes swoop to the over-the-shoulder pose
## when the player walks under one, and swoop back on the way out.
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
## Seconds for the full hip <-> aim transition. Slow on purpose: the aim should
## narrow gradually rather than snap.
@export_range(0.05, 4.0, 0.05) var aim_transition: float = 1.2

@export_group("Hip pose")
## Vertical FOV (keep_aspect stays KEEP_HEIGHT).
@export_range(30.0, 110.0, 0.5) var fov: float = 70.0
## Top-down modes: metres above the player.
@export_range(2.0, 80.0, 0.1) var height: float = 25.0
## Top-down modes: player position in frame. 0 = centred, positive = lower in
## frame with more ground ahead.
@export_range(-0.8, 0.8, 0.01) var player_screen_offset: float = 0.0
## TOP_DOWN_CURSOR only: rig rotation about world Y. Købmagergade at the spawn
## runs 20 deg off +Z, so -160 (= 200) puts it vertically up the screen.
## Per-street, not global. Every other mode takes its yaw from the mouse.
@export_range(-180.0, 180.0, 1.0) var camera_yaw: float = 180.0
## FIRST_PERSON only: camera height above the player's feet.
@export_range(0.5, 2.5, 0.05) var eye_height: float = 1.65

@export_group("Over-the-shoulder pose")
## V1's RMB pose, V2's resting pose, and where the top-down modes swoop to
## under cover. Metres above the player's feet.
@export_range(0.5, 20.0, 0.1) var aim_height: float = 2.1
## Metres behind the player.
@export_range(0.0, 20.0, 0.1) var aim_distance: float = 3.2
## Metres to the right. Without this the character sits dead centre and blocks
## the thing you are aiming at.
@export_range(-3.0, 3.0, 0.05) var aim_shoulder: float = 0.7
## Resting pitch in this pose. Negative looks down; near 0 is the horizon.
@export_range(-89.0, 10.0, 1.0) var aim_pitch: float = -10.0

@export_group("Aim / RMB")
## FOV while RMB is held.
@export_range(20.0, 110.0, 0.5) var aim_fov: float = 55.0
## OVER_SHOULDER: how far behind the player the camera sits while aiming.
@export_range(0.0, 20.0, 0.1) var ads_distance: float = 2.0

@export_group("Cover swoop")
## Top-down modes only. A straight-down camera loses the player entirely under
## a roof, so it drops to the over-the-shoulder pose instead.
@export var swoop_when_covered: bool = true
## Seconds for the swoop down and back.
@export_range(0.05, 3.0, 0.05) var cover_transition: float = 0.6
## Extra metres of roof-probe on top of the speed-derived distance.
##
## The probe is deliberately TIME-based, not a fixed distance: it reaches
## `speed * cover_transition + this`, i.e. roughly where you will be standing by
## the time the swoop finishes. A fixed 1 m did not work — at 5 m/s the 0.6 s
## swoop needs 3 m of travel, so 1 m bought only a third of it and the camera
## was still at ~11.6 m of 15 m as you crossed the threshold. Deriving it from
## speed also shrinks it automatically while aiming, where you move slower.
##
## Only ever ADDS cover, and only for the top-down modes that actually swoop:
## leaving is judged on your real position, so the camera stays down until you
## are genuinely out. Probes along actual movement, so it cannot flicker while
## you stand still, and walking past an opening does not trigger it.
@export_range(0.0, 5.0, 0.05) var cover_lookahead_margin: float = 0.75

@export_group("Camera collision")
## Brief 6 defers camera collision, but a pullback inside a 5-10 m street puts
## the camera through a facade constantly — the shoulder poses are untestable
## without it. A straight-down pose is never pulled in.
@export var aim_camera_collision: bool = true
## Height of the point the camera pulls in toward — roughly the shoulder.
@export_range(0.0, 3.0, 0.05) var camera_pivot_height: float = 1.4
## Stand-off from whatever the camera pulls in against.
@export_range(0.0, 1.5, 0.05) var camera_collision_margin: float = 0.3
## Exponential easing on the camera's own position. Without it the swoop is not
## a swoop: the moment the camera is allowed off straight-down, the collision
## ray hits the ceiling and clamps it to head height in a single frame, so it
## teleports down and only the rotation animates. 0 disables.
@export_range(0.0, 30.0, 0.5) var camera_move_smoothing: float = 7.0

@onready var _camera: Camera3D = $Camera3D

var _target: Node3D = null
var _hud: Label = null
var _focus := Vector3.ZERO
var _blend := 0.0  # 0 = hip, 1 = aim
var _cover := 0.0  # 0 = open sky, 1 = fully swooped under a roof
var _clearance := 1.0  # 1 = camera reaches its desired spot, <1 = pulled in
var _covered := false
var _roof := ""  # what is overhead, for the HUD
## Metres ahead the roof was found. 0 means it is directly overhead already.
var _cover_distance := 0.0
var _cam_local := Vector3.ZERO
var _cam_ready := false


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	_hud = get_node_or_null(hud_label_path) as Label
	if _target != null:
		_focus = _target.global_position
	_apply()


## True only where the player steers with an absolute world-space cursor. Once
## the camera has swooped under a roof the cursor is meaningless — its ray meets
## the ground plane at a grazing angle, or on the wrong side of a wall — so the
## controls hand over to relative mouse with it.
func uses_cursor() -> bool:
	return view_mode == ViewMode.TOP_DOWN_CURSOR and _cover < 0.5


func is_first_person() -> bool:
	return view_mode == ViewMode.FIRST_PERSON


func _is_top_down() -> bool:
	return view_mode == ViewMode.TOP_DOWN_CURSOR or view_mode == ViewMode.TOP_DOWN_ROTATE


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

	var cover_want := 1.0 if (_covered and swoop_when_covered and _is_top_down()) else 0.0
	_cover = move_toward(_cover, cover_want, delta / maxf(cover_transition, 0.01))

	_apply(delta)
	_update_hud()


func _is_aiming() -> bool:
	return _target != null and _target.get("aiming") == true


## Eased 0..1 so transitions start and settle softly.
func _t() -> float:
	return smoothstep(0.0, 1.0, _blend)


func _cover_t() -> float:
	return smoothstep(0.0, 1.0, _cover)


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


func _shoulder_pitch() -> float:
	return clampf(aim_pitch + _pitch_offset(), -89.0, 30.0)


func _hip_local() -> Vector3:
	match view_mode:
		ViewMode.OVER_SHOULDER:
			return _shoulder_local(aim_distance)
		ViewMode.FIRST_PERSON:
			return Vector3(0.0, eye_height, 0.0)
		_:
			return _top_down_local(height)


## Aiming and being under a roof want the same thing from the camera: a view
## along the ground that a shot can be placed in. So both top-down modes send
## RMB to the very same over-the-shoulder pose the cover swoop uses. Merely
## lowering a straight-down camera does not let you aim — there is no forward
## view to put the shot in, however close it gets.
func _aim_local() -> Vector3:
	match view_mode:
		ViewMode.OVER_SHOULDER:
			return _shoulder_local(ads_distance)
		ViewMode.FIRST_PERSON:
			return Vector3(0.0, eye_height, 0.0)
		_:
			return _shoulder_local(aim_distance)


func _hip_pitch() -> float:
	match view_mode:
		ViewMode.OVER_SHOULDER:
			return _shoulder_pitch()
		ViewMode.FIRST_PERSON:
			return clampf(_pitch_offset(), -89.0, 60.0)
		_:
			return -90.0


func _aim_pitch_now() -> float:
	match view_mode:
		ViewMode.FIRST_PERSON:
			return clampf(_pitch_offset(), -89.0, 60.0)
		_:
			return _shoulder_pitch()


## The pose the camera actually wants this frame: hip blended toward aim by RMB,
## then the whole thing blended toward the shoulder pose by cover.
func _desired_camera_local() -> Vector3:
	var normal := _hip_local().lerp(_aim_local(), _t())
	return normal.lerp(_shoulder_local(aim_distance), _cover_t())


func _current_pitch() -> float:
	var normal := lerpf(_hip_pitch(), _aim_pitch_now(), _t())
	return lerpf(normal, _shoulder_pitch(), _cover_t())


func _current_fov() -> float:
	return lerpf(lerpf(fov, aim_fov, _t()), aim_fov, _cover_t())


## The point the camera retreats toward when something is in the way.
##
## A straight-down camera must pull back toward the point directly OVERHEAD the
## player — never toward their shoulder, which would drag it to head height and
## destroy the very height being measured. Retreating straight overhead trims
## only the screen offset, which is the one thing that can shove a top-down
## camera sideways into a facade, and leaves the height untouched.
func _pivot_local() -> Vector3:
	if _current_pitch() <= -89.5:
		return Vector3(0.0, _desired_camera_local().y, 0.0)
	return Vector3(0.0, camera_pivot_height, 0.0)


func _apply(delta: float = -1.0) -> void:
	# V1 holds the rig to the street until RMB (or a roof) swings it to the aim
	# direction. Every other mode is mouse-driven in both states.
	var hip_yaw := deg_to_rad(camera_yaw) if view_mode == ViewMode.TOP_DOWN_CURSOR else _player_yaw()
	var yaw := lerp_angle(hip_yaw, _player_yaw(), _t())
	rotation = Vector3(0.0, lerp_angle(yaw, _player_yaw(), _cover_t()), 0.0)

	# Pulled in toward the shoulder pivot when something is in the way.
	var target := _pivot_local().lerp(_desired_camera_local(), _clearance)
	if not _cam_ready or delta < 0.0 or camera_move_smoothing <= 0.0:
		_cam_local = target
		_cam_ready = true
	else:
		_cam_local = _cam_local.lerp(target, 1.0 - exp(-camera_move_smoothing * delta))

	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = _current_fov()
	_camera.position = _cam_local
	_camera.rotation = Vector3(deg_to_rad(_current_pitch()), 0.0, 0.0)


## Physics queries belong on the physics tick, so results are cached here and
## consumed by _apply() on the render tick.
func _physics_process(_delta: float) -> void:
	_update_cover()

	_clearance = 1.0
	if not aim_camera_collision or _target == null:
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


## Ray straight up from a ground position; empty when open to the sky.
func _roof_above(pos: Vector3) -> Dictionary:
	var from := pos + Vector3(0.0, camera_pivot_height, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 90.0, 0.0))
	query.exclude = [_target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


## Is there a roof over the player? Deliberately a ray straight UP from the
## player rather than camera-to-player: once the camera swoops down under the
## ceiling a camera-to-player ray would come back clear, which would swoop it
## straight back up and oscillate forever.
func _update_cover() -> void:
	_covered = false
	_roof = ""
	if _target == null:
		return
	var hit := _roof_above(_target.global_position)
	_cover_distance = 0.0

	# Only the top-down modes swoop, so only they anticipate. For V2/V4 the
	# readout stays literal: are you actually under something.
	if hit.is_empty() and _is_top_down() and swoop_when_covered:
		var travel: Vector3 = _target.get("velocity")
		travel.y = 0.0
		var speed := travel.length()
		# Where you will be standing once the swoop has finished.
		var reach := speed * cover_transition + cover_lookahead_margin
		if speed > 0.5 and reach > 0.05:
			var direction := travel / speed
			# Step along the path rather than only testing the far end, so a
			# shallow porch between here and there is not stepped straight over.
			var steps := maxi(1, int(ceil(reach / 0.5)))
			for i in range(1, steps + 1):
				var probe := reach * float(i) / float(steps)
				hit = _roof_above(_target.global_position + direction * probe)
				if not hit.is_empty():
					_cover_distance = probe
					break
	if hit.is_empty():
		return
	_covered = true
	# Imported buildings put the collider under a named mesh, so the parent is
	# the useful label. CSG generates its collider on the node itself, whose
	# parent is only the scene root — use its own name there.
	var collider := hit.collider as Node
	var label := collider.name
	var parent := collider.get_parent()
	if parent != null and parent != get_tree().current_scene:
		label = parent.name
	_roof = "%s at %.1f m" % [label, hit.position.y - _target.global_position.y]


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


func _update_hud() -> void:
	if _hud == null:
		return

	var state := "HIP" if _blend < 0.5 else "AIM"
	if _blend > 0.0 and _blend < 1.0:
		state = "->AIM" if _is_aiming() else "->HIP"

	var lines := ["%s  [%s]   hold RMB to aim   (macOS: ctrl+click = RMB)" % [_mode_name(), state]]

	# Once leaned or swooped, the top-down readouts describe a camera that is no
	# longer there — quoting "height 15.0 m" while it sits at 8 m is worse than
	# not quoting it — so report the live pose instead.
	if _is_top_down() and _cover < 0.5 and _blend < 0.5:
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
			# Below the roofline the splay formula divides by a negative: the
			# building never projects a roof edge outward because its roof is
			# ABOVE the camera. You are inside the canyon looking at wall faces.
			lines.append("BELOW ROOFLINE by %.1f m — inside the canyon, no roofs in frame" % [
				REFERENCE_BUILDING_HEIGHT - height,
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
			lines.append("camera: %.2f m up, %.2f m back, %.2f m shoulder  (clearance %.2f)" % [
				_camera.position.y, _camera.position.z, _camera.position.x, _clearance,
			])

	if _target != null:
		var p := _target.global_position
		lines.append("player pos: (%.1f, %.1f)" % [p.x, p.z])

	if _covered:
		if not (_is_top_down() and swoop_when_covered):
			lines.append(">>> UNDER COVER (%s)" % _roof)
		elif _cover_distance > 0.0:
			lines.append(">>> COVER %.1f m AHEAD (%s) — swooping %.0f%%" % [
				_cover_distance, _roof, _cover * 100.0,
			])
		else:
			lines.append(">>> UNDER COVER (%s) — swooped %.0f%%" % [_roof, _cover * 100.0])

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
