extends CanvasLayer
## Tuning HUD for the 3D test scenes: a GTA-style minimap (heading-up, ~30 m
## to each side) and live sliders for the things the night look turns on —
## mist, darkness, flashlight cone, eye adaptation. ESC frees the mouse to use
## the sliders; F toggles the flashlight.
##
## The visibility model these knobs are tuning is written up in
## docs/superpowers/specs/2026-09-16-visibility-and-eye-adaptation.md.

const Z := preload("res://scripts/3d/zombie_3d.gd")

@export var player_path: NodePath = ^"../TestPlayer"
@export var environment_path: NodePath = ^"../WorldEnvironment"
## Metres from the player to the minimap edge.
@export_range(10.0, 120.0, 1.0) var minimap_radius: float = 30.0
@export var minimap_px: int = 220
## Eye adaptation, see the visibility doc: exposure climbs from 1x to this
## while the flashlight is off, over adapt_time seconds. Flashlight back on
## snaps it down over dazzle_time.
@export_range(1.0, 6.0, 0.1) var adapt_gain: float = 2.0
@export_range(1.0, 300.0, 1.0) var adapt_time: float = 60.0
@export_range(0.1, 10.0, 0.1) var dazzle_time: float = 2.0

var _player: Node3D
var _env: Environment
var _attrs: CameraAttributesPractical
var _moon: DirectionalLight3D
var _map_cam: Camera3D
var _north: Label
var _panel: PanelContainer
var _hint: Label


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	var world_env := get_node_or_null(environment_path) as WorldEnvironment
	if _player == null or world_env == null:
		push_warning("TuningHUD: needs TestPlayer and WorldEnvironment siblings")
		return
	_env = world_env.environment
	_build_eye_adaptation(world_env)
	_build_moon()
	_build_minimap()
	_build_sliders()


## Eyes adjusting = a plain exposure multiplier driven in _process. Godot's
## auto exposure was tried first and blows a dark street out to daylight
## because it targets mid-grey whatever the sensitivity clamp says.
func _build_eye_adaptation(world_env: WorldEnvironment) -> void:
	_attrs = world_env.camera_attributes as CameraAttributesPractical
	if _attrs == null:
		_attrs = CameraAttributesPractical.new()
		world_env.camera_attributes = _attrs
	_attrs.auto_exposure_enabled = false
	_attrs.exposure_multiplier = 1.0


func _build_moon() -> void:
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color(0.62, 0.7, 0.9)
	_moon.light_energy = 0.08
	_moon.shadow_enabled = true
	_moon.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	get_parent().add_child.call_deferred(_moon)


func _build_minimap() -> void:
	var frame := Panel.new()
	frame.name = "Minimap"
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.85, 0.85, 0.7)
	frame.add_theme_stylebox_override("panel", style)
	frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	frame.position = Vector2(20, -20 - minimap_px)
	frame.size = Vector2(minimap_px, minimap_px)
	add_child(frame)

	var sub := SubViewport.new()
	sub.size = Vector2i(minimap_px, minimap_px)
	sub.world_3d = get_viewport().world_3d
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(sub)

	_map_cam = Camera3D.new()
	_map_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_cam.size = minimap_radius * 2.0
	_map_cam.near = 1.0
	_map_cam.far = 400.0
	_map_cam.cull_mask &= ~Z.COMMANDER_LAYER  # the zombie player's fog of war and markers
	# Flat, bright, fog-free: the map must not inherit the night look.
	var map_env := Environment.new()
	map_env.background_mode = Environment.BG_COLOR
	map_env.background_color = Color(0.09, 0.1, 0.12)
	map_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	map_env.ambient_light_color = Color(0.75, 0.75, 0.75)
	map_env.ambient_light_energy = 1.0
	_map_cam.environment = map_env
	_map_cam.attributes = CameraAttributesPractical.new()
	sub.add_child(_map_cam)

	var tex := TextureRect.new()
	tex.texture = sub.get_texture()
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(tex)

	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0, -9), Vector2(6, 7), Vector2(0, 4), Vector2(-6, 7)])
	arrow.color = Color(1.0, 1.0, 1.0)
	arrow.position = Vector2(minimap_px, minimap_px) * 0.5
	frame.add_child(arrow)

	_north = Label.new()
	_north.text = "N"
	_north.add_theme_font_size_override("font_size", 13)
	_north.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	frame.add_child(_north)


func _build_sliders() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Tuning"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-330, 10)
	_panel.size = Vector2(320, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_panel.visible = false  # debug: H shows the sliders and the camera readout
	_set_debug_label(false)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint.custom_minimum_size = Vector2(300, 0)
	box.add_child(_hint)

	_slider(box, "Mist (volumetric)", 0.0, 0.2, 0.005, _env.volumetric_fog_density,
		func(v: float) -> void: _env.volumetric_fog_density = v)
	_slider(box, "Haze (distance fog)", 0.0, 0.1, 0.002, _env.fog_density,
		func(v: float) -> void: _env.fog_density = v)
	_slider(box, "Ambient", 0.0, 1.0, 0.01, _env.ambient_light_energy,
		func(v: float) -> void: _env.ambient_light_energy = v)
	_slider(box, "Moon", 0.0, 1.0, 0.01, _moon.light_energy,
		func(v: float) -> void: _moon.light_energy = v)
	_slider(box, "Flashlight angle", 5.0, 80.0, 0.5, _player.flashlight_angle,
		func(v: float) -> void: _player.flashlight_angle = v)
	_slider(box, "Flashlight edge (higher = softer)", 0.15, 4.0, 0.05, _player.flashlight_edge_softness,
		func(v: float) -> void: _player.flashlight_edge_softness = v)
	_slider(box, "Flashlight energy", 0.0, 32.0, 0.1, _player.flashlight_energy,
		func(v: float) -> void: _player.flashlight_energy = v)
	_slider(box, "Flashlight range", 2.0, 80.0, 0.5, _player.flashlight_range,
		func(v: float) -> void: _player.flashlight_range = v)
	_slider(box, "Flashlight fog shaft", 0.0, 8.0, 0.05, _player.flashlight_fog_energy,
		func(v: float) -> void: _player.flashlight_fog_energy = v)
	_slider(box, "Eye adapt gain (dark-adapted exposure x)", 1.0, 6.0, 0.1, adapt_gain,
		func(v: float) -> void: adapt_gain = v)
	_slider(box, "Eye adapt time (s)", 1.0, 300.0, 1.0, adapt_time,
		func(v: float) -> void: adapt_time = v)


func _slider(box: VBoxContainer, label: String, lo: float, hi: float, step: float, value: float, setter: Callable) -> void:
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 12)
	box.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(300, 14)
	slider.focus_mode = Control.FOCUS_NONE
	var show := func(v: float) -> void: name_label.text = "%s: %.3f" % [label, v]
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		show.call(v))
	show.call(value)
	box.add_child(slider)


func _process(delta: float) -> void:
	if _map_cam == null or _player == null:
		return
	_adapt_eyes(delta)
	var yaw: float = _player.rotation.y
	_map_cam.global_position = _player.global_position + Vector3(0.0, 150.0, 0.0)
	# Heading-up: pitch straight down after yawing, so screen-up is where the
	# player faces.
	_map_cam.rotation = Vector3(-PI * 0.5, yaw, 0.0)
	var r := minimap_px * 0.5 - 14.0
	_north.position = Vector2(minimap_px * 0.5, minimap_px * 0.5) + Vector2(sin(yaw), -cos(yaw)) * r - Vector2(5, 8)


func _adapt_eyes(delta: float) -> void:
	var torch_on: bool = _player.flashlight_enabled and _player.get("torch_in_hand") != false
	var target := 1.0 if torch_on else adapt_gain
	var rate := (adapt_gain - 1.0) / (dazzle_time if torch_on else adapt_time)
	_attrs.exposure_multiplier = move_toward(_attrs.exposure_multiplier, target, rate * delta)
	_hint.text = "ESC menu · F flashlight · H hide   eyes: x%.2f  torch %s" % [
		_attrs.exposure_multiplier, "ON" if torch_on else "OFF"]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F:
				_player.flashlight_enabled = not _player.flashlight_enabled
			KEY_H:  # Tab swaps to the zombie commander (scripts/3d/commander.gd)
				_panel.visible = not _panel.visible
				_set_debug_label(_panel.visible)
				if _panel.visible:  # sliders need the cursor; clicking the world recaptures it
					_player.set("_mouse_freed", true)
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## The camera rig's readout (../DebugHUD/Label) goes with the sliders. The
## Label, not its CanvasLayer: the commander re-shows the layers on TAB.
func _set_debug_label(on: bool) -> void:
	var l := get_node_or_null("../DebugHUD/Label")
	if l:
		l.visible = on
