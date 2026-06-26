extends CharacterBody2D

## Human NPC in a zombie apocalypse.
## Behaviour: sneaks between hiding spots (walkable tiles next to buildings),
## hides 10-20s, then meanders via random waypoints to a new spot.
## A zombie touching it starts an inevitable 5s conversion (freeze + pulse +
## progress bar), then a standard zombie spawns in its place.
## The shooter touching it makes it follow him permanently, ~1 tile behind.
## Bullets can kill it at any time — death spawns no zombie.
##
## Multiplayer: all logic runs on the server. Clients render the synced
## position/state/convert_progress (visuals in _process).

signal converted(zombie: Node2D)

const ZOMBIE_SCENE := preload("res://scenes/zombie/zombie.tscn")

# All tuning comes from Balance.NPC (assigned in _ready).
var speed: float
var max_hp: int
var hide_min: float
var hide_max: float
var hide_radius: int
var CONVERT_DURATION: float
var FOLLOW_DISTANCE: float
var FOLLOW_DEADZONE: float
var NPC_VISION_PX: float    # how far it spots zombies
var MUZZLE_OFFSET: float    # spawn bullets past the NPC's own body

const WALKABLE: Array[String] = ["road", "sidewalk", "grass", "parking"]

var hp: int

# Weapon handed over by the shooter (server-side). weapon_id == -1 means unarmed.
var weapon_id: int = -1
var weapon_mag: int = 0
var weapon_total: int = 0
var _npc_can_shoot: bool = true
var _npc_reloading: bool = false

# Armed-combat state (server-side). _engaged latches on the player's spark and
# holds while a zombie is visible; recoil mirrors the player's shape with NPC knobs.
var _engaged: bool = false
var _recoil: float = 0.0
var _recoil_elapsed: float = 0.0
var _recoil_recover: float = 0.0

# References injected by the spawner (world.gd, server only)
var ground_layer: TileMapLayer
var building_layer: TileMapLayer
var shooter: Node2D

enum State { HIDDEN, RELOCATING, FOLLOWING, CONVERTING }
var state: State = State.HIDDEN

## Synced conversion visual: -1 = not converting, 0..1 = progress.
var convert_progress: float = -1.0

var _hide_timer: float = 0.0
var _waypoints: Array[Vector2] = []
var _convert_timer: float = 0.0
var _last_shooter_dir: Vector2 = Vector2.RIGHT
var _progress_bar: Node2D = null

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var conversion_zone: Area2D = $ConversionZone
@onready var npc_shoot_cooldown: Timer = $NpcShootCooldown


func _ready() -> void:
	var b: Dictionary = Balance.NPC
	speed = b.speed
	max_hp = b.max_hp
	hide_min = b.hide_min
	hide_max = b.hide_max
	hide_radius = b.hide_radius
	CONVERT_DURATION = b.convert_duration
	FOLLOW_DISTANCE = b.follow_distance
	FOLLOW_DEADZONE = b.follow_deadzone
	NPC_VISION_PX = b.vision_px
	MUZZLE_OFFSET = b.muzzle_offset
	hp = max_hp
	# Logic runs on the server only (true in single player too)
	set_physics_process(multiplayer.is_server())
	if multiplayer.is_server():
		nav_agent.path_desired_distance = 8.0
		nav_agent.target_desired_distance = 8.0
		conversion_zone.body_entered.connect(_on_zone_body_entered)
		npc_shoot_cooldown.timeout.connect(_on_npc_shoot_cooldown_timeout)
		# Short randomized first wait so NPCs don't all move at once
		_start_hidden(randf_range(1.0, 4.0))


## Conversion visuals — every peer, driven by synced state/convert_progress.
func _process(_delta: float) -> void:
	if state == State.CONVERTING and convert_progress >= 0.0:
		if _progress_bar == null:
			_progress_bar = ConversionProgressBar.new()
			add_child(_progress_bar)
			_progress_bar.position = Vector2(0, -24)
		_progress_bar.progress = convert_progress
		var pulse: float = 0.6 + 0.4 * abs(sin(Time.get_ticks_msec() / 1000.0 * 4.0))
		modulate = Color(pulse, pulse, pulse, 1.0)
	elif _progress_bar != null:
		_progress_bar.queue_free()
		_progress_bar = null
		modulate = Color.WHITE


func _physics_process(delta: float) -> void:
	match state:
		State.CONVERTING:
			_process_converting(delta)
		State.HIDDEN:
			_hide_timer -= delta
			if _hide_timer <= 0.0:
				_plan_relocation()
		State.RELOCATING:
			if nav_agent.is_navigation_finished():
				if _waypoints.is_empty():
					_start_hidden(randf_range(hide_min, hide_max))
				else:
					nav_agent.target_position = _waypoints.pop_front()
			else:
				_nav_move()
		State.FOLLOWING:
			_process_following()
			if weapon_id != -1:
				_process_shooting(delta)


func _nav_move() -> void:
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	velocity = (next_pos - global_position).normalized() * speed
	move_and_slide()


func _start_hidden(duration: float) -> void:
	state = State.HIDDEN
	_hide_timer = duration
	_waypoints.clear()
	velocity = Vector2.ZERO


## True if the tile is a walkable ground type with no building on it.
func _is_walkable(tile: Vector2i) -> bool:
	if ground_layer == null:
		return false
	var td: TileData = ground_layer.get_cell_tile_data(tile)
	if td == null or not td.get_custom_data("tile_type") in WALKABLE:
		return false
	if building_layer and building_layer.get_cell_tile_data(tile) != null:
		return false
	return true


## A hiding tile is walkable and adjacent to at least one building tile.
func _is_hiding_tile(tile: Vector2i) -> bool:
	if not _is_walkable(tile):
		return false
	if building_layer == null:
		return false
	for n in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if building_layer.get_cell_tile_data(tile + n) != null:
			return true
	return false


func _find_hiding_spot() -> Vector2i:
	var current_tile: Vector2i = ground_layer.local_to_map(
		ground_layer.to_local(global_position)
	)
	for _attempt in range(40):
		var candidate := current_tile + Vector2i(
			randi_range(-hide_radius, hide_radius),
			randi_range(-hide_radius, hide_radius)
		)
		if _is_hiding_tile(candidate):
			return candidate
	return Vector2i(-1, -1)


## Build a meandering waypoint path to a new hiding spot.
func _plan_relocation() -> void:
	if ground_layer == null:
		_start_hidden(randf_range(1.0, 3.0))
		return

	var spot := _find_hiding_spot()
	if spot == Vector2i(-1, -1):
		_start_hidden(randf_range(1.0, 3.0))
		return

	var start_tile: Vector2i = ground_layer.local_to_map(
		ground_layer.to_local(global_position)
	)
	_waypoints.clear()

	# 2-4 intermediate waypoints jittered off the straight line, so the path
	# looks like nervous wandering instead of a beeline
	var steps := randi_range(2, 4)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var line_tile := Vector2i((Vector2(start_tile) + (Vector2(spot) - Vector2(start_tile)) * t).round())
		for _try in range(8):
			var jittered := line_tile + Vector2i(randi_range(-3, 3), randi_range(-3, 3))
			if _is_walkable(jittered):
				_waypoints.append(ground_layer.map_to_local(jittered))
				break

	_waypoints.append(ground_layer.map_to_local(spot))
	state = State.RELOCATING
	nav_agent.target_position = _waypoints.pop_front()


func _process_following() -> void:
	if not is_instance_valid(shooter):
		_start_hidden(randf_range(1.0, 3.0))
		return

	if "velocity" in shooter and shooter.velocity.length() > 5.0:
		_last_shooter_dir = shooter.velocity.normalized()

	var follow_point: Vector2 = shooter.global_position - _last_shooter_dir * FOLLOW_DISTANCE
	if global_position.distance_to(follow_point) < FOLLOW_DEADZONE:
		velocity = Vector2.ZERO
		return

	nav_agent.target_position = follow_point
	if not nav_agent.is_navigation_finished():
		_nav_move()
	else:
		velocity = Vector2.ZERO


## Called by the shooter when handing over its special weapon (server-side).
func receive_weapon(id: int, total: int) -> void:
	weapon_id = id
	weapon_total = total
	var w := Weapons.get_data(id)
	weapon_mag = min(w.mag_size, total)
	_npc_can_shoot = true
	_npc_reloading = false


## Fire at the nearest zombie, but only while the shooter is also firing, and
## with a deliberately sloppy aim. Mirrors the shooter's mag/reload timing.
func _process_shooting(delta: float) -> void:
	# Recoil decays every armed frame.
	_recoil_elapsed += delta
	_recoil = NpcAim.recoil_after(Balance.NPC.recoil_initial, _recoil_elapsed, _recoil_recover)

	# --- Engagement latch: a visible zombie is required to stay engaged. ---
	var target := _nearest_zombie(NPC_VISION_PX)
	if target == null:
		_engaged = false
		return
	if not _engaged:
		# Spark: the player firing near a visible zombie engages us; after that we
		# fight on our own until no zombie is visible.
		if is_instance_valid(shooter) and shooter.has_method("is_firing") and shooter.is_firing():
			_engaged = true
		else:
			return

	# --- Fire (gated by ammo / reload / fire-rate cap). ---
	if _npc_reloading or not _npc_can_shoot or weapon_mag <= 0:
		return

	var w := Weapons.get_data(weapon_id)
	var base_angle: float = (target.global_position - global_position).angle()
	# Spawn past our own collider so the NPC never shoots itself.
	var origin: Vector2 = global_position + Vector2.from_angle(base_angle) * MUZZLE_OFFSET
	var cursor: Vector2 = target.global_position
	var moving: bool = velocity.length() > 5.0
	var debuff: float = NpcAim.aim_debuff(Balance.NPC, moving, hp, max_hp, _recoil)
	var coeff: float = AimModel.spread_coeff(w, debuff, 0.0)
	var radius: float = coeff * origin.distance_to(cursor)
	Weapons.fire(get_parent(), origin, cursor, radius, w)

	# Per-shot recoil kick (decays over recover-factor x damage-units seconds).
	var dmg_units: float = (w.damage * w.pellets) / Balance.NPC.dmg_ref
	_recoil_elapsed = 0.0
	_recoil_recover = Balance.NPC.recoil_recover_factor * dmg_units

	weapon_mag -= 1
	weapon_total -= 1
	_npc_can_shoot = false
	if weapon_total <= 0:
		weapon_id = -1  # weapon spent
		return
	if weapon_mag <= 0:
		_npc_reloading = true
		npc_shoot_cooldown.start(w.reload_time)
	else:
		npc_shoot_cooldown.start(maxf(w.cooldown, Balance.NPC.min_shot_interval))


func _on_npc_shoot_cooldown_timeout() -> void:
	if _npc_reloading:
		var w := Weapons.get_data(weapon_id)
		var reserve: int = weapon_total - weapon_mag
		weapon_mag += min(w.mag_size - weapon_mag, reserve)
		_npc_reloading = false
	_npc_can_shoot = true


func _nearest_zombie(max_dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D and is_instance_valid(z):
			var d := global_position.distance_to(z.global_position)
			if d < best_d:
				best_d = d
				best = z
	return best


func _on_zone_body_entered(body: Node2D) -> void:
	if state == State.CONVERTING:
		return  # Conversion is inevitable — ignore further contact
	if body.is_in_group("zombies"):
		_start_conversion()
	elif body.is_in_group("shooter") and state != State.FOLLOWING:
		state = State.FOLLOWING


func _start_conversion() -> void:
	state = State.CONVERTING
	_convert_timer = 0.0
	convert_progress = 0.0
	velocity = Vector2.ZERO
	nav_agent.target_position = global_position


func _process_converting(delta: float) -> void:
	velocity = Vector2.ZERO
	_convert_timer += delta
	convert_progress = _convert_timer / CONVERT_DURATION
	if _convert_timer >= CONVERT_DURATION:
		_finish_conversion()


func _finish_conversion() -> void:
	var new_zombie: Node2D = ZOMBIE_SCENE.instantiate()
	new_zombie.global_position = global_position
	get_parent().add_child(new_zombie, true)
	if is_instance_valid(shooter) and new_zombie.has_method("set_target"):
		new_zombie.set_target(shooter)
	converted.emit(new_zombie)
	queue_free()


## Called by bullets (server-side). Death never spawns a zombie — shooting a
## converting NPC before the bar fills is the only way to stop a conversion.
func take_damage(amount: float) -> void:
	hp -= int(amount)
	if hp <= 0:
		queue_free()


## Small progress bar drawn above the NPC during conversion.
## Mirrors MergeManager.MergeProgressBar, sized for the 32x32 NPC.
class ConversionProgressBar extends Node2D:
	var progress: float = 0.0
	const BAR_WIDTH: float = 32.0
	const BAR_HEIGHT: float = 4.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var bg_rect := Rect2(-BAR_WIDTH / 2, -BAR_HEIGHT / 2, BAR_WIDTH, BAR_HEIGHT)
		draw_rect(bg_rect, Color(0.2, 0.2, 0.2, 0.8))
		var fill_width: float = BAR_WIDTH * clampf(progress, 0.0, 1.0)
		var fill_rect := Rect2(-BAR_WIDTH / 2, -BAR_HEIGHT / 2, fill_width, BAR_HEIGHT)
		draw_rect(fill_rect, Color(1.0, 0.8, 0.0, 1.0))
		draw_rect(bg_rect, Color.WHITE, false, 1.0)
