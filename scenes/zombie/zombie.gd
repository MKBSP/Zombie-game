extends CharacterBody2D

# Stats come from Balance, chosen by group (standard / fast / fat). See _ready().
var speed: float
var max_hp: int
var contact_dps: float
var vision_range: int
var _contact_px: float


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

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

signal zombie_died(zombie: Node2D)

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
	scale = Vector2(stats.scale, stats.scale)
	hp = max_hp
	# AI/simulation runs on the server only (true in single player too)
	set_physics_process(multiplayer.is_server())
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

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if command_mode:
		nav_agent.target_position = command_target
		if nav_agent.is_navigation_finished():
			command_mode = false
	else:
		# Only chase target if it exists AND is within vision range
		if target != null and _target_in_range():
			nav_agent.target_position = target.global_position
		else:
			# Idle — stay put
			return

	if nav_agent.is_navigation_finished():
		return

	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

	if velocity.length() > 0:
		rotation = velocity.angle()

	_check_contact_damage(delta)


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

func set_command(destination: Vector2) -> void:
	command_mode = true
	command_target = destination

func set_target(new_target: Node2D) -> void:
	target = new_target

func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _check_contact_damage(delta: float) -> void:
	if target == null:
		return
	var distance := global_position.distance_to(target.global_position)
	if distance < _contact_px:
		if target.has_method("take_damage"):
			target.take_damage(contact_dps * delta)


func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
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
