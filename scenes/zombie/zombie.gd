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
	_update_navigation()

func _physics_process(delta: float) -> void:
	if is_dead or target == null:
		return

	if command_mode:
		nav_agent.target_position = command_target
		if nav_agent.is_navigation_finished():
			command_mode = false
	else:
		if target:
			nav_agent.target_position = target.global_position

	if nav_agent.is_navigation_finished():
		return

	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

	if velocity.length() > 0:
		rotation = velocity.angle()

	_check_contact_damage(delta)

func _draw() -> void:
	if is_selected:
		draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color.GREEN, 2.0)

func set_command(destination: Vector2) -> void:
	command_mode = true
	command_target = destination

func set_target(new_target: Node2D) -> void:
	target = new_target

func set_selected(value: bool) -> void:
	is_selected = value
	queue_redraw()

func _update_navigation() -> void:
	if target != null:
		nav_agent.target_position = target.global_position

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
