extends Node2D

@onready var hud: Control = $HUDLayer/HUD
@onready var game_over_screen: Control = $HUDLayer/GameOverScreen
@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var building_layer: TileMapLayer = $BuildingLayer
@onready var prop_scatter: Node = $PropScatter
@onready var zc_node: ZombieController = $ZombieControllerNode
@onready var zc_camera: Camera2D = $ZCCamera
@onready var entities: Node2D = $Entities
@onready var merge_manager: MergeManager = $MergeManager
@onready var aim_cursor: Control = $HUDLayer/AimCursor
@onready var _effects: Node2D = $Effects
@onready var _blood_canvas: BloodCanvas = $BloodCanvas

const HIT_BURST_SCENE: PackedScene = preload("res://scenes/fx/hit_burst.tscn")

var shooter_scene := preload("res://scenes/shooter/shooter.tscn")
var zombie_scene := preload("res://scenes/zombie/zombie.tscn")
var master_zombie_scene := preload("res://scenes/zombie/master_zombie.tscn")
var npc_scene := preload("res://scenes/npc/npc_human.tscn")
var pickup_scene := preload("res://scenes/pickup/pickup.tscn")
var loot_box_scene := preload("res://scenes/loot_box/loot_box.tscn")

# From Balance.WORLD (assigned in _ready).
var zombie_count: int
var npc_count: int
## Testing switch: skip the fog-of-war overlay entirely.
var fog_enabled: bool

var shooter: CharacterBody2D = null           # this client's own shooter (owning peer)
var shooters: Array[Node] = []                 # server: all shooter nodes
var master_zombie: CharacterBody2D = null
var master_zombie_spawn_pos: Vector2 = Vector2.ZERO

var _client_ready: bool = false
var _spectate_label: Label = null


## Server: nearest living shooter to a point, or null if all are dead.
func nearest_shooter(from: Vector2) -> Node:
	var cands: Array = []
	for s in shooters:
		if is_instance_valid(s):
			cands.append({ "pos": s.global_position, "alive": not s.is_dead })
		else:
			cands.append({ "pos": Vector2.INF, "alive": false })
	var idx := ShooterSelect.nearest_alive_index(from, cands)
	return shooters[idx] if idx >= 0 else null

func _ready() -> void:
	# zombie_count / npc_count are computed from the shooter count on the server
	# (see _apply_population_scaling), after shooters spawn.
	fog_enabled = Balance.WORLD.fog_enabled
	# Shared seed so static scenery (props) looks identical on both peers.
	# Must run BEFORE any other RNG use so both peers consume it in step.
	if GameState.multiplayer_active:
		seed(GameState.world_seed)
	_create_grid()
	prop_scatter.scatter()
	_setup_blood_canvas()

	if multiplayer.is_server():
		# Server (also single player): spawn and simulate everything.
		# Master spawns first so _spawn_shooters() can keep shooters clear of it.
		_spawn_master_zombie()
		_spawn_shooters()
		_apply_population_scaling()
		_spawn_standard_zombies()
		_spawn_npcs()
		_spawn_loot_boxes()
		if GameState.is_dedicated_server:
			# Authoritative server only — no local player, no view to set up.
			# Shooters are driven by their HUMAN clients; the zombie controller
			# is driven by the ZOMBIE client.
			for s in shooters:
				s.controls_enabled = false
			zc_node.deactivate()
		else:
			if shooter != null:
				hud.setup(shooter, master_zombie)
			_setup_fog()
			_apply_role()
	else:
		# Client: entities arrive via the MultiplayerSpawner.
		$MultiplayerSpawner.spawned.connect(_on_entity_spawned)
		for child in entities.get_children():
			_on_entity_spawned(child)


## Client-side: wire up references as replicated entities arrive.
func _on_entity_spawned(node: Node) -> void:
	if node.is_in_group("shooter"):
		if node.get_multiplayer_authority() == multiplayer.get_unique_id():
			shooter = node
	elif node.is_in_group("master_zombie"):
		master_zombie = node
		if _client_ready:
			hud.master_zombie = master_zombie
		if GameState.role == GameState.Role.ZOMBIE:
			zc_camera.global_position = master_zombie.global_position
	# The zombie client owns no shooter, so gate readiness on role, not on shooter.
	var ready_now := (GameState.role == GameState.Role.ZOMBIE and master_zombie != null) \
		or (GameState.role == GameState.Role.HUMAN and shooter != null)
	if not _client_ready and ready_now:
		_client_ready = true
		if shooter != null:
			hud.setup(shooter, master_zombie)
		_setup_fog()
		_apply_role()
		print("[net] client ready - role=", GameState.role, " has_shooter=", shooter != null)


## Configure controls, cameras, fog and UI for this window's role.
func _apply_role() -> void:
	if GameState.role == GameState.Role.HUMAN:
		if shooter == null:
			return  # our shooter hasn't replicated yet
		var shooter_cam: Camera2D = shooter.get_node("Camera2D")
		shooter.controls_enabled = true
		shooter_cam.enabled = true
		shooter_cam.make_current()
		zc_node.deactivate()
		aim_cursor.setup(shooter)
	else:
		# Zombie commander: no owned shooter; drive the RTS camera.
		hud.visible = false
		zc_node.activate()
		zc_camera.make_current()
		if is_instance_valid(master_zombie):
			zc_camera.global_position = master_zombie.global_position
		aim_cursor.teardown()


func _setup_fog() -> void:
	if not fog_enabled:
		return  # testing: fog disabled
	if GameState.role != GameState.Role.HUMAN or shooter == null:
		return  # only the shooter view gets the flashlight fog
	var props: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("occluders"):
		if node is Node2D:
			props.append(node)
	ShooterLighting.setup(self, shooter, ground_layer, building_layer, props)

func _create_grid() -> void:
	var grid := GridDrawer.new()
	grid.z_index = -1
	add_child(grid)

func _spawn_shooters() -> void:
	shooters.clear()
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	var peers: Array[int] = GameState.shooter_peers.duplicate()
	# Solo / single-player: always exactly one local shooter (id 1). Never trust
	# shooter_peers outside an active multiplayer session — a stale list from a
	# previous online match would spawn a shooter this window doesn't own.
	if peers.is_empty() or not GameState.multiplayer_active:
		peers = [1]
	for peer in peers:
		var pos := _random_shooter_spawn(walkable)
		var s := shooter_scene.instantiate()
		s.global_position = pos
		s.name = "Shooter_%d" % peer
		s.set_multiplayer_authority(peer)
		entities.add_child(s, true)
		s.player_died.connect(_on_player_died.bind(s))
		shooters.append(s)
	# This client's own shooter (host or dedicated: authority == local unique id).
	for s in shooters:
		if s.get_multiplayer_authority() == multiplayer.get_unique_id():
			shooter = s
			break
	# Give the master an initial target so it engages immediately.
	if is_instance_valid(master_zombie) and not shooters.is_empty():
		master_zombie.set_target(shooters[0])


## Pick a random walkable tile clear of buildings, away from the zombie spawn and
## other shooters. Relaxes the spacing constraints if the map is tight.
func _random_shooter_spawn(walkable: Array[String]) -> Vector2:
	var min_z: float = Balance.SHOOTER.min_dist_from_zombie_px
	var min_s: float = Balance.SHOOTER.min_dist_from_shooter_px
	var fallback := Vector2(300, 2700)
	var attempts := 0
	while attempts < 400:
		attempts += 1
		var relaxed := attempts > 300  # drop spacing constraints if the map is tight
		var candidate := Vector2i(randi_range(1, 45), randi_range(1, 45))
		var td: TileData = ground_layer.get_cell_tile_data(candidate)
		if td == null or not td.get_custom_data("tile_type") in walkable:
			continue
		if building_layer.get_cell_tile_data(candidate) != null:
			continue
		var world_pos: Vector2 = ground_layer.map_to_local(candidate)
		if not relaxed:
			if world_pos.distance_to(master_zombie_spawn_pos) < min_z:
				continue
			var clash := false
			for s in shooters:
				if is_instance_valid(s) and world_pos.distance_to(s.global_position) < min_s:
					clash = true
					break
			if clash:
				continue
		return world_pos
	return fallback

func _spawn_master_zombie() -> void:
	var tile := _find_clear_road_tile_near(Vector2i(43, 3))
	var spawn_pos := ground_layer.map_to_local(tile) if tile != Vector2i(-1, -1) else Vector2(2700, 300)
	master_zombie = master_zombie_scene.instantiate()
	master_zombie.global_position = spawn_pos
	master_zombie_spawn_pos = spawn_pos
	entities.add_child(master_zombie, true)
	# Shooters don't exist yet at master-spawn time; _spawn_shooters() gives the
	# master its initial target once they're placed.
	master_zombie.master_zombie_died.connect(_on_master_zombie_died)

## Scale enemy/NPC counts to the number of shooter players. Normal zombies grow
## by zombies_per_extra_shooter for each shooter beyond the first; NPCs are
## npc_per_player for every player, counting the zombie commander (shooters + 1).
func _apply_population_scaling() -> void:
	var n := shooters.size()
	zombie_count = Balance.WORLD.base_zombie_count + Balance.WORLD.zombies_per_extra_shooter * (n - 1)
	npc_count = Balance.WORLD.npc_per_player * (n + 1)


func _spawn_standard_zombies() -> void:
	var master_tile := ground_layer.local_to_map(master_zombie.global_position)
	var used: Array[Vector2i] = []
	var spawned := 0
	var attempts := 0
	while spawned < zombie_count and attempts < zombie_count * 60 + 200:
		attempts += 1
		var offset := Vector2i(randi_range(-6, 6), randi_range(-6, 6))
		var tile := _find_clear_walkable_tile_near(master_tile + offset, used)
		if tile == Vector2i(-1, -1):
			continue
		used.append(tile)  # one zombie per tile so solid bodies don't wedge
		var z := zombie_scene.instantiate()
		z.global_position = ground_layer.map_to_local(tile)
		entities.add_child(z, true)
		z.set_target(nearest_shooter(z.global_position))
		z.zombie_died.connect(_on_zombie_died)
		spawned += 1


## A walkable, in-bounds tile near `target`, clear of buildings and not already
## used. get_cell_tile_data returns null off-map, so off-map tiles are skipped.
func _find_clear_walkable_tile_near(target: Vector2i, used: Array) -> Vector2i:
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	for radius in range(0, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var coords := target + Vector2i(dx, dy)
				if coords in used:
					continue
				var td: TileData = ground_layer.get_cell_tile_data(coords)
				if td == null or not td.get_custom_data("tile_type") in walkable:
					continue
				if building_layer.get_cell_tile_data(coords) != null:
					continue
				return coords
	return Vector2i(-1, -1)

func _spawn_npcs() -> void:
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	var spawned := 0
	var attempts := 0
	while spawned < npc_count and attempts < 200:
		attempts += 1
		var candidate := Vector2i(randi_range(1, 45), randi_range(1, 45))
		var td: TileData = ground_layer.get_cell_tile_data(candidate)
		if td == null or not td.get_custom_data("tile_type") in walkable:
			continue
		if building_layer.get_cell_tile_data(candidate) != null:
			continue
		var world_pos: Vector2 = ground_layer.map_to_local(candidate)
		# Keep NPCs at least 5 tiles (320px) from every shooter and all zombies
		var too_close := false
		for s in shooters:
			if is_instance_valid(s) and world_pos.distance_to(s.global_position) < 320.0:
				too_close = true
				break
		if not too_close:
			for z in get_tree().get_nodes_in_group("zombies"):
				if z is Node2D and world_pos.distance_to(z.global_position) < 320.0:
					too_close = true
					break
		if too_close:
			continue
		var npc: Node2D = npc_scene.instantiate()
		npc.global_position = world_pos
		npc.ground_layer = ground_layer
		npc.building_layer = building_layer
		npc.shooter = nearest_shooter(world_pos)
		npc.converted.connect(_on_npc_converted)
		entities.add_child(npc, true)
		spawned += 1

## Scatter closed loot boxes on walkable tiles, clear of buildings, props, the
## shooter spawn, and each other. Server-only; boxes replicate via the spawner.
func _spawn_loot_boxes() -> void:
	for _i in range(Balance.LOOT.box_count):
		var pos := _find_box_spawn()
		if pos == Vector2.INF:
			continue
		var b: Node2D = loot_box_scene.instantiate()
		b.position = pos
		entities.add_child(b, true)


## A walkable tile clear of the shooter spawn and of already-placed boxes.
func _find_box_spawn() -> Vector2:
	for _attempt in range(200):
		var pos := _find_item_spawn(false)
		if pos == Vector2.INF:
			return Vector2.INF
		var clear := true
		for b in get_tree().get_nodes_in_group("loot_boxes"):
			if b.global_position.distance_to(pos) < 96.0:
				clear = false
				break
		if clear:
			return pos
	return Vector2.INF


## Pick a valid landing point for a bursting item near `center`: walkable, not
## in a building, not on a prop/body, and burst_min_sep_px clear of `placed`.
## Falls back to the box center if no clear spot is found.
func loot_landing_spot(center: Vector2, placed: Array) -> Vector2:
	var radius: float = Balance.LOOT.burst_radius_px
	var min_sep: float = Balance.LOOT.burst_min_sep_px
	var space := get_world_2d().direct_space_state
	for _attempt in range(24):
		var ang := randf() * TAU
		var dist: float = max(sqrt(randf()) * radius, min_sep)
		var cand := center + Vector2.from_angle(ang) * dist
		if not _is_loot_tile(cand):
			continue
		var too_near := false
		for q in placed:
			if cand.distance_to(q) < min_sep:
				too_near = true
				break
		if too_near:
			continue
		# Reject if a physical body (prop/shooter/npc/zombie) sits on the point.
		var q := PhysicsPointQueryParameters2D.new()
		q.position = cand
		q.collision_mask = 1
		if not space.intersect_point(q, 1).is_empty():
			continue
		return cand
	return center


## True if `world_pos` is a walkable ground tile with no building over it.
func _is_loot_tile(world_pos: Vector2) -> bool:
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	var tile := ground_layer.local_to_map(ground_layer.to_local(world_pos))
	var td: TileData = ground_layer.get_cell_tile_data(tile)
	if td == null or not td.get_custom_data("tile_type") in walkable:
		return false
	if building_layer.get_cell_tile_data(tile) != null:
		return false
	return true


## Pick a walkable tile for an item. When `near` is true, bias toward tiles
## within ~8 tiles of the shooter; otherwise just keep clear of the spawn.
func _find_item_spawn(near_player: bool = false) -> Vector2:
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	for _attempt in range(200):
		var candidate := Vector2i(randi_range(1, 45), randi_range(1, 45))
		var td: TileData = ground_layer.get_cell_tile_data(candidate)
		if td == null or not td.get_custom_data("tile_type") in walkable:
			continue
		if building_layer.get_cell_tile_data(candidate) != null:
			continue
		var world_pos: Vector2 = ground_layer.map_to_local(candidate)
		if shooter:
			var dist := world_pos.distance_to(shooter.global_position)
			if dist < 200.0:
				continue  # never right on top of the spawn
			if near_player and dist > 512.0:
				continue  # specials stay within ~8 tiles for testing
		return world_pos
	return Vector2.INF

func _on_npc_converted(zombie: Node2D) -> void:
	if zombie.has_signal("zombie_died"):
		zombie.zombie_died.connect(_on_zombie_died)


# --- Zombie Controller commands (sent by whichever peer plays ZOMBIE) ---

@rpc("any_peer", "call_local", "reliable")
func rpc_command_move(zombie_names: Array, world_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	for n in zombie_names:
		var z := entities.get_node_or_null(NodePath(String(n)))
		if z and z.has_method("set_command"):
			z.set_command(world_pos)

signal noise_event(world_pos: Vector2, strength: float)

## Server-side: broadcast a noise (e.g. a gunshot) to every peer.
func emit_noise(world_pos: Vector2, strength: float) -> void:
	if not multiplayer.is_server():
		return
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D and z.has_method("alert_to") \
			and z.global_position.distance_to(world_pos) <= Balance.AGGRO.alert_radius_px:
			z.alert_to(world_pos)
	rpc_noise_event.rpc(world_pos, strength)

@rpc("authority", "call_local", "reliable")
func rpc_noise_event(world_pos: Vector2, strength: float) -> void:
	noise_event.emit(world_pos, strength)

## Server entry point for a cosmetic hit burst; replicates to every peer.
func spawn_hit_fx(preset: int, pos: Vector2, dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	rpc_spawn_hit_fx.rpc(preset, pos, dir)

@rpc("authority", "call_local", "unreliable")
func rpc_spawn_hit_fx(preset: int, pos: Vector2, dir: Vector2) -> void:
	var burst := HIT_BURST_SCENE.instantiate()
	_effects.add_child(burst)
	burst.global_position = pos
	burst.play(preset, dir)

## Size the permanent blood-trail canvas to the ground bounds. Runs on every
## peer so each accumulates an identical trail from the server-authored drips.
func _setup_blood_canvas() -> void:
	var used: Rect2i = ground_layer.get_used_rect()
	var ts: Vector2i = ground_layer.tile_set.tile_size
	var origin: Vector2 = ground_layer.to_global(ground_layer.map_to_local(used.position)) - Vector2(ts) * 0.5
	var size_px := Vector2(used.size.x * ts.x, used.size.y * ts.y)
	_blood_canvas.setup(origin, size_px)

@rpc("authority", "call_local", "unreliable")
func rpc_bleed_drop(world_pos: Vector2) -> void:
	_blood_canvas.stamp(world_pos)

@rpc("any_peer", "call_local", "reliable")
func rpc_set_combat(zombie_names: Array, combat: int) -> void:
	if not multiplayer.is_server():
		return
	for n in zombie_names:
		var z := entities.get_node_or_null(NodePath(String(n)))
		if z and z.has_method("set_combat"):
			z.set_combat(combat)

@rpc("any_peer", "call_local", "reliable")
func rpc_set_movement(zombie_names: Array, mode: int, trigger: int, p1: Vector2, p2: Vector2) -> void:
	if not multiplayer.is_server():
		return
	for n in zombie_names:
		var z := entities.get_node_or_null(NodePath(String(n)))
		if z and z.has_method("set_movement"):
			z.set_movement(mode, trigger, p1, p2)

@rpc("any_peer", "call_local", "reliable")
func rpc_request_merge(zombie_names: Array, type: String) -> void:
	if not multiplayer.is_server():
		return
	var zombies: Array[Node2D] = []
	for n in zombie_names:
		var z := entities.get_node_or_null(NodePath(String(n)))
		if z is Node2D:
			zombies.append(z)
	var required: int = 2 if type == "fast" else 3
	if zombies.size() < required:
		return
	merge_manager.start_merge(zombies, type)

@rpc("any_peer", "call_local", "reliable")
func rpc_cancel_merge() -> void:
	if not multiplayer.is_server():
		return
	merge_manager.cancel_merge()


func _find_clear_road_tile_near(target: Vector2i) -> Vector2i:
	for radius in range(0, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var coords := target + Vector2i(dx, dy)
				var ground_data: TileData = ground_layer.get_cell_tile_data(coords)
				if ground_data == null:
					continue
				var tile_type: String = ground_data.get_custom_data("tile_type")
				if tile_type != "road":
					continue
				var building_data: TileData = building_layer.get_cell_tile_data(coords)
				if building_data != null:
					continue
				return coords
	return Vector2i(-1, -1)

func _on_zombie_died(_zombie: Node2D) -> void:
	pass

func _on_master_zombie_died() -> void:
	if multiplayer.is_server():
		_game_over.rpc(true)

## Server: a shooter died (dead_shooter bound at connect time). Dead shooters
## spectate a living ally; when none remain alive the zombie side wins.
func _on_player_died(dead_shooter: Node) -> void:
	if not multiplayer.is_server():
		return
	var living: Array = []
	for s in shooters:
		if is_instance_valid(s) and not s.is_dead:
			living.append(s)
	if living.is_empty():
		_game_over.rpc(false)   # all shooters dead -> zombie wins
		return
	# Banner for the shooter that just died.
	_spectator_banner.rpc_id(dead_shooter.get_multiplayer_authority())
	# Point every dead shooter's camera at a living ally.
	var tp: NodePath = living[0].get_path()
	for s in shooters:
		if is_instance_valid(s) and s.is_dead:
			_spectator_follow.rpc_id(s.get_multiplayer_authority(), tp)


## Owning client of a just-dead shooter: stop input, show a non-pausing banner.
@rpc("authority", "reliable")
func _spectator_banner() -> void:
	if shooter != null:
		shooter.enter_spectator()
	if _spectate_label == null:
		_spectate_label = Label.new()
		_spectate_label.add_theme_font_size_override("font_size", 28)
		_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_spectate_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_spectate_label.offset_top = 40.0
		$HUDLayer.add_child(_spectate_label)
	_spectate_label.text = "YOU DIED — spectating"
	_spectate_label.visible = true


## A dead shooter's client: follow a living ally's camera.
@rpc("authority", "reliable")
func _spectator_follow(target_path: NodePath) -> void:
	var t := get_node_or_null(target_path)
	if t != null and t.has_node("Camera2D"):
		var cam := t.get_node("Camera2D") as Camera2D
		cam.enabled = true
		cam.make_current()

## Broadcast by the server; each peer renders the message for its own role.
@rpc("authority", "call_local", "reliable")
func _game_over(master_died: bool) -> void:
	# Dedicated server: no UI and never pause the authoritative tree. Reset the
	# room so the same players can rematch (or a new host can take over).
	if multiplayer.is_server() and GameState.is_dedicated_server:
		Net.server_on_match_ended()
		return
	var msg: String
	if master_died:
		msg = "YOU LOSE" if GameState.role == GameState.Role.ZOMBIE else "YOU WIN!"
	else:
		msg = "YOU WIN!" if GameState.role == GameState.Role.ZOMBIE else "YOU DIED"
	_show_game_over(msg)

func _show_game_over(message: String) -> void:
	game_over_screen.show_message(message)

class GridDrawer extends Node2D:
	func _draw() -> void:
		var map_size := 3000
		var spacing := 64
		for x in range(0, map_size + 1, spacing):
			draw_line(Vector2(x, 0), Vector2(x, map_size), Color(1, 1, 1, 0.08), 1.0)
		for y in range(0, map_size + 1, spacing):
			draw_line(Vector2(0, y), Vector2(map_size, y), Color(1, 1, 1, 0.08), 1.0)
		draw_rect(Rect2(0, 0, map_size, map_size), Color(1, 1, 1, 0.3), false, 2.0)
