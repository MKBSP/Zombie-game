extends Control

## Title screen + role select.
## Play -> choose HUMAN (left) or ZOMBIE (right) -> load the world with that role.

@onready var title_panel: Control = $TitlePanel
@onready var role_panel: Control = $RolePanel
@onready var play_button: Button = $TitlePanel/CenterContainer/VBoxContainer/PlayButton
@onready var human_button: Button = $RolePanel/HBoxContainer/HumanButton
@onready var zombie_button: Button = $RolePanel/HBoxContainer/ZombieButton


func _ready() -> void:
	title_panel.visible = true
	role_panel.visible = false
	play_button.pressed.connect(_on_play_pressed)
	human_button.pressed.connect(_on_role_chosen.bind(GameState.Role.HUMAN))
	zombie_button.pressed.connect(_on_role_chosen.bind(GameState.Role.ZOMBIE))
	for b: Button in [human_button, zombie_button]:
		b.mouse_entered.connect(func(): b.modulate = Color(1.2, 1.2, 1.2))
		b.mouse_exited.connect(func(): b.modulate = Color.WHITE)


func _on_play_pressed() -> void:
	title_panel.visible = false
	role_panel.visible = true


func _on_role_chosen(role: GameState.Role) -> void:
	GameState.role = role
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
