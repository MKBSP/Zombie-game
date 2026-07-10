extends CharacterBody2D

# Stats come from Balance.MASTER (assigned in _ready).
var speed: float
var max_hp: int
var contact_dps: float
var vision_range: int
var _contact_px: float
var damage_per_hit: int
var attack_interval: float
var _attack_cooldown: float = 0.0
var _health_bar: HealthBar = null
var _last_hp_seen: int = -1

var hp: int
var is_dead: bool = false
var target: Node2D = null

var command_mode: bool = false
var command_target: Vector2 = Vector2.ZERO
var is_selected: bool = false

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

signal master_zombie_died
signal took_damage(zombie: Node2D, amount: int)


func _ready() -> void:
	# Clients: adopt the spawn pose (see zombie.gd — sync_pos carries position).
	if not multiplayer.is_server():
		position = sync_pos
		rotation = sync_rot
	speed = Balance.MASTER.speed
	max_hp = Balance.MASTER.max_hp
	contact_dps = Balance.MASTER.contact_dps
	vision_range = Balance.MASTER.vision
	_contact_px = Balance.MASTER.contact_px
	damage_per_hit = Balance.MASTER.damage_per_hit
	attack_interval = Balance.MASTER.attack_interval
	hp = max_hp
	scale = Vector2(Balance.MASTER.scale, Balance.MASTER.scale)
	modulate = Color(1.0, 0.2, 0.2)
	_health_bar = HealthBar.new()
	_health_bar.position = Vector2(0, -22)
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
	set_collision_mask_value(2, true)  # solid body vs standard zombies
	set_collision_mask_value(4, true)  # ...and vs NPCs
	await get_tree().physics_frame
	nav_agent.target_position = global_position  # Stay put initially


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if command_mode:
		nav_agent.target_position = command_target
		if nav_agent.is_navigation_finished():
			command_mode = false
	else:
		if target != null and _target_in_range():
			nav_agent.target_position = target.global_position
		else:
			_check_contact_damage(delta)  # tick cooldown / bite if touching
			return  # Idle — stay put

	if nav_agent.is_navigation_finished():
		return

	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	nav_agent.set_velocity(direction * speed)
	# velocity applied in _on_velocity_computed (RVO avoidance)

	_check_contact_damage(delta)


func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	if velocity.length() > 0:
		rotation = velocity.angle()


func _target_in_range() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var detection_px: float = vision_range * 64.0
	return global_position.distance_to(target.global_position) <= detection_px


func _draw() -> void:
	if is_selected:
		# Scale is 1.8 on this node, so draw in local coords (pre-scale).
		# Radius 16 * 1.8 = 28.8px visual — clearly outside the 25px sprite edge.
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color.GREEN, 3.0)


func set_command(destination: Vector2) -> void:
	command_mode = true
	command_target = destination


func set_target(new_target: Node2D) -> void:
	target = new_target


## Server-synced pose (see NetSmooth): published here, eased on clients.
var sync_pos: Vector2
var sync_rot: float


## Publish the spawn pose before the MultiplayerSpawner captures spawn state.
func _enter_tree() -> void:
	if multiplayer.is_server():
		sync_pos = position
		sync_rot = rotation


func _process(delta: float) -> void:
	if multiplayer.is_server():
		sync_pos = position
		sync_rot = rotation
	else:
		NetSmooth.follow(self, sync_pos, delta)
		NetSmooth.follow_rot(self, sync_rot, delta)
	if _health_bar and hp != _last_hp_seen:
		_last_hp_seen = hp
		_refresh_health_bar()


func _refresh_health_bar() -> void:
	if _health_bar == null:
		return
	var frac := float(hp) / float(max_hp)
	_health_bar.set_fraction(frac)
	_health_bar.visible = is_selected or frac < 1.0


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()
	_refresh_health_bar()


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


func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	took_damage.emit(self, int(amount))
	_refresh_health_bar()
	modulate = Color.WHITE
	await get_tree().create_timer(0.05).timeout
	modulate = Color(1.0, 0.2, 0.2)
	if hp <= 0:
		die()


func die() -> void:
	is_dead = true
	master_zombie_died.emit()
	queue_free()
