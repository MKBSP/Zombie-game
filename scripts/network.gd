extends Node

## Autoload "Net" — WebSocket multiplayer lifecycle for 2-player games.
## The host is the authoritative server; the joiner gets the opposite role.
## Phase 6 (online) reuses this with a relay URL instead of localhost.

const PORT := 8910

signal player_joined
signal player_left
signal connection_failed


func host() -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	GameState.multiplayer_active = true
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func join(ip: String = "127.0.0.1") -> Error:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client("ws://%s:%d" % [ip, PORT])
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	GameState.multiplayer_active = true
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


## Drop any connection and return to clean offline state.
func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.multiplayer_active = false


## Host calls this from the lobby once a player has joined and a role is chosen.
func start_game(host_role: GameState.Role) -> void:
	GameState.role = host_role
	GameState.world_seed = randi()
	var client_role: GameState.Role = (
		GameState.Role.ZOMBIE if host_role == GameState.Role.HUMAN else GameState.Role.HUMAN
	)
	_assign_role_and_start.rpc(client_role, GameState.world_seed)
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


@rpc("authority", "reliable")
func _assign_role_and_start(role: GameState.Role, world_seed: int) -> void:
	GameState.role = role
	GameState.world_seed = world_seed
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _on_peer_connected(id: int) -> void:
	# 2-player game: reject extra joiners
	if multiplayer.get_peers().size() > 1:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	player_joined.emit()


func _on_peer_disconnected(_id: int) -> void:
	player_left.emit()
	_back_to_menu()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	player_left.emit()
	_back_to_menu()


func _back_to_menu() -> void:
	leave()
	get_tree().paused = false
	if get_tree().current_scene and get_tree().current_scene.scene_file_path != "res://scenes/ui/main_menu.tscn":
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
