extends Control

## In-game overlay toggled with Esc: Resume + Quit to Main Menu.
## Single-player truly pauses the tree. Multiplayer is overlay-only — the
## simulation is authoritative on the server and can't be paused for one player.

@onready var resume_button: Button = $VBoxContainer/ResumeButton
@onready var menu_button: Button = $VBoxContainer/MenuButton


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


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
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
	visible = true
	if not GameState.multiplayer_active:
		get_tree().paused = true


func _close() -> void:
	visible = false
	get_tree().paused = false


func _on_menu() -> void:
	visible = false
	# Handles unpause, leaving the room, and the scene change for both modes.
	Net.leave_to_menu()
