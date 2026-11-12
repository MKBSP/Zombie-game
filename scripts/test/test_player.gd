extends CharacterBody3D
## Locomotion + aiming stand-in for the 3D camera test — Brief 11.
##
## Control scheme follows whatever the rig's `view_mode` asks for:
##   V1 TOP_DOWN_CURSOR  absolute world-space cursor while hip-firing; RMB (or
##                       the cover swoop) captures the mouse and switches to
##                       relative motion.
##   V2/V3/V4            mouse is captured from the start and always relative.
##                       ESC frees it, left-click grabs it back.
##
## Movement: walk by default, SHIFT sprint, C crouch, SPACE jump. Crouching
## lowers the capsule as well as the speed, so it is a real stance rather than a
## slow walk — and it is the steadiest one to shoot from (see below).
##
## The reticle is two distinct things (Brief 8.2) and they must not be
## conflated: the SPHERE is the reticle volume — the region of world space being
## aimed at. The CONE is the bullet path, muzzle -> through the sphere -> out
## beyond it. A sphere bigger than a head hitbox means shots can miss over the
## top; that is intended, and it is what the stat system will later modify.
## Movement state is the first real input to that: sprinting blows the volume
## up, crouching tightens it below standing.
##
## Shooting, arms and weapons live in scripts/3d/viewmodel.gd (a child of the
## camera) when the scene has one; this script only owns movement + aim.

@export_group("Movement")
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 6.0
@export var crouch_speed: float = 1.4
## Aiming caps your speed — aim mode is commitment, not awareness.
@export var aim_speed: float = 2.2
@export var jump_velocity: float = 7.0
## Project gravity is 9.8 m/s2 — real, and far too floaty for a game. Scaling it
## up while raising jump_velocity to match keeps the apex at ~1 m but roughly
## halves the hang time, which is what actually reads as "floaty".
@export_range(1.0, 6.0, 0.1) var gravity_scale: float = 2.4
## Extra gravity on the way DOWN only. Falling faster than you rose is the
## standard trick for a jump that feels weighted rather than balloon-like.
@export_range(1.0, 3.0, 0.05) var fall_gravity_multiplier: float = 1.35
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.0
## How fast the capsule rises/sinks between stances.
@export_range(1.0, 40.0, 0.5) var crouch_lerp: float = 12.0

@export_group("Aim")
@export var rig_path: NodePath = ^"../CameraRig"
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.0035
## How far up/down mouse Y can swing the aim, in degrees either side of rest.
@export_range(0.0, 80.0, 1.0) var aim_pitch_range: float = 28.0
## Seconds for the reticle to narrow to its aimed size. Deliberately slow — the
## aim settles gradually rather than snapping, so committing costs you time.
@export_range(0.05, 5.0, 0.05) var reticle_settle: float = 2.0

@export_group("Reticle")
## Metres ahead of the player where the volume sits under a straight-down
## camera, which has no forward centre ray of its own to put it on.
@export_range(2.0, 40.0, 0.5) var reticle_distance: float = 12.0
## How far a forward-looking centre ray searches for something to sit on.
@export_range(5.0, 120.0, 1.0) var reticle_max_distance: float = 45.0
## Height of the sphere centre — chest/belly on the target.
@export_range(0.3, 2.5, 0.05) var reticle_height: float = 1.2
## Sphere radius when hip-firing (loose).
@export_range(0.05, 3.0, 0.05) var reticle_radius_hip: float = 0.95
## Sphere radius while aiming (tight). Weapon/skill/stats feed this later.
@export_range(0.05, 3.0, 0.05) var reticle_radius_aim: float = 0.28
## Global fade on the reticle. Drop it at night, where a bright ball of colour
## is the only thing competing with the flashlight for your attention.
@export_range(0.0, 1.0, 0.05) var reticle_opacity: float = 1.0
## The bullet-path cone. Useful to read the spread model by daylight, clutter
## once the flashlight is doing the same job.
@export var show_bullet_cone: bool = true

@export_group("Movement spread")
## Multipliers on the reticle volume per stance. Crouching is the steadiest
## thing you can do; sprinting means you effectively cannot aim.
@export_range(0.1, 5.0, 0.05) var spread_sprint: float = 2.2
@export_range(0.1, 5.0, 0.05) var spread_walk: float = 1.0
@export_range(0.1, 5.0, 0.05) var spread_still: float = 0.75
@export_range(0.1, 5.0, 0.05) var spread_crouch: float = 0.5
## How quickly the volume responds to a change of stance.
@export_range(0.5, 20.0, 0.5) var spread_settle: float = 5.0

@export_group("Flashlight")
## Off for the daylight scenes; on for the night ones.
@export var flashlight_enabled: bool = false
@export_range(2.0, 80.0, 0.5) var flashlight_range: float = 26.0
## Half the cone's opening angle, matching Balance.FOG_SHOOTER in the 2D game.
@export_range(5.0, 80.0, 0.5) var flashlight_angle: float = 22.0
@export_range(0.0, 32.0, 0.1) var flashlight_energy: float = 5.0
@export var flashlight_color: Color = Color(1.0, 0.97, 0.85)
## Softens the hard edge of the cone. 1.0 is a sharp cutout; lower feathers it.
@export_range(0.15, 4.0, 0.05) var flashlight_edge_softness: float = 0.55
## How much the beam wavers, as a fraction of its energy. This is a torch in
## someone's hand, not a fixture — a little unsteadiness sells that.
@export_range(0.0, 0.6, 0.01) var flashlight_shimmer: float = 0.12
@export_range(0.5, 20.0, 0.5) var flashlight_shimmer_speed: float = 6.0
## How strongly the beam lights the volumetric fog — this is what makes a
## visible shaft rather than just a lit patch of ground.
@export_range(0.0, 8.0, 0.05) var flashlight_fog_energy: float = 1.4
## The dim personal halo, so you are not standing in absolute darkness.
@export_range(0.0, 8.0, 0.05) var halo_energy: float = 0.3
@export_range(0.5, 20.0, 0.5) var halo_range: float = 5.0
@export var halo_color: Color = Color(0.82, 0.86, 1.0)

## World yaw the player is facing, radians. Read by camera_rig.
var aim_yaw: float = 0.0
## Degrees of vertical aim from mouse Y, added to the rig's rest pitch. Read by
## camera_rig. Without this the forward-looking modes are one-dimensional: the
## centre ray is pinned at the rest pitch and you can only aim at the ground.
var aim_pitch_offset: float = 0.0
## True while RMB is held. Read by camera_rig.
var aiming: bool = false
var crouching: bool = false
var sprinting: bool = false
## Where the aim actually lands. The flashlight points at it.
var reticle_point: Vector3 = Vector3.ZERO
## Current reticle-volume radius (m) — a shot lands anywhere inside it.
var reticle_radius: float = 0.0
## Weapon multiplier on the volume, set by the viewmodel (rifle tight, shotgun wide).
var spread_mult: float = 1.0
## Hidden by the viewmodel when nothing in hand shoots (bat, torch, bare hands).
var reticle_visible: bool = true
## False while both hands are on a weapon: no torch, whatever F says.
var torch_in_hand: bool = true
## When set (the torch lens in the viewmodel), the beam starts here instead of the chest.
var light_anchor: Node3D = null
## Render layer the first-person viewmodel draws on. The world lights skip it,
## so the torch never lights its own handle; the viewmodel brings its own lights.
const VIEWMODEL_LAYER := 2

var _rig: Node3D = null
var _collision: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _mesh: MeshInstance3D = null
var _capsule_mesh: CapsuleMesh = null
var _sphere: MeshInstance3D = null
var _sphere_mesh: SphereMesh = null
var _cone: MeshInstance3D = null
var _cone_mesh: CylinderMesh = null
var _flashlight: SpotLight3D = null
var _halo: OmniLight3D = null
var _blend := 0.0
var _spread := 1.0
var _height := 1.8
var _time := 0.0
## Set when the player hits ESC to get the OS cursor back; cleared on the next
## click. Stops _sync_mouse_mode re-grabbing the mouse they just freed.
var _mouse_freed := false


func _ready() -> void:
	_rig = get_node_or_null(rig_path) as Node3D
	aim_yaw = rotation.y
	_height = stand_height

	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision != null:
		_capsule = _collision.shape as CapsuleShape3D
	_mesh = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh != null:
		_capsule_mesh = _mesh.mesh as CapsuleMesh

	if _wants_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _rig != null and _rig.is_first_person() and _mesh != null:
		# You would be looking at the inside of your own capsule.
		_mesh.visible = false

	_build_reticle()
	_build_lights()
	_collide_illum()


## The Illum block on the east side of Købmagergade is visual-only in the
## greybox (no "-col" suffix), so the street would have one wall. Give it
## collision here until the object is renamed "Illum-col" in Blender.
func _collide_illum() -> void:
	var illum := get_tree().current_scene.find_child("Illum", true, false)
	if illum is MeshInstance3D and illum.get_child_count() == 0:
		illum.create_trimesh_collision()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## V1 steers with a visible cursor; every other mode reads relative motion.
func _uses_cursor() -> bool:
	return _rig == null or _rig.uses_cursor()


func _wants_capture() -> bool:
	return not _uses_cursor()


func _physics_process(delta: float) -> void:
	_time += delta
	_update_stance(delta)

	if not is_on_floor():
		var gravity := get_gravity() * gravity_scale
		if velocity.y < 0.0:
			gravity *= fall_gravity_multiplier
		velocity += gravity * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = jump_velocity
	else:
		velocity.y = 0.0

	if _uses_cursor() and not aiming:
		_face_cursor()
	rotation.y = aim_yaw

	# Movement is relative to the RIG, so W is up-screen under a street-locked
	# top-down camera and forward-along-aim once the rig follows the mouse.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw := aim_yaw
	if _rig != null:
		yaw = _rig.rotation.y
	var direction := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)

	var speed := _current_speed()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()

	_blend = move_toward(_blend, 1.0 if aiming else 0.0, delta / maxf(reticle_settle, 0.01))
	_spread = lerpf(_spread, _stance_spread(input.length() > 0.1), 1.0 - exp(-spread_settle * delta))
	_sync_mouse_mode()
	_update_reticle()
	update_lights()


## Crouch is a real stance: the capsule shrinks as well as slowing down, and you
## cannot stand back up with something directly over your head.
func _update_stance(delta: float) -> void:
	sprinting = Input.is_action_pressed("sprint") and not aiming and not crouching
	var want_crouch := Input.is_action_pressed("crouch")
	if crouching and not want_crouch and _blocked_overhead():
		want_crouch = true
	crouching = want_crouch

	var target := crouch_height if crouching else stand_height
	_height = lerpf(_height, target, 1.0 - exp(-crouch_lerp * delta))
	if _capsule != null:
		_capsule.height = _height
		_collision.position.y = _height * 0.5
	if _capsule_mesh != null:
		_capsule_mesh.height = _height
		_mesh.position.y = _height * 0.5


func _blocked_overhead() -> bool:
	if _capsule == null:
		return false
	var probe := CapsuleShape3D.new()
	probe.radius = _capsule.radius
	probe.height = stand_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = Transform3D(Basis(), global_position + Vector3(0.0, stand_height * 0.5, 0.0))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _current_speed() -> float:
	if crouching:
		return crouch_speed
	if aiming:
		return aim_speed
	if sprinting:
		return sprint_speed
	return walk_speed


func _stance_spread(moving: bool) -> float:
	if crouching:
		return spread_crouch
	if sprinting and moving:
		return spread_sprint
	if moving:
		return spread_walk
	return spread_still


## The control scheme follows the CAMERA, not just RMB: when the rig swoops
## under a roof the cursor stops being meaningful, so the mouse is captured and
## handed back automatically as cover comes and goes.
func _sync_mouse_mode() -> void:
	if _mouse_freed:
		return
	var want_capture := _wants_capture() or aiming
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if want_capture and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not want_capture and captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_warp_cursor_to_aim()


func _unhandled_input(event: InputEvent) -> void:
	# Escape hatch out of a captured mouse, and a way back in.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_freed = true
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			aiming = button.pressed
			if button.pressed:
				_mouse_freed = false
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_mouse_freed = false
		return

	if event is InputEventMouseMotion and _reading_relative_mouse():
		var motion := (event as InputEventMouseMotion).relative
		# Mouse right turns right, so yaw decreases.
		aim_yaw -= motion.x * mouse_sensitivity
		# Mouse down (positive y) looks down, i.e. more negative pitch.
		aim_pitch_offset = clampf(
			aim_pitch_offset - motion.y * mouse_sensitivity * 57.2958,
			-aim_pitch_range,
			aim_pitch_range,
		)


func _reading_relative_mouse() -> bool:
	if _uses_cursor():
		return aiming
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Handing the cursor back is the side that can jump: the OS cursor reappears
## wherever it was parked, and the next _face_cursor() would snap the body to
## it. So put it back on the point we are currently aiming at.
func _warp_cursor_to_aim() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var ahead := global_position + _forward() * reticle_distance
	var screen := camera.unproject_position(ahead)
	if get_viewport().get_visible_rect().has_point(screen):
		Input.warp_mouse(screen)


func _forward() -> Vector3:
	return Vector3(-sin(aim_yaw), 0.0, -cos(aim_yaw))


## Point the capsule at the mouse cursor. Intersects the view ray with the
## player's ground plane analytically — no physics raycast needed for this.
func _face_cursor() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_normal := camera.project_ray_normal(mouse)
	if absf(ray_normal.y) < 0.0001:
		return
	var t := (global_position.y - ray_origin.y) / ray_normal.y
	if t <= 0.0:
		return
	var to_cursor := (ray_origin + ray_normal * t) - global_position
	if to_cursor.length_squared() < 0.01:
		return
	# The Facing marker sits on local -Z, so aim -Z down `to_cursor`.
	aim_yaw = atan2(-to_cursor.x, -to_cursor.z)


func _build_reticle() -> void:
	_sphere_mesh = SphereMesh.new()
	_sphere = MeshInstance3D.new()
	_sphere.name = "ReticleVolume"
	_sphere.mesh = _sphere_mesh
	_sphere.material_override = _translucent(Color(1.0, 0.25, 0.2))
	add_child(_sphere)

	_cone_mesh = CylinderMesh.new()
	_cone_mesh.bottom_radius = 0.02  # muzzle
	_cone = MeshInstance3D.new()
	_cone.name = "BulletPath"
	_cone.mesh = _cone_mesh
	_cone.material_override = _translucent(Color(1.0, 0.85, 0.35))
	add_child(_cone)

	# Both live in world space: once the camera sits over one shoulder, the
	# reticle is on the CAMERA's centre ray, not on the player's forward axis.
	_sphere.top_level = true
	_cone.top_level = true
	_cone.visible = show_bullet_cone

	_update_reticle()


func _build_lights() -> void:
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.top_level = true
	_flashlight.shadow_enabled = true
	_flashlight.light_cull_mask = 0xFFFFF & ~VIEWMODEL_LAYER
	add_child(_flashlight)

	_halo = OmniLight3D.new()
	_halo.name = "Halo"
	_halo.top_level = true
	_halo.shadow_enabled = false
	_halo.light_cull_mask = 0xFFFFF & ~VIEWMODEL_LAYER
	add_child(_halo)

	update_lights()


func _translucent(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


func _update_reticle() -> void:
	var t := smoothstep(0.0, 1.0, _blend)
	var radius := lerpf(reticle_radius_hip, reticle_radius_aim, t) * _spread * spread_mult
	reticle_radius = radius
	var muzzle := global_position + Vector3(0.0, reticle_height, 0.0)

	# Under a straight-down camera the centre ray points at the player's own
	# feet, so the volume goes ahead of the player instead. As the camera
	# pitches up toward the horizon it hands over to the true centre ray, which
	# is what locks the reticle to screen centre.
	var point := muzzle + _forward() * reticle_distance
	# Stop at the first thing in the way. Without this the volume sits on the
	# far side of a wall — indoors you end up aiming through the room at the
	# OUTSIDE of it, which reads as the aim jumping past the geometry.
	var space := get_world_3d().direct_space_state
	var wall_query := PhysicsRayQueryParameters3D.create(muzzle, point)
	wall_query.exclude = [get_rid()]
	var wall_hit := space.intersect_ray(wall_query)
	if not wall_hit.is_empty():
		point = wall_hit.position

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var pitch_deg := rad_to_deg(camera.global_rotation.x)
		var centre_weight := clampf((pitch_deg + 90.0) / 55.0, 0.0, 1.0)
		if centre_weight > 0.0:
			var origin := camera.global_position
			var far := origin + (-camera.global_transform.basis.z) * reticle_max_distance
			var query := PhysicsRayQueryParameters3D.create(origin, far)
			query.exclude = [get_rid()]
			var hit := space.intersect_ray(query)
			# Sit on whatever the ray actually meets. Placing it at a fixed
			# distance along the ray instead buries it underground the moment
			# the camera pitches down.
			var locked: Vector3 = hit.position if not hit.is_empty() else far
			point = point.lerp(locked, centre_weight)

	reticle_point = point

	_sphere_mesh.radius = radius
	_sphere_mesh.height = radius * 2.0
	_sphere.global_position = point
	_sphere.visible = reticle_visible
	# Faint while hip-firing, solid once committed.
	_sphere.material_override.albedo_color.a = lerpf(0.18, 0.45, t) * reticle_opacity

	_cone.visible = show_bullet_cone
	if not show_bullet_cone:
		return
	# Bullet path: muzzle -> through the sphere -> beyond, widening to the
	# sphere's radius. Anything inside that volume is a possible trajectory.
	var to_point := point - muzzle
	var length := to_point.length()
	if length < 0.05:
		return
	_cone_mesh.top_radius = radius
	_cone_mesh.height = length
	_cone.global_position = muzzle + to_point * 0.5
	_cone.look_at(point, Vector3.UP)
	# CylinderMesh runs along +Y; look_at aligned -Z, so tip it a quarter turn.
	_cone.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	_cone.material_override.albedo_color.a = lerpf(0.05, 0.20, t) * reticle_opacity


## The beam points at the reticle, so at night the lit spot IS the aim — one
## thing to read instead of two.
func update_lights() -> void:
	var lit := flashlight_enabled and torch_in_hand
	_flashlight.visible = lit
	_halo.visible = lit
	if not lit:
		return

	var muzzle := global_position + Vector3(0.0, _height * 0.65, 0.0)
	_halo.global_position = muzzle
	_halo.light_energy = halo_energy
	_halo.light_color = halo_color
	_halo.omni_range = halo_range

	var shimmer := _shimmer()
	_halo.light_energy = halo_energy * shimmer

	_flashlight.global_position = light_anchor.global_position if light_anchor != null else muzzle
	_flashlight.spot_range = flashlight_range
	_flashlight.spot_angle = flashlight_angle
	_flashlight.spot_angle_attenuation = flashlight_edge_softness
	_flashlight.light_energy = flashlight_energy * shimmer
	_flashlight.light_color = flashlight_color
	_flashlight.light_volumetric_fog_energy = flashlight_fog_energy
	if _flashlight.global_position.distance_to(reticle_point) > 0.5:
		_flashlight.look_at(reticle_point, Vector3.UP)


## Two sine waves at incommensurate rates, so it reads as an unsteady hand
## rather than a repeating pulse. Stays at 1.0 when shimmer is 0.
func _shimmer() -> float:
	if flashlight_shimmer <= 0.0:
		return 1.0
	var a := sin(_time * flashlight_shimmer_speed)
	var b := sin(_time * flashlight_shimmer_speed * 2.37 + 1.7)
	return 1.0 + flashlight_shimmer * (a * 0.6 + b * 0.4)
