extends Node
## Autoload "UITheme". Builds the ZOMBIE COMMAND Theme in code from UIStyle
## tokens and applies it to the root window, so every Control in the project
## inherits it without per-scene theme wiring.
##
## Type variations (use via a Control's `theme_type_variation`):
##   Labels:  TitleLabel, HeadingLabel, MonoLabel, MicroLabel, BodyLabel
##   Buttons: MenuItemButton (large menu rows), DangerButton (red hover)
##   Panels:  CardPanel (BUNKER + dim border), ModalPanel (BAR_BG + border)

var theme: Theme

var font_mono: FontFile
var font_body: FontFile
## Mono with wide tracking for headings / HUD labels.
var mono_spaced: FontVariation


func _ready() -> void:
	theme = _build()
	get_window().theme = theme


func _build() -> Theme:
	font_mono = UIStyle.font(UIStyle.FONT_MONO)
	font_body = UIStyle.font(UIStyle.FONT_BODY)
	mono_spaced = UIStyle.mono_spaced()

	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 15

	_theme_labels(t)
	_theme_buttons(t)
	_theme_inputs(t)
	_theme_panels(t)
	return t


func _theme_labels(t: Theme) -> void:
	t.set_color("font_color", "Label", UIStyle.ASH)

	for variation: Array in [
		# [name, font, size, color]
		["TitleLabel", mono_spaced, 30, UIStyle.INFECTION],
		["HeadingLabel", mono_spaced, 22, UIStyle.ASH],
		["MonoLabel", mono_spaced, 13, UIStyle.MOSS],
		["MicroLabel", mono_spaced, 11, UIStyle.DIM],
		["BodyLabel", font_body, 14, UIStyle.MOSS],
	]:
		var vname: StringName = variation[0]
		t.set_type_variation(vname, "Label")
		t.set_font("font", vname, variation[1])
		t.set_font_size("font_size", vname, variation[2])
		t.set_color("font_color", vname, variation[3])


func _theme_buttons(t: Theme) -> void:
	t.set_font("font", "Button", mono_spaced)
	t.set_font_size("font_size", "Button", 14)
	t.set_color("font_color", "Button", UIStyle.MOSS)
	t.set_color("font_hover_color", "Button", UIStyle.INFECTION)
	t.set_color("font_pressed_color", "Button", UIStyle.INFECTION)
	t.set_color("font_focus_color", "Button", UIStyle.INFECTION)
	t.set_color("font_hover_pressed_color", "Button", UIStyle.INFECTION)
	t.set_color("font_disabled_color", "Button", UIStyle.DIM)

	var normal := UIStyle.box(Color.TRANSPARENT, UIStyle.BORDER_DIM)
	var hover := UIStyle.box(
		UIStyle.fade(UIStyle.INFECTION, 0.06), UIStyle.INFECTION,
		UIStyle.fade(UIStyle.INFECTION, 0.12), 6)
	var pressed := UIStyle.box(
		UIStyle.fade(UIStyle.INFECTION, 0.10), UIStyle.INFECTION,
		UIStyle.fade(UIStyle.INFECTION, 0.20), 8)
	var disabled := UIStyle.box(Color.TRANSPARENT, UIStyle.BORDER_DIM)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", disabled)

	# Large menu rows (main menu / multiplayer hub). Note: can't be called
	# "MenuButton" — that's a built-in Godot class.
	t.set_type_variation("MenuItemButton", "Button")
	t.set_font_size("font_size", "MenuItemButton", 15)
	var menu_normal := UIStyle.box(Color.TRANSPARENT, UIStyle.BORDER_DIM)
	menu_normal.content_margin_top = 14.0
	menu_normal.content_margin_bottom = 14.0
	menu_normal.content_margin_left = 18.0
	menu_normal.content_margin_right = 18.0
	var menu_hover: StyleBoxFlat = hover.duplicate()
	menu_hover.content_margin_top = 14.0
	menu_hover.content_margin_bottom = 14.0
	menu_hover.content_margin_left = 18.0
	menu_hover.content_margin_right = 18.0
	t.set_stylebox("normal", "MenuItemButton", menu_normal)
	t.set_stylebox("hover", "MenuItemButton", menu_hover)
	t.set_stylebox("focus", "MenuItemButton", menu_hover)
	var menu_pressed: StyleBoxFlat = menu_hover.duplicate()
	menu_pressed.bg_color = UIStyle.fade(UIStyle.INFECTION, 0.10)
	t.set_stylebox("pressed", "MenuItemButton", menu_pressed)

	# Destructive actions (exit to menu, disconnect).
	t.set_type_variation("DangerButton", "Button")
	t.set_color("font_hover_color", "DangerButton", UIStyle.HEMORRHAGE)
	t.set_color("font_pressed_color", "DangerButton", UIStyle.HEMORRHAGE)
	t.set_color("font_focus_color", "DangerButton", UIStyle.HEMORRHAGE)
	var danger_hover := UIStyle.box(
		UIStyle.fade(UIStyle.HEMORRHAGE, 0.08), UIStyle.HEMORRHAGE,
		UIStyle.fade(UIStyle.HEMORRHAGE, 0.15), 6)
	t.set_stylebox("hover", "DangerButton", danger_hover)
	t.set_stylebox("pressed", "DangerButton", danger_hover)
	t.set_stylebox("focus", "DangerButton", danger_hover)


func _theme_inputs(t: Theme) -> void:
	t.set_font("font", "LineEdit", mono_spaced)
	t.set_font_size("font_size", "LineEdit", 15)
	t.set_color("font_color", "LineEdit", UIStyle.INFECTION)
	t.set_color("font_placeholder_color", "LineEdit", UIStyle.DIM)
	t.set_color("caret_color", "LineEdit", UIStyle.INFECTION)
	t.set_color("selection_color", "LineEdit", UIStyle.fade(UIStyle.INFECTION, 0.25))
	var le_normal := UIStyle.box(UIStyle.fade(UIStyle.INFECTION, 0.04), UIStyle.BORDER)
	var le_focus := UIStyle.box(
		UIStyle.fade(UIStyle.INFECTION, 0.04), UIStyle.INFECTION,
		UIStyle.fade(UIStyle.INFECTION, 0.12), 6)
	t.set_stylebox("normal", "LineEdit", le_normal)
	t.set_stylebox("focus", "LineEdit", le_focus)

	# ProgressBar: BUNKER track, flat INFECTION fill.
	var track := UIStyle.box(UIStyle.BUNKER, UIStyle.BORDER_DIM)
	track.content_margin_left = 1.0
	track.content_margin_right = 1.0
	track.content_margin_top = 1.0
	track.content_margin_bottom = 1.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIStyle.INFECTION
	fill.set_corner_radius_all(0)
	t.set_stylebox("background", "ProgressBar", track)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_font("font", "ProgressBar", font_mono)
	t.set_color("font_color", "ProgressBar", UIStyle.ABYSS)

	t.set_font("font", "CheckButton", mono_spaced)
	t.set_color("font_color", "CheckButton", UIStyle.ASH)
	t.set_color("font_hover_color", "CheckButton", UIStyle.INFECTION)


func _theme_panels(t: Theme) -> void:
	var flat_bunker := UIStyle.box(UIStyle.BUNKER, UIStyle.BORDER_DIM)
	t.set_stylebox("panel", "Panel", flat_bunker)
	t.set_stylebox("panel", "PanelContainer", flat_bunker)

	t.set_type_variation("CardPanel", "PanelContainer")
	var card := UIStyle.box(UIStyle.BUNKER, UIStyle.BORDER_DIM)
	card.content_margin_left = 18.0
	card.content_margin_right = 18.0
	card.content_margin_top = 16.0
	card.content_margin_bottom = 16.0
	t.set_stylebox("panel", "CardPanel", card)

	t.set_type_variation("ModalPanel", "PanelContainer")
	var modal := UIStyle.box(UIStyle.BAR_BG, UIStyle.BORDER)
	modal.shadow_color = Color(0, 0, 0, 0.8)
	modal.shadow_size = 24
	modal.content_margin_left = 0.0
	modal.content_margin_right = 0.0
	modal.content_margin_top = 0.0
	modal.content_margin_bottom = 0.0
	t.set_stylebox("panel", "ModalPanel", modal)
