extends CharacterBody2D

@export var speed: float = 60.0
@export var max_hp: int = 450
@export var contact_dps: float = 12.0
@export var vision_range: int = 3

var hp: int
var is_dead: bool = false
var target: Node2D = null

var command_mode: bool = false
var command_target: Vector2 = Vector2.ZERO
var is_selected: bool = false

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

signal master_zombie_died


func _ready() -> void:
	hp = max_hp
	scale = Vector2(1.8, 1.8)
	modulate = Color(1.0, 0.2, 0.2)
	# AI/simulation runs on the server only (true in single player too)
	set_physics_process(multiplayer.is_server())
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
			return  # Idle — stay put

	if nav_agent.is_navigation_finished():
		return

	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

	if velocity.length() > 0:
		rotation = velocity.angle()

	_check_contact_damage(delta)


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


func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()


func _check_contact_damage(delta: float) -> void:
	if target == null:
		return
	var distance := global_position.distance_to(target.global_position)
	if distance < 48.0:
		if target.has_method("take_damage"):
			target.take_damage(contact_dps * delta)


func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	modulate = Color.WHITE
	await get_tree().create_timer(0.05).timeout
	modulate = Color(1.0, 0.2, 0.2)
	if hp <= 0:
		die()


func die() -> void:
	is_dead = true
	master_zombie_died.emit()
	queue_free()
