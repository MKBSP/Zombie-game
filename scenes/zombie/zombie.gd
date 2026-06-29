extends CharacterBody2D

# Stats come from Balance, chosen by group (standard / fast / fat). See _ready().
var speed: float
var max_hp: int
var contact_dps: float
var vision_range: int
var _contact_px: float
var damage_per_hit: int
var attack_interval: float
var _attack_cooldown: float = 0.0

enum Stance { AGGRESSIVE, HOLD, PATROL_ATTACK, PATROL_FLEE, SKITTISH, FLEE_POINT }
var stance: int = Stance.AGGRESSIVE
var patrol_a: Vector2 = Vector2.ZERO
var patrol_b: Vector2 = Vector2.ZERO
var flee_point: Vector2 = Vector2.ZERO
var _patrol_leg: int = 0
var _no_enemy_timer: float = 0.0
var _alert_point: Vector2 = Vector2.ZERO
var _alert_timer: float = 0.0
var _merging: bool = false
var _merge_target: Vector2 = Vector2.ZERO

var command_mode: bool = false
var command_target: Vector2 = Vector2.ZERO
var is_selected: bool = false
var hp: int
var is_dead: bool = false
var target: Node2D = null

## Synced merge visual state: -1 = not merging, 0..1 = lock progress.
## Set by MergeManager on the server; rendered locally on every peer.
var merge_progress: float = -1.0
var _merge_bar: Node2D = null
var _health_bar: HealthBar = null
var _last_hp_seen: int = -1

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

signal zombie_died(zombie: Node2D)
signal took_damage(zombie: Node2D, amount: int)

func _ready() -> void:
	# Pick the stat block by group: standard / fast / fat all use this script.
	var stats: Dictionary = Balance.ZOMBIE
	if is_in_group("fast_zombie"):
		stats = Balance.FAST
	elif is_in_group("fat_zombie"):
		stats = Balance.FAT
	speed = stats.speed
	max_hp = stats.max_hp
	contact_dps = stats.contact_dps
	vision_range = stats.vision
	_contact_px = stats.contact_px
	damage_per_hit = stats.damage_per_hit
	attack_interval = stats.attack_interval
	scale = Vector2(stats.scale, stats.scale)
	hp = max_hp
	_health_bar = HealthBar.new()
	_health_bar.position = Vector2(0, -28)
	_health_bar.z_index = 20
	add_child(_health_bar)
	_health_bar.visible = false
	# AI/simulation runs on the server only (true in single player too)
	set_physics_process(multiplayer.is_server())
	var sep: Dictionary = Balance.SEPARATION
	nav_agent.avoidance_enabled = true
	nav_agent.radius = sep.agent_radius
	nav_agent.neighbor_distance = sep.neighbor_distance
	nav_agent.max_neighbors = sep.max_neighbors
	nav_agent.time_horizon_agents = sep.time_horizon
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	await get_tree().physics_frame
	nav_agent.target_position = global_position  # Stay put initially

## Merge visuals — runs on every peer from the synced merge_progress.
func _process(_delta: float) -> void:
	if merge_progress >= 0.0:
		if _merge_bar == null:
			_merge_bar = MergeManager.MergeProgressBar.new()
			add_child(_merge_bar)
			_merge_bar.position = Vector2(0, -30)
		_merge_bar.progress = merge_progress
		var pulse: float = 0.6 + 0.4 * abs(sin(Time.get_ticks_msec() / 1000.0 * 4.0))
		modulate = Color(pulse, pulse, pulse, 1.0)
	elif _merge_bar != null:
		_merge_bar.queue_free()
		_merge_bar = null
		modulate = Color.WHITE
	# Refresh the health bar when replicated hp changes (clients see this too).
	if _health_bar and hp != _last_hp_seen:
		_last_hp_seen = hp
		_refresh_health_bar()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_check_contact_damage(delta)  # ticks cooldown; bites if already touching

	# Merging overrides everything: head to (and sit at) the merge point, no
	# stance and no avoidance, so zombies can overlap and reach touch_distance.
	if _merging:
		nav_agent.target_position = _merge_target
		_move_along_path()
		return

	# One-shot right-click move overrides the stance until it arrives.
	if command_mode:
		nav_agent.target_position = command_target
		if nav_agent.is_navigation_finished():
			command_mode = false
		_move_along_path()
		return

	var e: Node2D = null
	match stance:
		Stance.HOLD:
			return  # rooted; ignore fire, never chase
		Stance.AGGRESSIVE:
			e = _acquire_enemy()
			if e:
				target = e
				nav_agent.target_position = e.global_position
			elif _alert_timer > 0.0:
				target = null
				_alert_timer -= delta
				nav_agent.target_position = _alert_point
			else:
				target = null
				return
		Stance.PATROL_ATTACK:
			e = _acquire_enemy()
			if e:
				target = e
				nav_agent.target_position = e.global_position
			else:
				target = null
				_advance_patrol()
		Stance.PATROL_FLEE:
			e = _acquire_enemy()
			if e:
				target = null
				_no_enemy_timer = Balance.STANCE.flee_safe_seconds
				nav_agent.target_position = flee_point
			else:
				if _no_enemy_timer > 0.0:
					_no_enemy_timer -= delta
					nav_agent.target_position = flee_point
				else:
					_advance_patrol()
		Stance.SKITTISH:
			e = _acquire_enemy()
			if e:
				target = null
				nav_agent.target_position = flee_point
			else:
				return
		Stance.FLEE_POINT:
			target = null
			nav_agent.target_position = flee_point

	_move_along_path()


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	if velocity.length() > 0:
		rotation = velocity.angle()


## Server-side: nearest visible enemy (shooter or NPC), or null.
func _acquire_enemy() -> Node2D:
	var nodes: Array = []
	var cands: Array = []
	for grp in ["shooter", "npcs"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node2D and is_instance_valid(n):
				var eligible := true
				if "is_dead" in n and n.is_dead:
					eligible = false
				nodes.append(n)
				cands.append({ "pos": n.global_position, "eligible": eligible })
	var idx := Targeting.nearest_index(global_position, cands, vision_range * 64.0)
	return nodes[idx] if idx >= 0 else null


func _advance_patrol() -> void:
	var dest := patrol_a if _patrol_leg == 0 else patrol_b
	nav_agent.target_position = dest
	if StanceLogic.arrived(global_position.distance_to(dest), Balance.STANCE.arrive_px):
		_patrol_leg = StanceLogic.flip_leg(_patrol_leg)


func _move_along_path() -> void:
	if nav_agent.is_navigation_finished():
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(Vector2.ZERO)
		return
	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(direction * speed)
	else:
		# Avoidance off (e.g. merging): move directly so units can overlap.
		velocity = direction * speed
		move_and_slide()
		if velocity.length() > 0:
			rotation = velocity.angle()


## Enter/leave merge mode. While merging, avoidance is off (so zombies can
## touch) and the stance machine is bypassed (so they don't wander off).
func set_merging(value: bool, target: Vector2 = Vector2.ZERO) -> void:
	_merging = value
	command_mode = false
	nav_agent.avoidance_enabled = not value
	if value:
		_merge_target = target
		nav_agent.target_position = target


## Sound aggro: an Aggressive zombie within earshot turns toward a gunshot.
func alert_to(world_pos: Vector2) -> void:
	if stance != Stance.AGGRESSIVE:
		return  # Hold / flee / patrol stances deliberately ignore sound
	_alert_point = world_pos
	_alert_timer = Balance.AGGRO.alert_seconds


func set_stance(new_stance: int, p1: Vector2 = Vector2.ZERO, p2: Vector2 = Vector2.ZERO) -> void:
	stance = new_stance
	command_mode = false
	match new_stance:
		Stance.PATROL_ATTACK, Stance.PATROL_FLEE:
			patrol_a = p1
			patrol_b = p2
			_patrol_leg = 0
		Stance.FLEE_POINT, Stance.SKITTISH:
			flee_point = p1
	queue_redraw()


## Returns true if the target (shooter) is within this zombie's vision range.
func _target_in_range() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var detection_px: float = vision_range * 64.0
	return global_position.distance_to(target.global_position) <= detection_px


func _draw() -> void:
	if is_selected:
		var radius: float = 18.0
		var col_shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
		if col_shape:
			radius = 13.0 * col_shape.scale.x + 6.0
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color.GREEN, 2.0)
		draw_circle(Vector2(0, radius + 6.0), 3.5, _stance_color())


func _stance_color() -> Color:
	match stance:
		Stance.AGGRESSIVE: return Color.RED
		Stance.HOLD: return Color.GRAY
		Stance.PATROL_ATTACK: return Color.ORANGE
		Stance.PATROL_FLEE: return Color.YELLOW
		Stance.SKITTISH: return Color.CYAN
		Stance.FLEE_POINT: return Color.SKY_BLUE
		_: return Color.WHITE

func set_command(destination: Vector2) -> void:
	command_mode = true
	command_target = destination

func set_target(new_target: Node2D) -> void:
	target = new_target

func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()
	_refresh_health_bar()


func _refresh_health_bar() -> void:
	if _health_bar == null:
		return
	var frac := float(hp) / float(max_hp)
	_health_bar.set_fraction(frac)
	_health_bar.visible = is_selected or frac < 1.0


func _check_contact_damage(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if target == null or not is_instance_valid(target):
		return
	var distance := global_position.distance_to(target.global_position)
	if CombatMath.can_attack(distance, _contact_px, _attack_cooldown):
		if target.has_method("take_damage"):
			target.take_damage(damage_per_hit)
		_attack_cooldown = attack_interval
		_lunge_toward(target.global_position)


func _lunge_toward(point: Vector2) -> void:
	var dir := (point - global_position).normalized()
	var tween := create_tween()
	tween.tween_property(self, "position", position + dir * 6.0, 0.05)
	tween.tween_property(self, "position", position, 0.05)


func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	took_damage.emit(self, int(amount))
	_refresh_health_bar()
	modulate = Color.WHITE
	await get_tree().create_timer(0.05).timeout
	if merge_progress < 0.0:
		modulate = Color(1, 1, 1, 1)
	if hp <= 0:
		die()


func die() -> void:
	is_dead = true
	zombie_died.emit(self)
	queue_free()
