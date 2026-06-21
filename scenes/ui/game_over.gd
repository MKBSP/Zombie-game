extends Control

@onready var message_label: Label = $VBoxContainer/MessageLabel
@onready var play_again_button: Button = $VBoxContainer/PlayAgainButton
@onready var main_menu_button: Button = $VBoxContainer/MainMenuButton


func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again)
	main_menu_button.pressed.connect(_on_main_menu)


func show_message(text: String) -> void:
	message_label.text = text
	visible = true
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
