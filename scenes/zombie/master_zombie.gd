extends CharacterBody2D

@export var speed: float = 60.0
@export var max_hp: int = 450
@export var contact_dps: float = 12.0

var hp: int
var is_dead: bool = false
var target: Node2D = null

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

signal master_zombie_died


func _ready() -> void:
	hp = max_hp
	# Make it bigger and red with a yellow tint
	scale = Vector2(1.8, 1.8)
	modulate = Color(1.0, 0.2, 0.2)  # bright red
	await get_tree().physics_frame
	_update_navigation()


func _physics_process(delta: float) -> void:
	if is_dead or target == null:
		return

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


func _update_navigation() -> void:
	if target != null:
		nav_agent.target_position = target.global_position


func _check_contact_damage(delta: float) -> void:
	if target == null:
		return
	var distance := global_position.distance_to(target.global_position)
	if distance < 36.0:  # larger because Master Zombie is scaled up
		if target.has_method("take_damage"):
			target.take_damage(contact_dps * delta)


func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	modulate = Color.WHITE
	await get_tree().create_timer(0.05).timeout
	modulate = Color(1.0, 0.2, 0.2)  # back to bright red

	if hp <= 0:
		die()


func die() -> void:
	is_dead = true
	master_zombie_died.emit()
	queue_free()
