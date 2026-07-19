extends Node
class_name ZombieController

## Manages the Zombie Controller's camera (pan + zoom) and fog of war.
## Attach to a Node in the world scene.

@export var camera: Camera2D
@export var fog_rect: TextureRect
@export var ground_layer: TileMapLayer
@export var selection_drawer: Control

#Merge Zombies to create new Zombies
@export var merge_manager: MergeManager
@export var fast_button: Button
@export var fat_button: Button
@export var cancel_button: Button


# Camera settings
const PAN_SPEED_KEYS: float = 400.0
const PAN_SPEED_MOUSE: float = 300.0
const EDGE_THRESHOLD: float = 30.0  # pixels from screen edge
# Height of the opaque bottom command bar. The world view is treated as the
# band above it: the camera centers there (offset) and edge-pan/pan-clamp
# use the bar's top edge as the bottom of the screen.
const BAR_H: float = 152.0
const ZOOM_MIN: float = 0.25
const ZOOM_MAX: float = 4.0
const ZOOM_STEP: float = 0.1

# Fog system
var fog_zc: FogZombieController
var fog_texture: ImageTexture
# Building tiles that block fog reveal (static map) + vision-light texture.
var _fog_blocked: Dictionary = {}
var _zc_radial_tex: Texture2D = null

# Whether this controller is active (receiving input)
var is_active: bool = true

# Selection state
var selected_zombies: Array[Node2D] = []
var _drag_start: Vector2 = Vector2.ZERO
var _is_dragging: bool = false
var _drag_threshold: float = 5.0  # pixels before a click becomes a drag

# Combat / movement / trigger values mirror the Zombie enums (zombie.gd).
const CB_AGGRESSIVE := 0
const CB_HOLD := 1
const MV_FREE := 0
const MV_FLEE := 1
const MV_PATROL := 2
const FT_ON_SIGHT := 0
const FT_ON_DAMAGE := 1
const FT_IDLE := 2
var stance_panel: Control = null
var _sel_header: Label = null
var _sel_stats: Label = null
var _portraits: Control = null
# Movement placement (flee = 1 point, patrol = 2 points).
var _pending_movement: int = -1
var _pending_trigger: int = 0
var _pending_points: Array[Vector2] = []
var _points_needed: int = 0
var _control_groups: Dictionary = {}
var minimap: Control = null
var _ripple_rng := RandomNumberGenerator.new()

func _ready() -> void:
	# Set up fog
	fog_zc = FogZombieController.new()
	add_child(fog_zc)

	# Create the texture for the shader
	fog_texture = ImageTexture.create_from_image(fog_zc.visibility_image)
	if fog_rect and fog_rect.material is ShaderMaterial:
		var mat: ShaderMaterial = fog_rect.material as ShaderMaterial
		mat.set_shader_parameter("visibility_tex", fog_texture)
	if fog_rect:
		# A TextureRect with no texture draws nothing, so the fog shader never
		# runs. Give it the fog texture (the shader overrides COLOR anyway) and
		# put it above the entities so unexplored areas actually go dark.
		fog_rect.texture = fog_texture
		fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
		fog_rect.z_index = 100
	_build_fog_blockers()

	# Minimap (runtime child of ZCOverlay so it inherits zombie-only visibility).
	var MinimapScript = load("res://scripts/minimap.gd")
	minimap = MinimapScript.new()
	minimap.name = "Minimap"
	minimap.anchor_left = 0.0
	minimap.anchor_right = 0.0
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = Balance.MINIMAP.margin_px
	minimap.offset_top = -(Balance.MINIMAP.size_px + Balance.MINIMAP.margin_px)
	minimap.offset_right = Balance.MINIMAP.margin_px + Balance.MINIMAP.size_px
	minimap.offset_bottom = -Balance.MINIMAP.margin_px
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay := get_node_or_null("ZCOverlay")
	if overlay:
		overlay.add_child(minimap)
		minimap.setup(fog_zc, camera)
		minimap.ground_layer = ground_layer
		minimap.building_layer = get_node_or_null("../BuildingLayer")
		minimap.rally_point_picked.connect(_rally_all)
		minimap.move_ordered.connect(_command_move)
		_create_rally_button(overlay)
		var world_node := get_parent()
		if world_node and world_node.has_signal("noise_event"):
			world_node.noise_event.connect(_on_noise)

#	set_process(false)
#	set_process_input(false)
	if fast_button:
		fast_button.pressed.connect(_on_fast_merge_pressed)
	if fat_button:
		fat_button.pressed.connect(_on_fat_merge_pressed)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_merge_pressed)
	if merge_manager:
		merge_manager.merge_started.connect(func(): cancel_button.visible = true)
		merge_manager.merge_completed.connect(func(): cancel_button.visible = false)
		merge_manager.merge_cancelled.connect(func(): cancel_button.visible = false)
		merge_manager.merge_locked_in.connect(func(): cancel_button.visible = false)

	# MERGE OPS panel (bottom-right): size so buttons are clickable + restyle.
	if fast_button:
		var panel: Control = fast_button.get_parent()
		panel.offset_left = -216
		panel.offset_top = -160
		panel.offset_right = -16
		panel.offset_bottom = -16
		if panel is VBoxContainer:
			panel.add_theme_constant_override("separation", 5)
		var merge_head := _panel_header("MERGE OPS")
		panel.add_child(merge_head)
		panel.move_child(merge_head, 0)
		fast_button.text = "MERGE → FAST  (2)"
		fat_button.text = "MERGE → FAT  (3)"
		cancel_button.text = "CANCEL MERGE"
		_style_merge_button(fast_button, UIStyle.FAST_CYAN)
		_style_merge_button(fat_button, UIStyle.FAT_AMBER)
		_style_merge_button(cancel_button, UIStyle.HEMORRHAGE)

	# Hide the old .tscn stance panel; build a two-row toolbar at runtime.
	var old_panel := get_node_or_null("ZCOverlay/StancePanel")
	if old_panel:
		old_panel.queue_free()
	if overlay:
		_build_stance_toolbar(overlay)
	if selection_drawer:
		selection_drawer.controller = self
	if overlay:
		_build_bottom_panel(overlay)


func _on_fast_merge_pressed() -> void:
	var standard_zombies := _get_standard_selected()
	if standard_zombies.size() < 2:
		return
	var pair := _find_closest_pair(standard_zombies)
	_send_merge_request(pair, "fast")


func _on_fat_merge_pressed() -> void:
	var standard_zombies := _get_standard_selected()
	if standard_zombies.size() < 3:
		return
	var trio := _find_closest_trio(standard_zombies)
	_send_merge_request(trio, "fat")


## Merges execute on the server; we send zombie node names (identical on
## both peers thanks to the MultiplayerSpawner).
func _send_merge_request(zombies: Array[Node2D], type: String) -> void:
	var names: Array = []
	for z in zombies:
		if is_instance_valid(z):
			names.append(String(z.name))
	if names.is_empty():
		return
	get_tree().current_scene.rpc_request_merge.rpc_id(1, names, type)


func _on_cancel_merge_pressed() -> void:
	get_tree().current_scene.rpc_cancel_merge.rpc_id(1)


## Returns selected standard zombies (excludes master, fast, fat).
func _get_standard_selected() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for z in selected_zombies:
		if is_instance_valid(z):
			if z.is_in_group("zombies") and not z.is_in_group("master_zombie") \
				and not z.is_in_group("fast_zombie") and not z.is_in_group("fat_zombie"):
				result.append(z)
	return result


## Find the 2 zombies closest to each other.
func _find_closest_pair(zombies: Array[Node2D]) -> Array[Node2D]:
	var best_dist: float = INF
	var best_pair: Array[Node2D] = []
	for i in range(zombies.size()):
		for j in range(i + 1, zombies.size()):
			var dist: float = zombies[i].global_position.distance_to(zombies[j].global_position)
			if dist < best_dist:
				best_dist = dist
				best_pair = [zombies[i], zombies[j]]
	return best_pair


## Find the 3 zombies with the smallest total pairwise distance.
func _find_closest_trio(zombies: Array[Node2D]) -> Array[Node2D]:
	var best_dist: float = INF
	var best_trio: Array[Node2D] = []
	for i in range(zombies.size()):
		for j in range(i + 1, zombies.size()):
			for k in range(j + 1, zombies.size()):
				var dist: float = (
					zombies[i].global_position.distance_to(zombies[j].global_position) +
					zombies[j].global_position.distance_to(zombies[k].global_position) +
					zombies[i].global_position.distance_to(zombies[k].global_position)
				)
				if dist < best_dist:
					best_dist = dist
					best_trio = [zombies[i], zombies[j], zombies[k]]
	return best_trio

## Call this to activate/deactivate the Zombie Controller view.
func activate() -> void:
	is_active = true
	set_process(true)
	set_process_input(true)
	if camera:
		camera.enabled = true
	if fog_rect:
		fog_rect.visible = true
	var overlay := get_node_or_null("ZCOverlay")
	if overlay:
		overlay.visible = true


func deactivate() -> void:
	is_active = false
	set_process(false)
	set_process_input(false)
	if camera:
		camera.enabled = false
	if fog_rect:
		fog_rect.visible = false
	var overlay := get_node_or_null("ZCOverlay")
	if overlay:
		overlay.visible = false


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
	# Shooter-style vision lights on every zombie (ZC view only, cosmetic).
	if Balance.WORLD.fog_enabled and GameState.role == GameState.Role.ZOMBIE:
		if _zc_radial_tex == null:
			_zc_radial_tex = ShooterLighting.make_radial_texture(Balance.FOG_ZC.light_tex_size)
		ZombieLighting.refresh_lights(get_tree(), _zc_radial_tex)
		# Update merge button states
	_update_merge_buttons()
	if stance_panel:
		stance_panel.visible = selected_zombies.size() > 0
	_update_selection_readout()

func _update_merge_buttons() -> void:
	if fast_button == null or fat_button == null:
		return

	var standard_count: int = _get_standard_selected().size()

	# Only show buttons when zombies are selected
	var any_selected: bool = selected_zombies.size() > 0
	fast_button.visible = any_selected
	fat_button.visible = any_selected

	# Enable/disable based on count
	fast_button.disabled = standard_count < 2 or merge_manager.state != MergeManager.MergeState.IDLE
	fat_button.disabled = standard_count < 3 or merge_manager.state != MergeManager.MergeState.IDLE


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

	# --- Control groups (Ctrl+1-9 save, 1-9 recall) ---
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var num: int = event.keycode - KEY_0
			if event.ctrl_pressed:
				_save_group(num)
			else:
				_recall_group(num)
			return
		if event.keycode == KEY_G:
			_arm_rally()
			return

	# --- Stance placement: clicks place points, not selection ---
	if _pending_movement >= 0 and event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT:
		# Swallow the release too, so placing a point can't deselect the horde.
		if not event.pressed:
			_is_dragging = false
			return
		if get_viewport().gui_get_hovered_control() is Button:
			return  # clicking a toolbar button, not placing a point
		var wp := _screen_to_world(event.position)
		_pending_points.append(wp)
		_show_ping(wp, Color.YELLOW, 34.0)  # feedback that the point landed
		if _pending_points.size() >= _points_needed:
			var p1: Vector2 = _pending_points[0]
			var p2: Vector2 = _pending_points[1] if _pending_points.size() > 1 else Vector2.ZERO
			_send_movement(_pending_movement, _pending_trigger, p1, p2)
			_pending_movement = -1
			_pending_points.clear()
		return

	# --- Rally placement: a world RIGHT-click (while armed) rallies the whole
	# horde, consistent with every other order. A left world click cancels. ---
	if minimap and minimap.rally_armed and event is InputEventMouseButton \
		and event.pressed:
		if _pointer_on_ui():
			return  # let the rally button / minimap handle their own click
		if event.button_index == MOUSE_BUTTON_RIGHT:
			minimap.rally_armed = false
			_rally_all(_screen_to_world(event.position))
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			minimap.rally_armed = false  # cancel: back to normal selection
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
	# Skip selection logic when clicking on UI (buttons, bottom bar, minimap)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _pointer_on_ui():
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

	# --- Right click: attack an enemy under the cursor, else move ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed and selected_zombies.size() > 0 and not _pointer_on_ui():
			var world_pos: Vector2 = _screen_to_world(event.position)
			var enemy := _get_enemy_at_position(world_pos)
			if enemy:
				_command_attack(enemy)
			else:
				_command_move(world_pos)


## True when the mouse is over interactive UI (a button, the minimap, or the
## bottom command bar) — world clicks should not fire there. The world-sized
## fog TextureRect ignores the mouse, so it never trips this.
func _pointer_on_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if hovered is Button or hovered == minimap:
		return true
	var n: Node = hovered
	while n != null:
		if n.name == "ZCBottomBar":
			return true
		n = n.get_parent()
	return false


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

	# Mouse edge panning. The bar's top edge is the effective screen bottom,
	# and hovering the HUD itself never pans.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var world_bottom: float = viewport_size.y - BAR_H

	if not _pointer_on_ui():
		if mouse_pos.x < EDGE_THRESHOLD:
			pan.x -= 1.0
		elif mouse_pos.x > viewport_size.x - EDGE_THRESHOLD:
			pan.x += 1.0
		if mouse_pos.y < EDGE_THRESHOLD:
			pan.y -= 1.0
		elif mouse_pos.y > world_bottom - EDGE_THRESHOLD:
			pan.y += 1.0

	if pan != Vector2.ZERO:
		camera.global_position += pan.normalized() * PAN_SPEED_MOUSE * delta

	# Clamp camera to map bounds
	camera.global_position = camera.global_position.clamp(
		Vector2.ZERO, Vector2(3008, 3008)
	)
	# Center the view in the band above the opaque command bar, not the full
	# window: push the look-at point down by half the bar height (screen px ->
	# world px, so zoom-corrected). Camera clamp excludes offset, which lets
	# the map's bottom rows clear the bar at full pan-down.
	camera.offset.y = BAR_H * 0.5 / camera.zoom.y


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

	fog_zc.update_visibility(zombies_data, _fog_blocked)
	fog_texture.update(fog_zc.visibility_image)


## Cache the building tiles that block line-of-sight reveal (static map).
func _build_fog_blockers() -> void:
	var bl: TileMapLayer = get_node_or_null("../BuildingLayer")
	if bl == null:
		return
	var used: Rect2i = bl.get_used_rect()
	for x in range(used.position.x, used.position.x + used.size.x):
		for y in range(used.position.y, used.position.y + used.size.y):
			var c := Vector2i(x, y)
			if bl.get_cell_tile_data(c) != null:
				_fog_blocked[c] = true

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


## Issue a move command to all selected zombies (executed on the server).
func _command_move(world_pos: Vector2) -> void:
	var names: Array = []
	for z in selected_zombies:
		if is_instance_valid(z):
			names.append(String(z.name))
	if names.is_empty():
		return
	get_tree().current_scene.rpc_command_move.rpc_id(1, names, world_pos)
	_show_ping(world_pos)
	if minimap:
		minimap.register_move_marker(world_pos, Color.GREEN)


func _selected_names() -> Array:
	var names: Array = []
	for z in selected_zombies:
		if is_instance_valid(z):
			names.append(String(z.name))
	return names


func _send_combat(combat: int) -> void:
	var names := _selected_names()
	if names.is_empty():
		return
	get_tree().current_scene.rpc_set_combat.rpc_id(1, names, combat)


func _begin_movement(mode: int, trigger: int, points_needed: int) -> void:
	if selected_zombies.is_empty():
		return
	if points_needed == 0:
		_send_movement(mode, trigger, Vector2.ZERO, Vector2.ZERO)
		return
	_pending_movement = mode
	_pending_trigger = trigger
	_points_needed = points_needed
	_pending_points.clear()


func _send_movement(mode: int, trigger: int, p1: Vector2, p2: Vector2) -> void:
	var names := _selected_names()
	if names.is_empty():
		return
	get_tree().current_scene.rpc_set_movement.rpc_id(1, names, mode, trigger, p1, p2)


## Bottom command bar (mockup screen 10): SELECTED[n] portraits + group stats,
## with the stance toolbar and MERGE OPS panel reparented in as sections.
## Runs from the minimap's right edge to the screen edge.
func _build_bottom_panel(overlay: Node) -> void:
	var m: float = Balance.MINIMAP.margin_px
	var sz: float = Balance.MINIMAP.size_px

	var bar := PanelContainer.new()
	bar.name = "ZCBottomBar"
	# Fully opaque: the world must read as ending at the bar, not running
	# underneath it (the 0.88 fade let entities ghost through).
	var bar_sb := UIStyle.box(UIStyle.BAR_BG, Color.TRANSPARENT)
	bar_sb.border_color = UIStyle.BORDER
	bar_sb.border_width_top = 1
	bar_sb.border_width_left = 1
	bar.add_theme_stylebox_override("panel", bar_sb)
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = m + sz + 12.0
	bar.offset_right = -0.0
	bar.offset_top = -BAR_H
	bar.offset_bottom = 0.0
	# STOP so _pointer_on_ui() can tell bar clicks from map clicks.
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bar.add_child(row)

	# — SELECTED [n] portraits + group stats —
	var sel_margin := MarginContainer.new()
	sel_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		sel_margin.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		sel_margin.add_theme_constant_override("margin_" + side, 8)
	row.add_child(sel_margin)
	var sel_col := VBoxContainer.new()
	sel_col.add_theme_constant_override("separation", 5)
	sel_margin.add_child(sel_col)
	_sel_header = Label.new()
	_sel_header.theme_type_variation = "MicroLabel"
	_sel_header.text = "NO UNITS SELECTED"
	sel_col.add_child(_sel_header)
	_portraits = PortraitStrip.new()
	_portraits.controller = self
	_portraits.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sel_col.add_child(_portraits)
	_sel_stats = Label.new()
	_sel_stats.theme_type_variation = "MicroLabel"
	_sel_stats.add_theme_color_override("font_color", UIStyle.MOSS)
	sel_col.add_child(_sel_stats)

	row.add_child(_bar_vline())

	# — Stance toolbar becomes a fixed section of the bar —
	if stance_panel:
		stance_panel.reparent(row)
		stance_panel.custom_minimum_size = Vector2(224, 0)
		stance_panel.alignment = BoxContainer.ALIGNMENT_CENTER

	row.add_child(_bar_vline())

	# — Merge ops panel likewise —
	if fast_button:
		var merge_panel: Control = fast_button.get_parent()
		merge_panel.reparent(row)
		merge_panel.custom_minimum_size = Vector2(216, 0)
		if merge_panel is BoxContainer:
			merge_panel.alignment = BoxContainer.ALIGNMENT_CENTER


## Keep the SELECTED header + group stats in sync with the live selection.
func _update_selection_readout() -> void:
	if _sel_header == null:
		return
	var alive: Array = []
	for z in selected_zombies:
		if is_instance_valid(z):
			alive.append(z)
	if alive.is_empty():
		_sel_header.text = "NO UNITS SELECTED"
		_sel_header.add_theme_color_override("font_color", UIStyle.DIM)
		_sel_stats.text = "CLICK OR DRAG TO SELECT  ·  RMB TO MOVE"
		return
	_sel_header.text = "SELECTED  [%d]" % alive.size()
	_sel_header.add_theme_color_override("font_color", UIStyle.INFECTION)
	var hp_sum := 0.0
	var counted := 0
	for z in alive:
		if "hp" in z and "max_hp" in z and z.max_hp > 0:
			hp_sum += float(z.hp) / float(z.max_hp)
			counted += 1
	if counted > 0:
		_sel_stats.text = "%d UNITS  ·  AVG HP %d%%" % [alive.size(), int(hp_sum / counted * 100.0)]
	else:
		_sel_stats.text = "%d UNITS" % alive.size()


func _bar_vline() -> Control:
	var line := ColorRect.new()
	line.color = UIStyle.BORDER
	line.custom_minimum_size = Vector2(1, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Live portraits of the current selection: type-colored frames + HP micro-bars.
class PortraitStrip:
	extends Control

	const BOX := 40.0
	const GAP := 6.0
	const MAX_SHOWN := 12

	var controller: Node = null

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if controller == null:
			return
		var i := 0
		for z in controller.selected_zombies:
			if not is_instance_valid(z) or i >= MAX_SHOWN:
				break
			var accent := UIStyle.INFECTION
			if z.is_in_group("master_zombie"):
				accent = UIStyle.HEMORRHAGE
			elif z.is_in_group("fat_zombie"):
				accent = UIStyle.FAT_AMBER
			elif z.is_in_group("fast_zombie"):
				accent = UIStyle.FAST_CYAN
			var x := i * (BOX + GAP)
			var box := Rect2(Vector2(x, 0), Vector2(BOX, BOX))
			draw_rect(box, UIStyle.fade(accent, 0.08))
			draw_rect(box, UIStyle.fade(accent, 0.7), false, 1.0)
			# Simple silhouette: head + torso blocks.
			draw_rect(Rect2(Vector2(x + BOX * 0.38, 7), Vector2(BOX * 0.24, BOX * 0.22)),
				UIStyle.fade(accent, 0.55))
			draw_rect(Rect2(Vector2(x + BOX * 0.28, 7 + BOX * 0.28), Vector2(BOX * 0.44, BOX * 0.34)),
				UIStyle.fade(accent, 0.35))
			# HP micro-bar.
			var pct := 1.0
			if "hp" in z and "max_hp" in z and z.max_hp > 0:
				pct = clampf(float(z.hp) / float(z.max_hp), 0.0, 1.0)
			draw_rect(Rect2(Vector2(x, BOX + 3), Vector2(BOX, 3)), UIStyle.BUNKER)
			draw_rect(Rect2(Vector2(x, BOX + 3), Vector2(BOX * pct, 3)), UIStyle.hp_color(pct))
			i += 1


## Compact ZOMBIE COMMAND toolbar button: mono caps, accent border on hover.
func _add_btn(parent: Node, text: String, cb: Callable, accent: Color = UIStyle.MOSS) -> void:
	var b := Button.new()
	b.text = text.to_upper()
	b.pressed.connect(cb)
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(102, 25)
	b.add_theme_stylebox_override("normal",
		UIStyle.box(UIStyle.fade(UIStyle.PANEL_DARK, 0.9), UIStyle.BORDER_DIM))
	var hot := UIStyle.box(
		UIStyle.fade(accent, 0.10), accent, UIStyle.fade(accent, 0.20), 5)
	for state in ["hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, hot)
	b.add_theme_color_override("font_color", UIStyle.fade(accent, 0.85))
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_focus_color", accent)
	parent.add_child(b)


## Micro section header for the ZC panels ("STANCE", "MERGE OPS", …).
func _panel_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "MicroLabel"
	return l


## Merge-op button: always shows its accent frame (these are the panel's
## whole identity — cyan fast / amber fat / red cancel).
func _style_merge_button(b: Button, accent: Color) -> void:
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_stylebox_override("normal",
		UIStyle.box(UIStyle.fade(accent, 0.05), UIStyle.fade(accent, 0.6)))
	var hot := UIStyle.box(
		UIStyle.fade(accent, 0.12), accent, UIStyle.fade(accent, 0.25), 6)
	for state in ["hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, hot)
	b.add_theme_stylebox_override("disabled",
		UIStyle.box(Color.TRANSPARENT, UIStyle.BORDER_DIM))
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_color_override("font_focus_color", accent)
	b.add_theme_color_override("font_disabled_color", UIStyle.DIM)


func _build_stance_toolbar(overlay: Node) -> void:
	stance_panel = VBoxContainer.new()
	stance_panel.name = "StanceToolbar"
	stance_panel.anchor_top = 1.0
	stance_panel.anchor_bottom = 1.0
	var m: float = Balance.MINIMAP.margin_px
	var sz: float = Balance.MINIMAP.size_px
	stance_panel.offset_left = m + sz + 12.0
	stance_panel.offset_right = m + sz + 210.0
	stance_panel.offset_top = -320.0
	stance_panel.offset_bottom = -m
	stance_panel.add_theme_constant_override("separation", 4)
	stance_panel.alignment = BoxContainer.ALIGNMENT_END
	stance_panel.add_child(_panel_header("PRIMARY STANCE"))
	var combat_row := HBoxContainer.new()
	combat_row.add_theme_constant_override("separation", 4)
	stance_panel.add_child(combat_row)
	_add_btn(combat_row, "Aggressive", func(): _send_combat(CB_AGGRESSIVE), UIStyle.WOUND)
	_add_btn(combat_row, "Hold", func(): _send_combat(CB_HOLD), UIStyle.HOLD_BLUE)
	stance_panel.add_child(_panel_header("MOVEMENT BEHAVIOR"))
	var moves := GridContainer.new()
	moves.columns = 2
	moves.add_theme_constant_override("h_separation", 4)
	moves.add_theme_constant_override("v_separation", 4)
	stance_panel.add_child(moves)
	_add_btn(moves, "Free", func(): _begin_movement(MV_FREE, 0, 0), UIStyle.MOSS)
	_add_btn(moves, "Patrol", func(): _begin_movement(MV_PATROL, 0, 2), UIStyle.PATROL_PURPLE)
	_add_btn(moves, "Flee: sight", func(): _begin_movement(MV_FLEE, FT_ON_SIGHT, 1), UIStyle.LURE_YELLOW)
	_add_btn(moves, "Flee: hit", func(): _begin_movement(MV_FLEE, FT_ON_DAMAGE, 1), UIStyle.LURE_YELLOW)
	_add_btn(moves, "Flee: idle", func(): _begin_movement(MV_FLEE, FT_IDLE, 1), UIStyle.LURE_YELLOW)
	overlay.add_child(stance_panel)
	stance_panel.visible = false


func _save_group(num: int) -> void:
	var names: Array = []
	for z in selected_zombies:
		if is_instance_valid(z):
			names.append(String(z.name))
	_control_groups[num] = names


func _recall_group(num: int) -> void:
	if not _control_groups.has(num):
		return
	_deselect_all()
	for n in _control_groups[num]:
		var z := get_tree().current_scene.get_node_or_null(NodePath("Entities/" + String(n)))
		if z and z.is_in_group("zombies"):
			selected_zombies.append(z)
			if z.has_method("set_selected"):
				z.set_selected(true)


const RALLY_GOLD := Color(1.0, 0.84, 0.0)


func _create_rally_button(overlay: Node) -> void:
	var btn := Button.new()
	btn.name = "RallyAllButton"
	btn.text = "RALLY ALL  [G]"
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	var m: float = Balance.MINIMAP.margin_px
	var sz: float = Balance.MINIMAP.size_px
	btn.offset_left = m
	btn.offset_right = m + sz
	btn.offset_top = -(sz + m + 46.0)
	btn.offset_bottom = -(sz + m + 20.0)
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_stylebox_override("normal",
		UIStyle.box(UIStyle.fade(UIStyle.PANEL_DARK, 0.9), UIStyle.fade(RALLY_GOLD, 0.5)))
	var hot := UIStyle.box(
		UIStyle.fade(RALLY_GOLD, 0.12), RALLY_GOLD, UIStyle.fade(RALLY_GOLD, 0.25), 5)
	for state in ["hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, hot)
	btn.add_theme_color_override("font_color", UIStyle.fade(RALLY_GOLD, 0.85))
	btn.add_theme_color_override("font_hover_color", RALLY_GOLD)
	btn.add_theme_color_override("font_pressed_color", RALLY_GOLD)
	btn.pressed.connect(_arm_rally)
	overlay.add_child(btn)

	# MINIMAP header strip just above the map (mockup screen 10).
	var head := Label.new()
	head.name = "MinimapHeader"
	head.text = "MINIMAP"
	head.theme_type_variation = "MicroLabel"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.anchor_top = 1.0
	head.anchor_bottom = 1.0
	head.offset_left = m
	head.offset_right = m + sz
	head.offset_top = -(sz + m + 16.0)
	head.offset_bottom = -(sz + m)
	overlay.add_child(head)


func _arm_rally() -> void:
	if minimap:
		minimap.rally_armed = true


## Rally: select the whole horde (rings light up as feedback) and send it to a
## point. Works from a minimap click or a world click while armed.
func _rally_all(world_pos: Vector2) -> void:
	_select_all_zombies()
	var names: Array = []
	for z in selected_zombies:
		if is_instance_valid(z):
			names.append(String(z.name))
	if names.is_empty():
		return
	get_tree().current_scene.rpc_command_move.rpc_id(1, names, world_pos)
	_show_ping(world_pos, Color(1.0, 0.84, 0.0), 90.0)
	if minimap:
		minimap.register_move_marker(world_pos, Color(1.0, 0.84, 0.0))


func _select_all_zombies() -> void:
	_deselect_all()
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D:
			selected_zombies.append(z)
			if z.has_method("set_selected"):
				z.set_selected(true)


func _on_noise(pos: Vector2, _strength: float) -> void:
	if minimap:
		minimap.register_noise(pos)
	if camera and camera.global_position.distance_to(pos) <= Balance.AGGRO.world_ripple_px:
		var rip = load("res://scripts/noise_ripple.gd").new()
		rip.global_position = MinimapMath.fuzz(pos, 30.0, _ripple_rng)
		rip.z_index = 40
		get_tree().current_scene.add_child(rip)

## Try to find a living enemy (shooter or NPC) under the given world position.
func _get_enemy_at_position(world_pos: Vector2) -> Node2D:
	for grp in ["shooter", "npcs"]:
		for e in get_tree().get_nodes_in_group(grp):
			if e is Node2D and is_instance_valid(e):
				if "is_dead" in e and e.is_dead:
					continue
				if e.global_position.distance_to(world_pos) < 20.0:
					return e
	return null


## Issue an attack order on a specific enemy (executed on the server).
func _command_attack(enemy: Node2D) -> void:
	var names := _selected_names()
	if names.is_empty():
		return
	get_tree().current_scene.rpc_command_attack.rpc_id(1, names, String(enemy.name))
	_show_ping(enemy.global_position, Color.RED, 40.0)
	if minimap:
		minimap.register_move_marker(enemy.global_position, Color.RED)


## Try to find a zombie under the given world position.
func _get_zombie_at_position(world_pos: Vector2) -> Node2D:
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Node2D:
			if zombie.global_position.distance_to(world_pos) < 20.0:
				return zombie
	return null
	

func _show_ping(world_pos: Vector2, ping_color: Color = Color.GREEN, max_radius: float = 48.0) -> void:
	var ping := Node2D.new()
	ping.set_script(preload("res://scripts/ping_visual.gd"))
	ping.global_position = world_pos
	# Above ZCFogRect (z_index 100) so the command feedback reads even when the
	# target point lies in unexplored fog.
	ping.z_index = 150
	ping.z_as_relative = false
	ping.color = ping_color
	ping.max_radius = max_radius
	get_tree().current_scene.add_child(ping)
