class_name MenuWidgets
extends RefCounted
## Builders that restyle plain menu nodes into ZOMBIE COMMAND widgets
## (docs/design_system.md). They mutate existing Buttons/Labels in place so
## scene wiring (@onready paths, signal connections) is never disturbed.


## Micro breadcrumb line, e.g. "MAIN MENU  ›  MULTIPLAYER".
static func breadcrumb(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "MicroLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UIStyle.MOSS)
	return l


## Screen heading, e.g. "SELECT YOUR ROLE".
static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HeadingLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Fixed vertical gap for VBox layouts.
static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## Restyle an existing status Label into a centered mono status line.
static func status_line(l: Label) -> void:
	l.theme_type_variation = "MonoLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)


## Turn an existing Button into a main-menu row: mono title over a dim
## description, green title + arrow on hover. Keeps the button's signals.
static func menu_row(btn: Button, title: String, desc: String) -> void:
	btn.text = ""
	btn.custom_minimum_size = Vector2(380, 62)
	btn.theme_type_variation = "MenuItemButton"

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", 9)
	btn.add_child(margin)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 1)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(v)

	var title_l := Label.new()
	title_l.text = title
	title_l.theme_type_variation = "MonoLabel"
	title_l.add_theme_color_override("font_color", UIStyle.ASH)
	v.add_child(title_l)

	var desc_l := Label.new()
	desc_l.text = desc
	desc_l.theme_type_variation = "BodyLabel"
	desc_l.add_theme_font_size_override("font_size", 12)
	v.add_child(desc_l)

	var arrow := Label.new()
	arrow.text = "›"
	arrow.theme_type_variation = "MonoLabel"
	arrow.add_theme_color_override("font_color", UIStyle.INFECTION)
	arrow.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	arrow.position.x -= 22.0
	arrow.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	arrow.grow_vertical = Control.GROW_DIRECTION_BOTH
	arrow.visible = false
	btn.add_child(arrow)

	btn.mouse_entered.connect(func() -> void:
		title_l.add_theme_color_override("font_color", UIStyle.INFECTION)
		arrow.visible = true)
	btn.mouse_exited.connect(func() -> void:
		title_l.add_theme_color_override("font_color", UIStyle.ASH)
		arrow.visible = false)


## Turn an existing Button into a role-select card (mockup screen 04):
## accent-colored frame on hover, title + tag, bullet lines, stat rows.
static func role_card(btn: Button, accent: Color, title: String, tag: String,
		bullets: Array, stats: Array) -> void:
	btn.text = ""
	btn.custom_minimum_size = Vector2(240, 220)
	btn.add_theme_stylebox_override("normal", UIStyle.box(UIStyle.BUNKER, UIStyle.BORDER_DIM))
	var hot := UIStyle.box(
		UIStyle.fade(accent, 0.06), accent, UIStyle.fade(accent, 0.15), 8)
	for state in ["hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, hot)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	btn.add_child(margin)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	var title_l := Label.new()
	title_l.text = title
	title_l.theme_type_variation = "MonoLabel"
	title_l.add_theme_color_override("font_color", UIStyle.ASH)
	v.add_child(title_l)

	var tag_l := Label.new()
	tag_l.text = tag
	tag_l.theme_type_variation = "MicroLabel"
	tag_l.add_theme_color_override("font_color", UIStyle.fade(accent, 0.8))
	v.add_child(tag_l)

	v.add_child(_hairline())
	for line: String in bullets:
		var b := Label.new()
		b.text = "·  " + line
		b.theme_type_variation = "BodyLabel"
		b.add_theme_font_size_override("font_size", 13)
		v.add_child(b)

	if not stats.is_empty():
		v.add_child(_hairline())
		for stat: Array in stats:
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var k := Label.new()
			k.text = stat[0]
			k.theme_type_variation = "MicroLabel"
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(k)
			var val := Label.new()
			val.text = stat[1]
			val.theme_type_variation = "MicroLabel"
			val.add_theme_color_override("font_color", UIStyle.MOSS)
			row.add_child(val)
			v.add_child(row)

	btn.mouse_entered.connect(func() -> void:
		title_l.add_theme_color_override("font_color", accent))
	btn.mouse_exited.connect(func() -> void:
		title_l.add_theme_color_override("font_color", UIStyle.ASH))


## Style a Button as the primary (green) call-to-action, e.g. START GAME.
static func primary_button(btn: Button) -> void:
	btn.custom_minimum_size = Vector2(260, 48)
	btn.add_theme_color_override("font_color", UIStyle.INFECTION)
	var normal := UIStyle.box(
		UIStyle.fade(UIStyle.INFECTION, 0.08), UIStyle.INFECTION,
		UIStyle.fade(UIStyle.INFECTION, 0.15), 6)
	var hover := UIStyle.box(
		UIStyle.fade(UIStyle.INFECTION, 0.14), UIStyle.INFECTION,
		UIStyle.fade(UIStyle.INFECTION, 0.25), 10)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", hover)


static func _hairline() -> Control:
	var line := ColorRect.new()
	line.color = UIStyle.BORDER_DIM
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line
