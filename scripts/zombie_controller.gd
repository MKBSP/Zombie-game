extends Node
class_name ZombieController

## Manages the Zombie Controller's camera (pan + zoom) and fog of war.
## Attach to a Node in the world scene.

@export var camera: Camera2D
@export var fog_rect: TextureRect
@export var ground_layer: TileMapLayer

# Camera settings
const PAN_SPEED_KEYS: float = 400.0
const PAN_SPEED_MOUSE: float = 300.0
const EDGE_THRESHOLD: float = 30.0  # pixels from screen edge
const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 4.0
const ZOOM_STEP: float = 0.1

# Fog system
var fog_zc: FogZombieController
var fog_texture: ImageTexture

# Whether this controller is active (receiving input)
var is_active: bool = false


func _ready() -> void:
	# Set up fog
	fog_zc = FogZombieController.new()
	add_child(fog_zc)

	# Create the texture for the shader
	fog_texture = ImageTexture.create_from_image(fog_zc.visibility_image)
	if fog_rect and fog_rect.material is ShaderMaterial:
		var mat: ShaderMaterial = fog_rect.material as ShaderMaterial
		mat.set_shader_parameter("visibility_tex", fog_texture)

	set_process(false)
	set_process_input(false)


## Call this to activate/deactivate the Zombie Controller view.
func activate() -> void:
	is_active = true
	set_process(true)
	set_process_input(true)
	if camera:
		camera.enabled = true
	if fog_rect:
		fog_rect.visible = true


func deactivate() -> void:
	is_active = false
	set_process(false)
	set_process_input(false)
	if camera:
		camera.enabled = false
	if fog_rect:
		fog_rect.visible = false


func _process(delta: float) -> void:
	_handle_camera_pan(delta)
	_update_fog()


func _input(event: InputEvent) -> void:
	# Zoom with mouse scroll
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(ZOOM_STEP)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-ZOOM_STEP)


func _handle_camera_pan(delta: float) -> void:
	if camera == null:
		return

	var pan := Vector2.ZERO

	# Arrow key panning
	if Input.is_action_pressed("cam_up"):
		pan.y -= 1.0
	if Input.is_action_pressed("cam_down"):
		pan.y += 1.0
	if Input.is_action_pressed("cam_left"):
		pan.x -= 1.0
	if Input.is_action_pressed("cam_right"):
		pan.x += 1.0

	if pan != Vector2.ZERO:
		camera.global_position += pan.normalized() * PAN_SPEED_KEYS * delta
		return  # Prioritize key input over mouse edge

	# Mouse edge panning
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	if mouse_pos.x < EDGE_THRESHOLD:
		pan.x -= 1.0
	elif mouse_pos.x > viewport_size.x - EDGE_THRESHOLD:
		pan.x += 1.0
	if mouse_pos.y < EDGE_THRESHOLD:
		pan.y -= 1.0
	elif mouse_pos.y > viewport_size.y - EDGE_THRESHOLD:
		pan.y += 1.0

	if pan != Vector2.ZERO:
		camera.global_position += pan.normalized() * PAN_SPEED_MOUSE * delta

	# Clamp camera to map bounds
	camera.global_position = camera.global_position.clamp(
		Vector2.ZERO, Vector2(3008, 3008)
	)


func _zoom_camera(amount: float) -> void:
	if camera == null:
		return
	var new_zoom: float = clampf(camera.zoom.x + amount, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(new_zoom, new_zoom)


func _update_fog() -> void:
	if ground_layer == null:
		return

	# Gather all zombie positions and vision ranges
	var zombies_data: Array[Dictionary] = []
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Node2D:
			var tile: Vector2i = ground_layer.local_to_map(
				ground_layer.to_local(zombie.global_position)
			)
			var vision: int = 2
			if "vision_range" in zombie:
				vision = zombie.vision_range
			# Fast and Fat zombies also have vision 2 (same as standard)
			zombies_data.append({"tile": tile, "vision": vision})

	fog_zc.update_visibility(zombies_data)
	fog_texture.update(fog_zc.visibility_image)
