extends Control

## Title → mode select.
## Single player → role select → world (offline).
## Multiplayer → connect to the dedicated server → Host or Join:
##   Host → server makes a room + code (share it) → lobby → pick role.
##   Join → enter code → lobby → pick role.
## When both roles are picked, the server starts the match.

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
@onready var join_choice_button: Button = $MultiplayerPanel/CenterContainer/VBoxContainer/JoinButton
@onready var mp_status: Label = $MultiplayerPanel/CenterContainer/VBoxContainer/MPStatus
@onready var lobby_human_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/RoleRow/LobbyHumanButton
@onready var lobby_zombie_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/RoleRow/LobbyZombieButton
@onready var lobby_title: Label = $LobbyPanel/CenterContainer/VBoxContainer/LobbyTitle
@onready var lobby_status: Label = $LobbyPanel/CenterContainer/VBoxContainer/LobbyStatus
@onready var start_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/StartButton
@onready var code_edit: LineEdit = $JoinPanel/CenterContainer/VBoxContainer/IPEdit
@onready var join_title: Label = $JoinPanel/CenterContainer/VBoxContainer/JoinTitle
@onready var join_confirm_button: Button = $JoinPanel/CenterContainer/VBoxContainer/ConnectButton
@onready var join_status: Label = $JoinPanel/CenterContainer/VBoxContainer/JoinStatus

var _room_code: String = ""
# Launch-flag automation (local two-window testing).
var _auto_role: int = -1
var _auto_host: bool = false
var _auto_join_code: String = ""


## All launch args, whether after `--` (terminal) or plain (editor instances).
func _all_cmdline_args() -> PackedStringArray:
	var a := OS.get_cmdline_args()
	a.append_array(OS.get_cmdline_user_args())
	return a


func _ready() -> void:
	var cmdline := _all_cmdline_args()

	# Dedicated headless server entry point: `godot --headless -- --server`.
	if "--server" in cmdline:
		Net.start_dedicated_server()
		return

	_show_panel(title_panel)

	play_button.pressed.connect(func(): _show_panel(mode_panel))
	single_button.pressed.connect(_on_single_pressed)
	multi_button.pressed.connect(_on_multi_pressed)

	human_button.pressed.connect(_on_solo_role_chosen.bind(GameState.Role.HUMAN))
	zombie_button.pressed.connect(_on_solo_role_chosen.bind(GameState.Role.ZOMBIE))

	host_button.pressed.connect(_on_host_pressed)
	join_choice_button.pressed.connect(_on_join_choice_pressed)
	join_confirm_button.pressed.connect(_on_join_confirm_pressed)

	lobby_human_button.pressed.connect(func(): Net.request_role(GameState.Role.HUMAN))
	lobby_zombie_button.pressed.connect(func(): Net.request_role(GameState.Role.ZOMBIE))

	Net.connected_to_server.connect(_on_connected_to_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)
	Net.room_joined.connect(_on_room_joined)
	Net.room_error.connect(_on_room_error)
	Net.lobby_updated.connect(_on_lobby_updated)

	start_button.visible = false  # match auto-starts when both roles are picked

	# Launch flags for local testing.
	for a in cmdline:
		if a.begins_with("--role="):
			var r := a.substr("--role=".length())
			_auto_role = GameState.Role.HUMAN if r == "human" else GameState.Role.ZOMBIE
		elif a.begins_with("--join="):
			_auto_join_code = a.substr("--join=".length())
	_auto_host = "--host" in cmdline
	if "--autojoin" in cmdline or _auto_host or _auto_join_code != "":
		_on_multi_pressed()


func _show_panel(panel: Control) -> void:
	for p in [title_panel, mode_panel, role_panel, mp_panel, lobby_panel, join_panel]:
		p.visible = (p == panel)


# --------------------------------------------------------------------- Single player

func _on_single_pressed() -> void:
	Net.leave()  # ensure offline
	_show_panel(role_panel)


func _on_solo_role_chosen(role: GameState.Role) -> void:
	GameState.role = role
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


# ----------------------------------------------------------------------- Multiplayer

## Entering multiplayer connects to the dedicated server; Host/Join unlock once
## connected.
func _on_multi_pressed() -> void:
	_show_panel(mp_panel)
	host_button.disabled = true
	join_choice_button.disabled = true
	mp_status.text = "Connecting to server..."
	if Net.connect_to_server() != OK:
		mp_status.text = "Couldn't start a connection."


func _on_connected_to_server() -> void:
	host_button.disabled = false
	join_choice_button.disabled = false
	mp_status.text = "Host a game, or Join with a code."
	if _auto_host:
		Net.request_host()
	elif _auto_join_code != "":
		Net.request_join(_auto_join_code)


func _on_connection_failed() -> void:
	mp_status.text = "Connection failed — server unreachable."
	host_button.disabled = true
	join_choice_button.disabled = true


func _on_server_disconnected() -> void:
	# Net returns us to the menu; nothing else to do here.
	pass


func _on_host_pressed() -> void:
	mp_status.text = "Creating game..."
	Net.request_host()


func _on_join_choice_pressed() -> void:
	join_title.text = "JOIN GAME"
	code_edit.text = ""
	code_edit.placeholder_text = "Enter room code"
	join_confirm_button.text = "JOIN"
	join_confirm_button.disabled = false
	join_status.text = ""
	_show_panel(join_panel)
	code_edit.grab_focus()


func _on_join_confirm_pressed() -> void:
	var code := code_edit.text.strip_edges()
	if code.is_empty():
		join_status.text = "Enter a room code."
		return
	join_status.text = "Joining..."
	join_confirm_button.disabled = true
	Net.request_join(code)


## In a room now (host or joiner): show the lobby and the code to share.
func _on_room_joined(code: String) -> void:
	_room_code = code
	_show_panel(lobby_panel)
	lobby_title.text = "ROOM CODE:  %s" % code
	lobby_status.text = "Share the code. Pick a role to ready up."
	if _auto_role != -1:
		Net.request_role(_auto_role)


## Host/Join was refused — show the reason on whichever screen is up.
func _on_room_error(message: String) -> void:
	if join_panel.visible:
		join_status.text = message
		join_confirm_button.disabled = false
	else:
		mp_status.text = message


func _on_lobby_updated(human_peer: int, zombie_peer: int) -> void:
	var me := multiplayer.get_unique_id()
	_style_role_button(lobby_human_button, "HUMAN", human_peer, me)
	_style_role_button(lobby_zombie_button, "ZOMBIE", zombie_peer, me)
	var filled := int(human_peer != 0) + int(zombie_peer != 0)
	if filled < 2:
		lobby_status.text = "Code %s  —  pick a role, waiting for both players (%d/2)..." % [_room_code, filled]
	else:
		lobby_status.text = "Both ready — starting!"


## Reflect a role's availability: claimed-by-you, taken, or free.
func _style_role_button(btn: Button, label: String, holder: int, me: int) -> void:
	if holder == me:
		btn.text = "%s  ✓ (you)" % label
		btn.modulate = Color(0.5, 1.5, 0.5)
		btn.disabled = false
	elif holder != 0:
		btn.text = "%s  (taken)" % label
		btn.modulate = Color(1.0, 0.6, 0.6)
		btn.disabled = true
	else:
		btn.text = label
		btn.modulate = Color.WHITE
		btn.disabled = false
