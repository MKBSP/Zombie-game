extends Node

## Autoload "Net" — online multiplayer over WebSocket with a dedicated,
## authoritative headless server (launched with --server). Players connect as
## clients, then either HOST a game (server makes a room + share code) or JOIN
## one with that code. Inside a room each player picks Human/Zombie (the server
## arbitrates) and the server starts the match. The server is NOT a player.
##
## Single active game for now: the server hosts one room at a time. Concurrent
## lobbies / ranked matchmaking come later.
##
## Local dev:  godot --headless -- --server --dev      (the server)
##             godot -- --autojoin --host --role=human  (host client)
##             godot -- --autojoin --join=CODE --role=zombie (joiner)
## Production: server on Railway (reads $PORT), clients connect to wss://...

const DEFAULT_PORT := 8910
const DEFAULT_LOCAL_URL := "ws://127.0.0.1:8910"
## The live server, used by every exported build (web or native download).
const PROD_SERVER_URL := "wss://zombie-game-production-2dad.up.railway.app"

## Room-code alphabet — no ambiguous chars (0/O, 1/I).
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 4

signal connected_to_server          # client: handshake complete
signal connection_failed            # client: could not reach the server
signal server_disconnected          # client: lost the server
signal room_joined(code: String)    # client: now in a room (as host or joiner)
signal room_error(message: String)  # client: host/join was refused
## Lobby roster changed. Each arg is the peer id holding that role (0 = free).
signal lobby_updated(human_peer: int, zombie_peer: int)
## The room ended out from under this client (opponent left, etc.).
signal room_closed(reason: String)

# Server-only room state (single active room).
var _room_code: String = ""
var _members: Array[int] = []   # peers in the room (max 2); _members[0] is host
var _human_peer: int = 0
var _zombie_peer: int = 0
var _match_started: bool = false
var _match_over: bool = false   # match finished; players choosing rematch/quit


## Which server a client connects to by default: localhost in the editor,
## the live server in any exported build.
func default_server_url() -> String:
	if OS.has_feature("editor"):
		return DEFAULT_LOCAL_URL
	return PROD_SERVER_URL


# --------------------------------------------------------------- Dedicated server

## Start the authoritative headless server. Reads the port from $PORT (Railway
## sets this) and falls back to DEFAULT_PORT for local testing.
func start_dedicated_server() -> Error:
	# Idempotent: re-entering main_menu._ready() (with --server) after a match
	# must not recreate the peer and drop every connection.
	if GameState.is_dedicated_server and multiplayer.has_multiplayer_peer():
		return OK
	var port := DEFAULT_PORT
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		port = env_port.to_int()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("[server] failed to listen on port %d (err %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	GameState.multiplayer_active = true
	GameState.is_dedicated_server = true
	multiplayer.peer_connected.connect(_on_server_peer_connected)
	multiplayer.peer_disconnected.connect(_on_server_peer_disconnected)
	print("[server] listening on port %d — waiting for a host" % port)
	return OK


func _on_server_peer_connected(_id: int) -> void:
	# Connections are allowed freely; room membership is gated by host/join.
	pass


func _on_server_peer_disconnected(id: int) -> void:
	_handle_member_left(id)


## A member left (disconnect or explicit leave). End the session sensibly:
## an empty room closes; during or after a match any departure closes the room
## and sends the other player home; in the lobby only the host leaving closes it
## (a joiner leaving just frees their slot so the host can keep waiting).
func _handle_member_left(id: int) -> void:
	if id not in _members:
		return
	var was_host := _members[0] == id
	_members.erase(id)
	if id == _human_peer:
		_human_peer = 0
	if id == _zombie_peer:
		_zombie_peer = 0
	if _members.is_empty():
		_close_room()
		return
	if _match_started or _match_over or was_host:
		var remaining := _members.duplicate()
		_close_room()
		for m in remaining:
			_room_closed.rpc_id(m, "The other player left.")
	else:
		_broadcast_lobby()


## Client -> server: create the room. Single-room server, so refuse if busy.
@rpc("any_peer", "reliable")
func create_room() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _room_code != "":
		_room_error.rpc_id(sender, "A game is already running. Try Join instead.")
		return
	_room_code = _gen_code()
	_members = [sender]
	_human_peer = 0
	_zombie_peer = 0
	_match_started = false
	_match_over = false
	print("[server] room created: %s (host=%d)" % [_room_code, sender])
	_room_joined.rpc_id(sender, _room_code)
	_broadcast_lobby()


## Client -> server: join the room matching `code`.
@rpc("any_peer", "reliable")
func join_room(code: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var c := code.strip_edges().to_upper()
	if _room_code == "":
		_room_error.rpc_id(sender, "No game is being hosted. Click Host to start one.")
		return
	if c != _room_code:
		_room_error.rpc_id(sender, "No game found with code %s." % c)
		return
	if sender not in _members and _members.size() >= 2:
		_room_error.rpc_id(sender, "That game is full.")
		return
	if sender not in _members:
		_members.append(sender)
	print("[server] peer %d joined room %s (%d/2)" % [sender, _room_code, _members.size()])
	_room_joined.rpc_id(sender, _room_code)
	_broadcast_lobby()


## Client -> server: request a role within the room. The server is the arbiter.
@rpc("any_peer", "reliable")
func claim_role(role: int) -> void:
	if not multiplayer.is_server() or _match_started or _match_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in _members:
		return
	# Release any role the sender currently holds (lets them switch).
	if _human_peer == sender:
		_human_peer = 0
	if _zombie_peer == sender:
		_zombie_peer = 0
	if role == GameState.Role.HUMAN and _human_peer == 0:
		_human_peer = sender
	elif role == GameState.Role.ZOMBIE and _zombie_peer == 0:
		_zombie_peer = sender
	# else: requested role is held by the other peer — ignore the request.
	_broadcast_lobby()
	if _human_peer != 0 and _zombie_peer != 0:
		_start_match()


## Client -> server: restart with the same two players and the same roles.
@rpc("any_peer", "reliable")
func rematch() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in _members:
		return
	if _match_started:
		return  # already restarting — both players may click Play Again
	if _human_peer == 0 or _zombie_peer == 0:
		return  # need both roles still present
	_start_match()


## Client -> server: leave the room (quit to menu).
@rpc("any_peer", "reliable")
func leave_room() -> void:
	if not multiplayer.is_server():
		return
	_handle_member_left(multiplayer.get_remote_sender_id())


func _broadcast_lobby() -> void:
	for m in _members:
		_update_lobby.rpc_id(m, _human_peer, _zombie_peer)


func _start_match() -> void:
	_match_started = true
	_match_over = false
	GameState.world_seed = randi()
	GameState.multiplayer_active = true
	print("[server] both roles filled — starting match (human=%d zombie=%d seed=%d)" % [_human_peer, _zombie_peer, GameState.world_seed])
	_assign_role_and_start.rpc_id(_human_peer, GameState.Role.HUMAN, GameState.world_seed)
	_assign_role_and_start.rpc_id(_zombie_peer, GameState.Role.ZOMBIE, GameState.world_seed)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


## Server: a match just ended. Keep the room + roles so the players can rematch,
## but mark it finished and drop the finished world (dedicated server goes idle
## until a rematch or a brand-new host arrives).
func server_on_match_ended() -> void:
	if not multiplayer.is_server():
		return
	_match_started = false
	_match_over = true
	if GameState.is_dedicated_server:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _close_room() -> void:
	_room_code = ""
	_members = []
	_human_peer = 0
	_zombie_peer = 0
	_match_started = false
	_match_over = false
	print("[server] room closed — waiting for a host")


func _gen_code() -> String:
	var s := ""
	for _i in CODE_LENGTH:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s


# ----------------------------------------------------------------------- Client

## Connect to a dedicated server. Empty `url` uses the default (localhost in the
## editor, the live server when exported). Bare host/IP gets a ws:// prefix.
func connect_to_server(url: String = "") -> Error:
	url = url.strip_edges()
	if url.is_empty():
		url = default_server_url()
	elif not (url.begins_with("ws://") or url.begins_with("wss://")):
		url = "ws://%s:%d" % [url, DEFAULT_PORT]
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	GameState.multiplayer_active = true
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


## Client -> server: host a new game.
func request_host() -> void:
	create_room.rpc_id(1)


## Client -> server: join the game with `code`.
func request_join(code: String) -> void:
	join_room.rpc_id(1, code)


## Client -> server: take a role inside the room.
func request_role(role: int) -> void:
	claim_role.rpc_id(1, role)


## Client -> server: rematch with the same players/roles.
func request_rematch() -> void:
	rematch.rpc_id(1)


## Leave the current room (if any) and return to the main menu. Safe in both
## single-player and multiplayer; the explicit leave_room RPC frees the server's
## room immediately rather than waiting on a (possibly slow) WebSocket close.
func leave_to_menu() -> void:
	if GameState.multiplayer_active and not multiplayer.is_server():
		leave_room.rpc_id(1)
		await get_tree().process_frame  # let the RPC flush before we drop the peer
	leave()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_connected() -> void:
	connected_to_server.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	server_disconnected.emit()
	_back_to_menu()


@rpc("authority", "reliable")
func _room_joined(code: String) -> void:
	_room_code = code
	room_joined.emit(code)


@rpc("authority", "reliable")
func _room_error(message: String) -> void:
	room_error.emit(message)


@rpc("authority", "reliable")
func _update_lobby(human_peer: int, zombie_peer: int) -> void:
	lobby_updated.emit(human_peer, zombie_peer)


@rpc("authority", "reliable")
func _assign_role_and_start(role: int, world_seed: int) -> void:
	GameState.role = role
	GameState.world_seed = world_seed
	GameState.multiplayer_active = true
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


## Server -> client: the room ended (opponent left). Return to the menu.
@rpc("authority", "reliable")
func _room_closed(reason: String) -> void:
	room_closed.emit(reason)
	print("[net] room closed: ", reason)
	_back_to_menu()


# ----------------------------------------------------------------------- Shared

## Drop any connection and return to a clean offline state.
func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.multiplayer_active = false
	GameState.is_dedicated_server = false
	_room_code = ""
	_members = []
	_human_peer = 0
	_zombie_peer = 0
	_match_started = false
	_match_over = false


func _back_to_menu() -> void:
	leave()
	get_tree().paused = false
	if get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://scenes/ui/main_menu.tscn":
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
