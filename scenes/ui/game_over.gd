extends Control

@onready var message_label: Label = $VBoxContainer/MessageLabel


func show_message(text: String) -> void:
	message_label.text = text
	visible = true
	# Pause the game tree but keep this UI processing
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().paused = false
		get_tree().reload_current_scene()
