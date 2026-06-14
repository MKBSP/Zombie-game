extends Control

## Title → mode select (Single player / Multiplayer).
## Single player → role select → world (offline).
## Multiplayer → Host (lobby: pick role, wait for player, start) or Join (IP → wait for host).

@onready var title_panel: Control = $TitlePanel
@onready var mode_panel: Control = $ModePanel
@onready var role_panel: Control = $RolePanel
@onready var mp_panel: Control = $MultiplayerPanel
@onready var lobby_panel: Control = $LobbyPanel
@onready var join_panel: Control = $JoinPanel

@onready var play_button: Button = $TitlePanel/CenterContainer/VBoxContainer/PlayButton
@onready var single_button: Button = $ModePanel/HBoxContainer/SingleButton
@onready var multi_button: Button = $ModePanel/HBoxContainer/MultiButton
@onready var human_button: Button = $RolePanel/HBoxContainer/HumanButton
@onready var zombie_button: Button = $RolePanel/HBoxContainer/ZombieButton
@onready var host_button: Button = $MultiplayerPanel/CenterContainer/VBoxContainer/HostButton
@onready var join_button: Button = $MultiplayerPanel/CenterContainer/VBoxContainer/JoinButton
@onready var lobby_human_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/RoleRow/LobbyHumanButton
@onready var lobby_zombie_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/RoleRow/LobbyZombieButton
@onready var lobby_status: Label = $LobbyPanel/CenterContainer/VBoxContainer/LobbyStatus
@onready var start_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/StartButton
@onready var ip_edit: LineEdit = $JoinPanel/CenterContainer/VBoxContainer/IPEdit
@onready var connect_button: Button = $JoinPanel/CenterContainer/VBoxContainer/ConnectButton
@onready var join_status: Label = $JoinPanel/CenterContainer/VBoxContainer/JoinStatus

var _lobby_role: GameState.Role = GameState.Role.HUMAN


func _ready() -> void:
	_show_panel(title_panel)

	play_button.pressed.connect(func(): _show_panel(mode_panel))
	single_button.pressed.connect(_on_single_pressed)
	multi_button.pressed.connect(func(): _show_panel(mp_panel))

	human_button.pressed.connect(_on_solo_role_chosen.bind(GameState.Role.HUMAN))
	zombie_button.pressed.connect(_on_solo_role_chosen.bind(GameState.Role.ZOMBIE))

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(func(): _show_panel(join_panel))

	lobby_human_button.pressed.connect(_on_lobby_role.bind(GameState.Role.HUMAN))
	lobby_zombie_button.pressed.connect(_on_lobby_role.bind(GameState.Role.ZOMBIE))
	start_button.pressed.connect(_on_start_pressed)
	connect_button.pressed.connect(_on_connect_pressed)

	Net.player_joined.connect(_on_player_joined)
	Net.player_left.connect(_on_player_left)
	Net.connection_failed.connect(_on_connection_failed)

	_update_lobby_role_buttons()

	# Dev shortcut: `godot --path . -- --autojoin` joins localhost immediately
	# (used for two-window testing on one machine).
	if "--autojoin" in OS.get_cmdline_user_args():
		_show_panel(join_panel)
		_on_connect_pressed()


func _show_panel(panel: Control) -> void:
	for p in [title_panel, mode_panel, role_panel, mp_panel, lobby_panel, join_panel]:
		p.visible = (p == panel)


func _on_single_pressed() -> void:
	Net.leave()  # make sure we're offline
	_show_panel(role_panel)


func _on_solo_role_chosen(role: GameState.Role) -> void:
	GameState.role = role
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _on_host_pressed() -> void:
	if Net.host() != OK:
		lobby_status.text = "Failed to start server (port in use?)"
		return
	lobby_status.text = "Waiting for player..."
	start_button.disabled = true
	_show_panel(lobby_panel)


func _on_lobby_role(role: GameState.Role) -> void:
	_lobby_role = role
	_update_lobby_role_buttons()


func _update_lobby_role_buttons() -> void:
	lobby_human_button.modulate = Color(0.5, 1.5, 0.5) if _lobby_role == GameState.Role.HUMAN else Color.WHITE
	lobby_zombie_button.modulate = Color(0.5, 1.5, 0.5) if _lobby_role == GameState.Role.ZOMBIE else Color.WHITE


func _on_player_joined() -> void:
	lobby_status.text = "Player connected!"
	start_button.disabled = false


func _on_player_left() -> void:
	if lobby_panel.visible:
		lobby_status.text = "Player left. Waiting for player..."
		start_button.disabled = true


func _on_start_pressed() -> void:
	Net.start_game(_lobby_role)


func _on_connect_pressed() -> void:
	var ip := ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	if Net.join(ip) != OK:
		join_status.text = "Invalid address"
		return
	join_status.text = "Connecting... then waiting for host to start"
	connect_button.disabled = true


func _on_connection_failed() -> void:
	join_status.text = "Connection failed — is the host running?"
	connect_button.disabled = false
