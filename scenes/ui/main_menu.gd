extends Control

## Title → mode select.
## Single player → role select → world (offline).
## Multiplayer → connect to the dedicated server → online lobby (pick a role,
## server-arbitrated) → world once both roles are filled.

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
@onready var lobby_human_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/RoleRow/LobbyHumanButton
@onready var lobby_zombie_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/RoleRow/LobbyZombieButton
@onready var lobby_title: Label = $LobbyPanel/CenterContainer/VBoxContainer/LobbyTitle
@onready var lobby_status: Label = $LobbyPanel/CenterContainer/VBoxContainer/LobbyStatus
@onready var start_button: Button = $LobbyPanel/CenterContainer/VBoxContainer/StartButton
@onready var url_edit: LineEdit = $JoinPanel/CenterContainer/VBoxContainer/IPEdit
@onready var connect_button: Button = $JoinPanel/CenterContainer/VBoxContainer/ConnectButton
@onready var join_status: Label = $JoinPanel/CenterContainer/VBoxContainer/JoinStatus

## Set from a `--role=human|zombie` launch flag — auto-claims it on connect.
var _auto_role: int = -1


## All launch arguments, whether passed after `--` (terminal) or as plain args
## (editor "Run Multiple Instances" config).
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

	lobby_human_button.pressed.connect(func(): Net.request_role(GameState.Role.HUMAN))
	lobby_zombie_button.pressed.connect(func(): Net.request_role(GameState.Role.ZOMBIE))
	connect_button.pressed.connect(_on_connect_pressed)

	Net.connected_to_server.connect(_on_connected_to_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)
	Net.lobby_updated.connect(_on_lobby_updated)

	# Online lobby cosmetics — the match auto-starts, so StartButton is unused.
	lobby_title.text = "LOBBY — pick your role"
	start_button.visible = false

	# Dev shortcut: `godot -- --autojoin [--role=human|--role=zombie]` connects to
	# the local server immediately (two-window testing).
	for a in cmdline:
		if a.begins_with("--role="):
			var r := a.substr("--role=".length())
			_auto_role = GameState.Role.HUMAN if r == "human" else GameState.Role.ZOMBIE
	if "--autojoin" in cmdline:
		_show_panel(join_panel)
		_on_connect_pressed()


func _show_panel(panel: Control) -> void:
	for p in [title_panel, mode_panel, role_panel, mp_panel, lobby_panel, join_panel]:
		p.visible = (p == panel)


func _on_single_pressed() -> void:
	Net.leave()  # ensure offline
	_show_panel(role_panel)


func _on_solo_role_chosen(role: GameState.Role) -> void:
	GameState.role = role
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _on_multi_pressed() -> void:
	url_edit.text = Net.default_server_url()  # localhost in editor, live server when exported
	join_status.text = ""
	connect_button.disabled = false
	_show_panel(join_panel)


func _on_connect_pressed() -> void:
	var url := url_edit.text.strip_edges()
	if Net.connect_to_server(url) != OK:
		join_status.text = "Invalid server address"
		return
	join_status.text = "Connecting..."
	connect_button.disabled = true


func _on_connected_to_server() -> void:
	_show_panel(lobby_panel)
	lobby_status.text = "Connected. Pick a role."
	if _auto_role != -1:
		Net.request_role(_auto_role)


func _on_connection_failed() -> void:
	join_status.text = "Connection failed — is the server running?"
	connect_button.disabled = false
	_show_panel(join_panel)


func _on_server_disconnected() -> void:
	# Net returns us to the menu; just re-enable the connect button.
	connect_button.disabled = false


func _on_lobby_updated(human_peer: int, zombie_peer: int) -> void:
	var me := multiplayer.get_unique_id()
	_style_role_button(lobby_human_button, "HUMAN", human_peer, me)
	_style_role_button(lobby_zombie_button, "ZOMBIE", zombie_peer, me)
	var filled := int(human_peer != 0) + int(zombie_peer != 0)
	if filled < 2:
		lobby_status.text = "Pick a role — waiting for both players (%d/2)..." % filled
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
