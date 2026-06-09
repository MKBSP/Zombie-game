extends CharacterBody2D

@export var speed: float = 85.0
@export var max_hp: int = 150
@export var contact_dps: float = 12.0
@export var vision_range: int = 2


var command_mode: bool = false
var command_target: Vector2 = Vector2.ZERO
var is_selected: bool = false
var hp: int
var is_dead: bool = false
var target: Node2D = null

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

signal zombie_died(zombie: Node2D)

func _ready() -> void:
	hp = max_hp
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
	if distance < 28.0:
		if target.has_method("take_damage"):
			target.take_damage(contact_dps * delta)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	modulate = Color.WHITE
	await get_tree().create_timer(0.05).timeout
	modulate = Color(0.6, 0.0, 0.0)
	if hp <= 0:
		die()

func die() -> void:
	is_dead = true
	zombie_died.emit(self)
	queue_free()
