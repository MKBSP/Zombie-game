class_name SettingsMenu
extends Control
## ZOMBIE COMMAND settings screen (mockup screen 12), built entirely in code.
## Instantiate with `SettingsMenu.new()`:
##   - from the main menu: `overlay_mode = false` (draws its own GameBg)
##   - from the pause menu: `overlay_mode = true` (dark scrim, game behind)
## Emits `closed` when the user backs out; the opener frees/hides it.

signal closed

var overlay_mode := false

const TABS := ["CONTROLS", "UI / HUD", "PROFILE"]

## Shooter bindings resolved live from InputMap (action -> display name).
const SHOOTER_ACTIONS := [
	["MOVE", ["move_up", "move_left", "move_down", "move_right"]],
	["SHOOT", []],  # empty = static mouse binding below
	["FOCUS AIM", ["focus_aim"]],
	["INTERACT", ["interact"]],
	["SWAP WEAPON", ["swap_weapon"]],
	["DROP WEAPON", ["drop_weapon"]],
	["PISTOL / HEAVY / MELEE", ["select_pistol", "select_heavy", "select_melee"]],
	["TOGGLE VIEW", ["toggle_view"]],
]
const SHOOTER_STATIC := {"SHOOT": ["LMB"]}

const ZOMBIE_CONTROLS := [
	["SELECT UNIT", ["LMB"]],
	["MULTI-SELECT", ["SHIFT", "LMB"]],
	["BOX SELECT", ["LMB DRAG"]],
	["MOVE ORDER", ["RMB"]],
	["CAMERA PAN", ["ARROWS"]],
]

const HUD_TOGGLES := [
	["Fullscreen  (F11)", "fullscreen"],
	["Show minimap", "show_minimap"],
	["Show interact prompts", "show_interact_prompts"],
	["Show pickup toasts", "show_pickup_toasts"],
	["Show debug coordinates", "show_debug_coords"],
]

var _active_tab := "CONTROLS"
var _tab_buttons := {}
var _content: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS  # usable while the tree is paused

	if overlay_mode:
		var scrim := ColorRect.new()
		scrim.color = UIStyle.fade(UIStyle.ABYSS, 0.82)
		add_child(scrim)
		scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		add_child(GameBg.new())

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var modal := PanelContainer.new()
	modal.theme_type_variation = "ModalPanel"
	modal.custom_minimum_size = Vector2(780, 500)
	center.add_child(modal)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	modal.add_child(root)

	root.add_child(_header())
	root.add_child(MenuWidgets._hairline())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	body.add_child(_nav())
	body.add_child(_vline())

	_content = MarginContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side, 20)
	body.add_child(_content)

	_select_tab("CONTROLS")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()


# ------------------------------------------------------------------ chrome

func _header() -> Control:
	var bar := MarginContainer.new()
	for side in ["left", "right"]:
		bar.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		bar.add_theme_constant_override("margin_" + side, 10)

	var row := HBoxContainer.new()
	bar.add_child(row)

	var title := Label.new()
	title.text = "SETTINGS"
	title.theme_type_variation = "MonoLabel"
	title.add_theme_color_override("font_color", UIStyle.INFECTION)
	row.add_child(title)

	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pad)

	var hint := Label.new()
	hint.text = "[ESC]  BACK TO PAUSE" if overlay_mode else "[ESC]  BACK"
	hint.theme_type_variation = "MicroLabel"
	row.add_child(hint)
	return bar


func _nav() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UIStyle.box(UIStyle.PANEL_DARK, Color.TRANSPARENT))
	panel.custom_minimum_size = Vector2(170, 0)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	for tab: String in TABS:
		var b := Button.new()
		b.text = tab
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_select_tab.bind(tab))
		v.add_child(b)
		_tab_buttons[tab] = b
	return panel


func _select_tab(tab: String) -> void:
	_active_tab = tab
	for tab_name: String in _tab_buttons:
		var b: Button = _tab_buttons[tab_name]
		var active: bool = tab_name == tab
		var sb := UIStyle.box(
			UIStyle.fade(UIStyle.INFECTION, 0.06) if active else Color.TRANSPARENT,
			Color.TRANSPARENT)
		sb.border_color = UIStyle.INFECTION
		sb.set_border_width_all(0)
		if active:
			sb.border_width_left = 2
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color",
			UIStyle.INFECTION if active else UIStyle.MOSS)

	for child in _content.get_children():
		child.queue_free()
	match tab:
		"CONTROLS":
			_content.add_child(_controls_tab())
		"UI / HUD":
			_content.add_child(_hud_tab())
		"PROFILE":
			_content.add_child(_profile_tab())


func _vline() -> Control:
	var line := ColorRect.new()
	line.color = UIStyle.BORDER
	line.custom_minimum_size = Vector2(1, 0)
	return line


# ------------------------------------------------------------------ tabs

func _controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	scroll.add_child(v)

	v.add_child(_section_header("SHOOTER", UIStyle.FAST_CYAN))
	for entry: Array in SHOOTER_ACTIONS:
		var keys: Array = SHOOTER_STATIC.get(entry[0], _action_keys(entry[1]))
		v.add_child(_binding_row(entry[0], keys))

	v.add_child(MenuWidgets.spacer(14.0))
	v.add_child(_section_header("ZOMBIE COMMANDER", UIStyle.INFECTION))
	for entry: Array in ZOMBIE_CONTROLS:
		v.add_child(_binding_row(entry[0], entry[1]))
	return scroll


func _hud_tab() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(_section_header("INTERFACE", UIStyle.INFECTION))
	for entry: Array in HUD_TOGGLES:
		v.add_child(_toggle_row(entry[0], entry[1]))
	var note := Label.new()
	note.text = "Applied on next match start."
	note.theme_type_variation = "MicroLabel"
	v.add_child(MenuWidgets.spacer(10.0))
	v.add_child(note)
	return v


func _profile_tab() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_section_header("OPERATOR", UIStyle.INFECTION))
	var name_l := Label.new()
	name_l.text = OS.get_environment("USER").to_upper()
	if name_l.text.is_empty():
		name_l.text = "OPERATOR_7"
	name_l.theme_type_variation = "MonoLabel"
	name_l.add_theme_color_override("font_color", UIStyle.INFECTION)
	v.add_child(name_l)
	var sub := Label.new()
	sub.text = "STAT TRACKING — COMING SOON"
	sub.theme_type_variation = "MicroLabel"
	v.add_child(sub)
	return v


# ------------------------------------------------------------------ widgets

func _section_header(text: String, color: Color) -> Control:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "MicroLabel"
	l.add_theme_color_override("font_color", color)
	return l


func _binding_row(action: String, keys: Array) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 30)

	var name_l := Label.new()
	name_l.text = action
	name_l.theme_type_variation = "BodyLabel"
	name_l.add_theme_color_override("font_color", UIStyle.ASH)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	for key: String in keys:
		row.add_child(_key_badge(key))
	return row


func _key_badge(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "MicroLabel"
	l.add_theme_color_override("font_color", UIStyle.ASH)
	var sb := UIStyle.box(UIStyle.BUNKER, UIStyle.BORDER)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	l.add_theme_stylebox_override("normal", sb)
	var badge_wrap := MarginContainer.new()
	badge_wrap.add_theme_constant_override("margin_left", 3)
	badge_wrap.add_child(l)
	return badge_wrap


func _toggle_row(label: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)

	var name_l := Label.new()
	name_l.text = label
	name_l.theme_type_variation = "BodyLabel"
	name_l.add_theme_color_override("font_color", UIStyle.ASH)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_l)

	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = _settings().get_value(key)
	b.custom_minimum_size = Vector2(64, 24)
	b.add_theme_font_size_override("font_size", 11)
	_paint_toggle(b)
	b.toggled.connect(func(on: bool) -> void:
		_settings().set_value(key, on)
		_paint_toggle(b))
	row.add_child(b)
	return row


func _paint_toggle(b: Button) -> void:
	var on := b.button_pressed
	b.text = "ON" if on else "OFF"
	var accent := UIStyle.INFECTION if on else UIStyle.DIM
	var sb := UIStyle.box(
		UIStyle.fade(UIStyle.INFECTION, 0.10) if on else Color.TRANSPARENT,
		accent,
		UIStyle.fade(UIStyle.INFECTION, 0.15) if on else Color.TRANSPARENT,
		4 if on else 0)
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", accent)


## The Settings autoload, fetched by path — the global identifier isn't
## visible to the editor's compiler until it restarts (registered this session).
func _settings() -> Node:
	return get_node("/root/Settings")


## Human-readable key list for a set of InputMap actions.
func _action_keys(actions: Array) -> Array:
	var keys: Array = []
	for action: String in actions:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var kc: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
				keys.append(OS.get_keycode_string(kc))
				break  # first key binding per action is enough
			elif ev is InputEventMouseButton:
				keys.append("LMB" if ev.button_index == MOUSE_BUTTON_LEFT
					else "RMB" if ev.button_index == MOUSE_BUTTON_RIGHT else "MMB")
				break
	return keys
