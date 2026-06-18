extends Node

## Autoload "Net" — online multiplayer over WebSocket with a dedicated,
## authoritative headless server (launched with --server). Both players connect
## as clients, pick Human/Zombie in a server-arbitrated lobby, and the server
## starts the match. The server simulates the world but is NOT a player.
##
## Local dev:  godot --headless -- --server        (the server)
##             godot -- --autojoin --role=human     (client A)
##             godot -- --autojoin --role=zombie     (client B)
## Production: server on Railway (reads $PORT), clients connect to wss://...

const DEFAULT_PORT := 8910
const DEFAULT_LOCAL_URL := "ws://127.0.0.1:8910"
## The live server, used by every exported build (web or native download).
## After deploying to Railway, paste your public domain here as wss://<domain>
## (no port — Railway proxies 443 -> the container's $PORT).
const PROD_SERVER_URL := "wss://CHANGE-ME.up.railway.app"


## Which server a client should connect to by default. The editor (local dev)
## talks to localhost; any exported build talks to the live server.
func default_server_url() -> String:
	if OS.has_feature("editor"):
		return DEFAULT_LOCAL_URL
	return PROD_SERVER_URL

signal connected_to_server          # client: handshake complete, show lobby
signal connection_failed            # client: could not reach the server
signal server_disconnected          # client: lost the server
## Lobby roster changed. Each arg is the peer id holding that role (0 = free).
signal lobby_updated(human_peer: int, zombie_peer: int)

# Server-only roster: which peer claimed which role.
var _human_peer: int = 0
var _zombie_peer: int = 0
var _match_started: bool = false


# --------------------------------------------------------------- Dedicated server

## Start the authoritative headless server. Reads the port from $PORT (Railway
## sets this) and falls back to DEFAULT_PORT for local testing.
func start_dedicated_server() -> Error:
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
	print("[server] listening on port %d — waiting for two players" % port)
	return OK


func _on_server_peer_connected(id: int) -> void:
	# Two-player game: reject a third connection.
	if multiplayer.get_peers().size() > 2:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	# Send the new client the current roster so its lobby UI is correct.
	_broadcast_lobby()


func _on_server_peer_disconnected(id: int) -> void:
	if id == _human_peer:
		_human_peer = 0
	if id == _zombie_peer:
		_zombie_peer = 0
	_broadcast_lobby()


## Client -> server: request a role. The server is the sole arbiter.
@rpc("any_peer", "reliable")
func claim_role(role: int) -> void:
	if not multiplayer.is_server() or _match_started:
		return
	var sender := multiplayer.get_remote_sender_id()
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


func _broadcast_lobby() -> void:
	_update_lobby.rpc(_human_peer, _zombie_peer)


@rpc("authority", "call_local", "reliable")
func _update_lobby(human_peer: int, zombie_peer: int) -> void:
	lobby_updated.emit(human_peer, zombie_peer)


func _start_match() -> void:
	_match_started = true
	GameState.world_seed = randi()
	GameState.multiplayer_active = true
	print("[server] both roles filled — starting match (human=%d zombie=%d seed=%d)" % [_human_peer, _zombie_peer, GameState.world_seed])
	_assign_role_and_start.rpc_id(_human_peer, GameState.Role.HUMAN, GameState.world_seed)
	_assign_role_and_start.rpc_id(_zombie_peer, GameState.Role.ZOMBIE, GameState.world_seed)
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


# ----------------------------------------------------------------------- Client

## Connect to a dedicated server. `url` is a full ws:// or wss:// address; an
## empty string falls back to the local server for development.
func connect_to_server(url: String = "") -> Error:
	url = url.strip_edges()
	if url.is_empty():
		url = DEFAULT_LOCAL_URL
	elif not (url.begins_with("ws://") or url.begins_with("wss://")):
		# Bare host/IP — assume plain ws on the default port.
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


## Client -> server: ask to take a role (the server validates it).
func request_role(role: int) -> void:
	claim_role.rpc_id(1, role)


func _on_connected() -> void:
	connected_to_server.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	server_disconnected.emit()
	_back_to_menu()


@rpc("authority", "reliable")
func _assign_role_and_start(role: int, world_seed: int) -> void:
	GameState.role = role
	GameState.world_seed = world_seed
	GameState.multiplayer_active = true
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


# ----------------------------------------------------------------------- Shared

## Drop any connection and return to a clean offline state.
func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.multiplayer_active = false
	GameState.is_dedicated_server = false
	_human_peer = 0
	_zombie_peer = 0
	_match_started = false


func _back_to_menu() -> void:
	leave()
	get_tree().paused = false
	if get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://scenes/ui/main_menu.tscn":
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
