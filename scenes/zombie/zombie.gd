extends CharacterBody2D

@export var speed: float = 85.0
@export var max_hp: int = 150
@export var contact_dps: float = 12.0  # damage per second on contact

var hp: int
var is_dead: bool = false
var target: Node2D = null  # the shooter — assigned by the world scene

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

signal zombie_died(zombie: Node2D)


func _ready() -> void:
	hp = max_hp
	# Wait one physics frame before setting navigation target
	# (NavigationServer needs a frame to initialise)
	await get_tree().physics_frame
	_update_navigation()


func _physics_process(delta: float) -> void:
	if is_dead or target == null:
		return

	# Update navigation target every frame
	nav_agent.target_position = target.global_position

	# If we've arrived, stop
	if nav_agent.is_navigation_finished():
		return

	# Move toward the next path point
	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

	# Face the direction of movement
	if velocity.length() > 0:
		rotation = velocity.angle()

	# Check for contact damage
	_check_contact_damage(delta)


func _update_navigation() -> void:
	if target != null:
		nav_agent.target_position = target.global_position


func _check_contact_damage(delta: float) -> void:
	# If close enough to the target, deal damage
	if target == null:
		return
	var distance := global_position.distance_to(target.global_position)
	if distance < 28.0:  # collision radius of zombie + shooter
		if target.has_method("take_damage"):
			target.take_damage(contact_dps * delta)


func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	# Visual feedback: flash white briefly
	modulate = Color.WHITE
	await get_tree().create_timer(0.05).timeout
	modulate = Color(0.6, 0.0, 0.0)  # back to dark red

	if hp <= 0:
		die()


func die() -> void:
	is_dead = true
	zombie_died.emit(self)
	queue_free()
