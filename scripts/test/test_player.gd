extends CharacterBody3D
## Locomotion + aiming stand-in for the 3D camera test — Brief 11.
##
## Control scheme follows whatever the rig's `view_mode` asks for:
##   V1 TOP_DOWN_CURSOR  absolute world-space cursor while hip-firing; RMB
##                       captures the mouse and switches to relative motion.
##   V2/V3/V4            mouse is captured from the start and always relative.
##                       ESC frees it, left-click grabs it back.
##
## The reticle is two distinct things (Brief 8.2) and they must not be
## conflated: the SPHERE is the reticle volume — the region of world space being
## aimed at. The CONE is the bullet path, muzzle -> through the sphere -> out
## beyond it. A sphere bigger than a head hitbox means shots can miss over the
## top; that is intended, and it is what the stat system will later modify.
##
## No shooting yet. This is a feel test.

@export var speed: float = 5.0
## Slower while aiming — aim mode is commitment, not awareness.
@export var aim_speed: float = 2.6
@export var rig_path: NodePath = ^"../CameraRig"
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.0035
## How far up/down mouse Y can swing the aim, in degrees either side of rest.
@export_range(0.0, 80.0, 1.0) var aim_pitch_range: float = 28.0

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

## World yaw the player is facing, radians. Read by camera_rig.
var aim_yaw: float = 0.0
## Degrees of vertical aim from mouse Y, added to the rig's rest pitch. Read by
## camera_rig. Without this the forward-looking modes are one-dimensional: the
## centre ray is pinned at the rest pitch and you can only aim at the ground.
var aim_pitch_offset: float = 0.0
## True while RMB is held. Read by camera_rig.
var aiming: bool = false

var _rig: Node3D = null
var _sphere: MeshInstance3D = null
var _sphere_mesh: SphereMesh = null
var _cone: MeshInstance3D = null
var _cone_mesh: CylinderMesh = null
var _blend := 0.0


func _ready() -> void:
	_rig = get_node_or_null(rig_path) as Node3D
	aim_yaw = rotation.y
	if _wants_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _rig != null and _rig.is_first_person():
		# You would be looking at the inside of your own capsule.
		var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh != null:
			mesh.visible = false
	_build_reticle()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## V1 steers with a visible cursor; every other mode reads relative motion.
func _uses_cursor() -> bool:
	return _rig == null or _rig.uses_cursor()


func _wants_capture() -> bool:
	return not _uses_cursor()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
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

	var move_speed := aim_speed if aiming else speed
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	move_and_slide()

	_blend = move_toward(_blend, 1.0 if aiming else 0.0, delta / 0.30)
	_update_reticle()


func _unhandled_input(event: InputEvent) -> void:
	# Escape hatch out of a captured mouse, and a way back in.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			if button.pressed:
				_enter_aim()
			else:
				_exit_aim()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			if _wants_capture() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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


## `aim_yaw` already tracks the cursor every frame while hip-firing, so entering
## aim simply stops reading the cursor and starts reading relative motion —
## there is nothing to re-initialise and the aim cannot jump on the first frame.
func _enter_aim() -> void:
	aiming = true
	if _uses_cursor():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Leaving is the side that can jump: the OS cursor reappears wherever it was
## parked, and the next _face_cursor() would snap the body to it. So warp the
## cursor onto the point we are currently aiming at before handing control back.
func _exit_aim() -> void:
	aiming = false
	if not _uses_cursor():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera := get_viewport().get_camera_3d()
	if camera != null:
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
	_sphere.material_override = _translucent(Color(1.0, 0.25, 0.2, 0.30))
	add_child(_sphere)

	_cone_mesh = CylinderMesh.new()
	_cone_mesh.bottom_radius = 0.02  # muzzle
	_cone = MeshInstance3D.new()
	_cone.name = "BulletPath"
	_cone.mesh = _cone_mesh
	_cone.material_override = _translucent(Color(1.0, 0.85, 0.35, 0.16))
	add_child(_cone)

	# Both live in world space: once the camera sits over one shoulder, the
	# reticle is on the CAMERA's centre ray, not on the player's forward axis.
	_sphere.top_level = true
	_cone.top_level = true

	_update_reticle()


func _translucent(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


func _update_reticle() -> void:
	var t := smoothstep(0.0, 1.0, _blend)
	var radius := lerpf(reticle_radius_hip, reticle_radius_aim, t)
	var muzzle := global_position + Vector3(0.0, reticle_height, 0.0)

	# Under a straight-down camera the centre ray points at the player's own
	# feet, so the volume goes ahead of the player instead. As the camera
	# pitches up toward the horizon it hands over to the true centre ray, which
	# is what locks the reticle to screen centre.
	var point := muzzle + _forward() * reticle_distance
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var pitch_deg := rad_to_deg(camera.global_rotation.x)
		var centre_weight := clampf((pitch_deg + 90.0) / 55.0, 0.0, 1.0)
		if centre_weight > 0.0:
			var origin := camera.global_position
			var far := origin + (-camera.global_transform.basis.z) * reticle_max_distance
			var query := PhysicsRayQueryParameters3D.create(origin, far)
			query.exclude = [get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			# Sit on whatever the ray actually meets. Placing it at a fixed
			# distance along the ray instead buries it underground the moment
			# the camera pitches down.
			var locked: Vector3 = hit.position if not hit.is_empty() else far
			point = point.lerp(locked, centre_weight)

	_sphere_mesh.radius = radius
	_sphere_mesh.height = radius * 2.0
	_sphere.global_position = point
	# Faint while hip-firing, solid once committed.
	_sphere.material_override.albedo_color.a = lerpf(0.18, 0.45, t)

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
	_cone.material_override.albedo_color.a = lerpf(0.05, 0.20, t)
