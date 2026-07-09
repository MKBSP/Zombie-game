extends Control

## In-game overlay toggled with Esc: Resume + Quit to Main Menu.
## Single-player truly pauses the tree. Multiplayer is overlay-only — the
## simulation is authoritative on the server and can't be paused for one player.

@onready var resume_button: Button = $VBoxContainer/ResumeButton
@onready var menu_button: Button = $VBoxContainer/MenuButton

var _settings_open := false
var _modal: PanelContainer = null


func _ready() -> void:
	visible = false
	# Stay responsive while the tree is paused (single-player).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The dedicated server has no input or view; this node just sits dormant.
	if GameState.is_dedicated_server:
		set_process_unhandled_input(false)
		return
	resume_button.pressed.connect(_close)
	menu_button.pressed.connect(_on_menu)
	_apply_zc_style()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_open:
		return  # the settings overlay owns ESC while it's up
	# Don't pop over the game-over screen.
	var game_over := get_parent().get_node_or_null("GameOverScreen")
	if game_over and game_over.visible:
		return
	if visible:
		_close()
	else:
		_open()
	get_viewport().set_input_as_handled()


func _open() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	if not GameState.multiplayer_active:
		get_tree().paused = true


func _close() -> void:
	visible = false
	get_tree().paused = false
	var ac := get_parent().get_node_or_null("AimCursor")
	if ac and ac.has_method("is_active") and ac.is_active():
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _on_menu() -> void:
	visible = false
	# Handles unpause, leaving the room, and the scene change for both modes.
	Net.leave_to_menu()


# ------------------------------------------------------- ZOMBIE COMMAND styling
# Visual-only restyle to the pause modal from the mockup (screen 13) plus a
# SETTINGS entry. Wiring above is untouched; nodes are restyled in place.

func _apply_zc_style() -> void:
	$Background.color = UIStyle.fade(UIStyle.ABYSS, 0.78)

	var vbox: VBoxContainer = $VBoxContainer
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_modal = PanelContainer.new()
	_modal.theme_type_variation = "ModalPanel"
	_modal.custom_minimum_size = Vector2(320, 0)
	center.add_child(_modal)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_modal.add_child(margin)
	vbox.reparent(margin)
	vbox.add_theme_constant_override("separation", 8)

	var title: Label = $VBoxContainer/TitleLabel if has_node("VBoxContainer/TitleLabel") \
		else vbox.get_node("TitleLabel")
	title.theme_type_variation = "MonoLabel"
	title.add_theme_font_size_override("font_size", 18)  # tscn had 48
	title.add_theme_color_override("font_color", UIStyle.INFECTION)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var line := ColorRect.new()
	line.color = UIStyle.BORDER
	line.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(line)
	vbox.move_child(line, 1)
	vbox.get_node("Spacer").custom_minimum_size = Vector2(0, 6)

	resume_button.remove_theme_font_size_override("font_size")
	MenuWidgets.primary_button(resume_button)
	resume_button.custom_minimum_size = Vector2(280, 44)

	var settings_btn := Button.new()
	settings_btn.text = "SETTINGS"
	settings_btn.custom_minimum_size = Vector2(280, 44)
	settings_btn.pressed.connect(_on_settings)
	vbox.add_child(settings_btn)
	vbox.move_child(settings_btn, vbox.get_children().find(menu_button))

	menu_button.remove_theme_font_size_override("font_size")
	menu_button.theme_type_variation = "DangerButton"
	menu_button.text = "EXIT TO MENU"
	menu_button.custom_minimum_size = Vector2(280, 44)


func _on_settings() -> void:
	var s := SettingsMenu.new()
	s.overlay_mode = true
	add_child(s)
	_settings_open = true
	_modal.visible = false
	s.closed.connect(func() -> void:
		s.queue_free()
		_settings_open = false
		_modal.visible = true)
