extends Control

@onready var message_label: Label = $VBoxContainer/MessageLabel
@onready var play_again_button: Button = $VBoxContainer/PlayAgainButton
@onready var main_menu_button: Button = $VBoxContainer/MainMenuButton


func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again)
	main_menu_button.pressed.connect(_on_main_menu)
	_apply_zc_style()


## Visual-only ZOMBIE COMMAND restyle (same modal pattern as the pause menu);
## wiring above is untouched.
func _apply_zc_style() -> void:
	$Background.color = UIStyle.fade(UIStyle.ABYSS, 0.85)

	var vbox: VBoxContainer = $VBoxContainer
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var modal := PanelContainer.new()
	modal.theme_type_variation = "ModalPanel"
	modal.custom_minimum_size = Vector2(360, 0)
	center.add_child(modal)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	modal.add_child(margin)
	vbox.reparent(margin)
	vbox.add_theme_constant_override("separation", 8)

	message_label.add_theme_font_override("font", UIStyle.mono_spaced())
	message_label.add_theme_font_size_override("font_size", 26)
	message_label.add_theme_color_override("font_color", UIStyle.INFECTION)

	var line := ColorRect.new()
	line.color = UIStyle.BORDER
	line.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(line)
	vbox.move_child(line, 1)
	# vbox was reparented above, so $VBoxContainer/... paths no longer resolve.
	vbox.get_node("Spacer").custom_minimum_size = Vector2(0, 6)

	play_again_button.remove_theme_font_size_override("font_size")
	MenuWidgets.primary_button(play_again_button)
	play_again_button.custom_minimum_size = Vector2(300, 44)

	main_menu_button.remove_theme_font_size_override("font_size")
	main_menu_button.theme_type_variation = "DangerButton"
	main_menu_button.custom_minimum_size = Vector2(300, 44)


func show_message(text: String) -> void:
	message_label.text = text
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	play_again_button.disabled = false
	main_menu_button.disabled = false
	# Pause the game tree but keep this UI processing.
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS


func _on_play_again() -> void:
	if GameState.multiplayer_active:
		# The server restarts the match for both players; we just ask and wait
		# for _assign_role_and_start to reload the world.
		play_again_button.disabled = true
		main_menu_button.disabled = true
		play_again_button.text = "RESTARTING..."
		Net.request_rematch()
	else:
		get_tree().paused = false
		get_tree().reload_current_scene()


func _on_main_menu() -> void:
	# Handles unpause, leaving the room, and the scene change for both modes.
	Net.leave_to_menu()
