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
	start_button.pressed.connect(func(): Net.request_start())

	Net.connected_to_server.connect(_on_connected_to_server)
	Net.connection_failed.connect(_on_connection_failed)
	Net.server_disconnected.connect(_on_server_disconnected)
	Net.room_joined.connect(_on_room_joined)
	Net.room_error.connect(_on_room_error)
	Net.lobby_updated.connect(_on_lobby_updated)

	start_button.visible = false  # match auto-starts when both roles are picked

	_apply_zc_style()

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


func _on_lobby_updated(zombie_peer: int, shooter_peers: Array, host_peer: int) -> void:
	var me := multiplayer.get_unique_id()
	# The shooter button represents claiming a shooter slot (up to 4 can hold it).
	var i_am_shooter := me in shooter_peers
	_style_shooter_button(lobby_human_button, shooter_peers.size(), i_am_shooter)
	_style_role_button(lobby_zombie_button, "ZOMBIE", zombie_peer, me)

	var can_start := zombie_peer != 0 and not shooter_peers.is_empty()
	var is_host := me == host_peer
	start_button.visible = is_host
	start_button.disabled = not can_start

	var zlabel := "zombie ✓" if zombie_peer != 0 else "no zombie"
	var tail := ""
	if is_host:
		tail = "  Host: press Start." if can_start else "  Waiting for a zombie + a shooter…"
	else:
		tail = "  Waiting for the host to start…"
	lobby_status.text = "Code %s  —  shooters %d/4, %s.%s" % [_room_code, shooter_peers.size(), zlabel, tail]


## The shooter slot is shared (up to 4). Show count and whether you hold one.
func _style_shooter_button(btn: Button, count: int, mine: bool) -> void:
	if mine:
		btn.text = "SHOOTER  ✓ YOU  %d/4" % count
		_tint_lobby_button(btn, UIStyle.FAST_CYAN, true)
	else:
		btn.text = "JOIN AS SHOOTER  %d/4" % count
		_tint_lobby_button(btn, UIStyle.FAST_CYAN, false)
	btn.disabled = (not mine) and count >= 4


## Reflect a role's availability: claimed-by-you, taken, or free.
func _style_role_button(btn: Button, label: String, holder: int, me: int) -> void:
	if holder == me:
		btn.text = "%s  ✓ YOU" % label
		_tint_lobby_button(btn, UIStyle.INFECTION, true)
		btn.disabled = false
	elif holder != 0:
		btn.text = "%s  — TAKEN" % label
		_tint_lobby_button(btn, UIStyle.WOUND, false)
		btn.disabled = true
	else:
		btn.text = label
		_tint_lobby_button(btn, UIStyle.INFECTION, false)
		btn.disabled = false


# ------------------------------------------------------- ZOMBIE COMMAND styling
# Visual-only. Node tree and wiring stay untouched; widgets are restyled or
# reparented in place (object refs and signal connections survive reparenting).
# Tokens/rules: scripts/ui_style.gd + docs/design_system.md.

func _apply_zc_style() -> void:
	var bg: ColorRect = $Background
	bg.color = UIStyle.ABYSS
	var grid := GameBg.new()
	add_child(grid)
	move_child(grid, 1)  # above the flat ground, below every panel

	_style_title_panel()
	_style_role_panel()
	_style_mp_panel()
	_style_lobby_panel()
	_style_join_panel()


## Title panel becomes the mockup main menu: logo lockup + menu rows.
## SINGLE PLAYER / MULTIPLAYER move up here from the old two-step ModePanel;
## the PLAY button is retired.
func _style_title_panel() -> void:
	var vbox: VBoxContainer = $TitlePanel/CenterContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", 8)
	$TitlePanel/CenterContainer/VBoxContainer/TitleLabel.visible = false
	play_button.visible = false

	var logo := LogoLockup.new()
	logo.lockup_size = "md"
	vbox.add_child(logo)
	vbox.move_child(logo, 0)
	vbox.add_child(MenuWidgets.spacer(26.0))
	vbox.move_child(vbox.get_child(vbox.get_child_count() - 1), 1)

	single_button.reparent(vbox)
	multi_button.reparent(vbox)
	MenuWidgets.menu_row(single_button, "SINGLE PLAYER", "Solo match, choose your faction")
	MenuWidgets.menu_row(multi_button, "MULTIPLAYER", "Host or join a networked match")

	var settings_btn := Button.new()
	vbox.add_child(settings_btn)
	MenuWidgets.menu_row(settings_btn, "SETTINGS", "Controls, interface, profile")
	settings_btn.pressed.connect(_on_settings_pressed)

	vbox.add_child(MenuWidgets.spacer(18.0))
	var footer := MenuWidgets.breadcrumb("2026  ·  V1.0.0")
	footer.add_theme_color_override("font_color", UIStyle.DIM)
	vbox.add_child(footer)


## Solo role select → mockup screen 04 cards.
func _style_role_panel() -> void:
	var hbox: HBoxContainer = $RolePanel/HBoxContainer
	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	role_panel.add_child(center_wrap)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	center_wrap.add_child(v)

	v.add_child(MenuWidgets.breadcrumb("SINGLE PLAYER"))
	v.add_child(MenuWidgets.heading("SELECT YOUR ROLE"))
	v.add_child(MenuWidgets.spacer(14.0))
	hbox.reparent(v)
	hbox.add_theme_constant_override("separation", 16)

	MenuWidgets.role_card(human_button, UIStyle.FAST_CYAN,
		"PLAY AS SHOOTER", "HUMAN SURVIVOR",
		["Eliminate the zombie threat", "Arm NPC survivors", "Hold out against the horde"],
		[["PERSPECTIVE", "HUMAN"], ["WEAPONS", "FIREARMS"], ["VICTORY", "ELIMINATE ALL"]])
	MenuWidgets.role_card(zombie_button, UIStyle.INFECTION,
		"PLAY AS ZOMBIE", "UNDEAD HORDE",
		["Command the horde", "Convert survivors", "Overwhelm defenses"],
		[["PERSPECTIVE", "UNDEAD"], ["WEAPONS", "HORDE"], ["VICTORY", "INFECT ALL"]])

	v.add_child(MenuWidgets.spacer(10.0))
	v.add_child(_back_button(func() -> void: _show_panel(title_panel)))


## Multiplayer hub → mockup screen 05.
func _style_mp_panel() -> void:
	var vbox: VBoxContainer = $MultiplayerPanel/CenterContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", 8)

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.add_child(MenuWidgets.breadcrumb("MAIN MENU  ›  MULTIPLAYER"))
	head.add_child(MenuWidgets.heading("MULTIPLAYER"))
	head.add_child(MenuWidgets.spacer(14.0))
	vbox.add_child(head)
	vbox.move_child(head, 0)

	MenuWidgets.menu_row(host_button, "HOST A GAME", "Create a new match and share the code")
	MenuWidgets.menu_row(join_choice_button, "JOIN A GAME", "Enter a code to join an existing match")
	MenuWidgets.status_line(mp_status)
	vbox.add_child(MenuWidgets.spacer(10.0))
	vbox.add_child(_back_button(_on_mp_back))


## Lobby → room code heading, role buttons, mono status, primary START.
func _style_lobby_panel() -> void:
	var vbox: VBoxContainer = $LobbyPanel/CenterContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", 12)

	var crumb := MenuWidgets.breadcrumb("MULTIPLAYER  ›  LOBBY")
	vbox.add_child(crumb)
	vbox.move_child(crumb, 0)

	lobby_title.theme_type_variation = "HeadingLabel"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_title.add_theme_color_override("font_color", UIStyle.INFECTION)

	var row: HBoxContainer = $LobbyPanel/CenterContainer/VBoxContainer/RoleRow
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for btn: Button in [lobby_human_button, lobby_zombie_button]:
		btn.custom_minimum_size = Vector2(230, 54)

	MenuWidgets.status_line(lobby_status)
	MenuWidgets.primary_button(start_button)
	vbox.add_child(MenuWidgets.spacer(10.0))
	vbox.add_child(_back_button(_on_lobby_back))


## Join-by-code → mockup screen 07 (private).
func _style_join_panel() -> void:
	var vbox: VBoxContainer = $JoinPanel/CenterContainer/VBoxContainer
	vbox.add_theme_constant_override("separation", 12)

	var crumb := MenuWidgets.breadcrumb("MULTIPLAYER  ›  JOIN A GAME")
	vbox.add_child(crumb)
	vbox.move_child(crumb, 0)

	join_title.theme_type_variation = "HeadingLabel"
	join_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.custom_minimum_size = Vector2(280, 48)
	code_edit.add_theme_font_size_override("font_size", 20)

	join_confirm_button.custom_minimum_size = Vector2(280, 44)
	MenuWidgets.status_line(join_status)
	vbox.add_child(MenuWidgets.spacer(10.0))
	vbox.add_child(_back_button(func() -> void: _show_panel(mp_panel)))


func _on_settings_pressed() -> void:
	var s := SettingsMenu.new()
	add_child(s)  # full-screen, sits above every panel
	s.closed.connect(s.queue_free)


# ------------------------------------------------------------- back navigation

## ESC steps back one screen (the settings overlay handles its own ESC first).
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if role_panel.visible:
		_show_panel(title_panel)
	elif join_panel.visible:
		_show_panel(mp_panel)
	elif mp_panel.visible:
		_on_mp_back()
	elif lobby_panel.visible:
		_on_lobby_back()
	else:
		return
	get_viewport().set_input_as_handled()


## Styled "‹ BACK" row for a menu panel.
func _back_button(cb: Callable) -> Button:
	var b := Button.new()
	b.text = "‹  BACK"
	b.custom_minimum_size = Vector2(140, 34)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b


func _on_mp_back() -> void:
	Net.leave()  # drop the server connection; re-entering reconnects
	_show_panel(title_panel)


func _on_lobby_back() -> void:
	# Tell the server we're leaving the room before dropping the connection
	# (same order leave_to_menu uses), so the lobby roster updates for others.
	if multiplayer.multiplayer_peer != null \
			and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		Net.leave_room.rpc_id(1)
		await get_tree().process_frame
	Net.leave()
	_show_panel(title_panel)


## Lobby role button tint: claimed-by-you = solid accent frame, otherwise flat.
func _tint_lobby_button(btn: Button, accent: Color, claimed: bool) -> void:
	btn.modulate = Color.WHITE
	if claimed:
		btn.add_theme_color_override("font_color", accent)
		btn.add_theme_stylebox_override("normal",
			UIStyle.box(UIStyle.fade(accent, 0.08), accent, UIStyle.fade(accent, 0.15), 6))
	else:
		btn.remove_theme_color_override("font_color")
		btn.remove_theme_stylebox_override("normal")
	btn.add_theme_color_override("font_disabled_color", UIStyle.fade(accent, 0.55))
