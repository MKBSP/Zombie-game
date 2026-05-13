extends Node
class_name ZombieController

## Manages the Zombie Controller's camera (pan + zoom) and fog of war.
## Attach to a Node in the world scene.

@export var camera: Camera2D
@export var fog_rect: TextureRect
@export var ground_layer: TileMapLayer
@export var selection_drawer: Control

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

# Selection state
var selected_zombies: Array[Node2D] = []
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_threshold: float = 5.0  # pixels before a click becomes a drag

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
		# Update selection rectangle visual
	if selection_drawer:
		if _is_dragging:
			selection_drawer.draw_rect_active = true
			selection_drawer.draw_rect_start = _drag_start
			selection_drawer.draw_rect_end = get_viewport().get_mouse_position()
		else:
			selection_drawer.draw_rect_active = false
	_update_fog()


#func _input(event: InputEvent) -> void:
#	# Zoom with mouse scroll
#	if event is InputEventMouseButton:
#		if event.pressed:
#			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
#				_zoom_camera(ZOOM_STEP)
#			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
#				_zoom_camera(-ZOOM_STEP)

func _input(event: InputEvent) -> void:
	if not is_active:
		return

	# --- Zoom ---
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(ZOOM_STEP)
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-ZOOM_STEP)
				return

	# --- Left click: selection ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos: Vector2 = _screen_to_world(event.position)

		if event.pressed:
			_drag_start = event.position
			_is_dragging = false
		else:
			# Button released
			if _is_dragging:
				# Complete drag-select
				var drag_end: Vector2 = event.position
				var rect := _make_world_rect(_drag_start, drag_end)
				_select_in_rect(rect)
				_is_dragging = false
			else:
				# Single click
				var zombie := _get_zombie_at_position(world_pos)
				if zombie:
					if Input.is_key_pressed(KEY_SHIFT):
						_toggle_select(zombie)
					else:
						_select_single(zombie)
				else:
					if not Input.is_key_pressed(KEY_SHIFT):
						_deselect_all()

	# --- Mouse motion: detect drag ---
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if not _is_dragging:
				if event.position.distance_to(_drag_start) > _drag_threshold:
					_is_dragging = true

	# --- Right click: move command ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and selected_zombies.size() > 0:
			var world_pos: Vector2 = _screen_to_world(event.position)
			_command_move(world_pos)


## Convert a screen position to a world position, accounting for camera.
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	if camera == null:
		return screen_pos
	# Get the canvas transform from the viewport
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos


## Create a world-space Rect2 from two screen positions.
func _make_world_rect(screen_a: Vector2, screen_b: Vector2) -> Rect2:
	var world_a := _screen_to_world(screen_a)
	var world_b := _screen_to_world(screen_b)
	var top_left := Vector2(minf(world_a.x, world_b.x), minf(world_a.y, world_b.y))
	var size := Vector2(absf(world_a.x - world_b.x), absf(world_a.y - world_b.y))
	return Rect2(top_left, size)


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

## Deselect all zombies.
func _deselect_all() -> void:
	for z in selected_zombies:
		if is_instance_valid(z) and z.has_method("set_selected"):
			z.set_selected(false)
	selected_zombies.clear()


## Select a single zombie (deselecting all others).
func _select_single(zombie: Node2D) -> void:
	_deselect_all()
	selected_zombies.append(zombie)
	if zombie.has_method("set_selected"):
		zombie.set_selected(true)


## Toggle a zombie in/out of the selection.
func _toggle_select(zombie: Node2D) -> void:
	if zombie in selected_zombies:
		selected_zombies.erase(zombie)
		if zombie.has_method("set_selected"):
			zombie.set_selected(false)
	else:
		selected_zombies.append(zombie)
		if zombie.has_method("set_selected"):
			zombie.set_selected(true)


## Select all zombies inside a world-space rectangle.
func _select_in_rect(rect: Rect2) -> void:
	_deselect_all()
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Node2D:
			if rect.has_point(zombie.global_position):
				selected_zombies.append(zombie)
				if zombie.has_method("set_selected"):
					zombie.set_selected(true)


## Issue a move command to all selected zombies.
func _command_move(world_pos: Vector2) -> void:
	for z in selected_zombies:
		if is_instance_valid(z) and z.has_method("set_command"):
			z.set_command(world_pos)
	# Show a brief ping at the target (we'll add this visual later)
			_show_ping(world_pos)

## Try to find a zombie under the given world position.
func _get_zombie_at_position(world_pos: Vector2) -> Node2D:
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Node2D:
			if zombie.global_position.distance_to(world_pos) < 20.0:
				return zombie
	return null
	

func _show_ping(world_pos: Vector2) -> void:
	var ping := Node2D.new()
	ping.global_position = world_pos
	ping.z_index = 50
	get_tree().current_scene.add_child(ping)

	# Simple circle that fades out
	var tween := get_tree().create_tween()
	tween.tween_property(ping, "modulate:a", 0.0, 0.5)
	tween.tween_callback(ping.queue_free)

	# Draw a green circle
	ping.set_script(preload("res://scripts/ping_visual.gd"))
