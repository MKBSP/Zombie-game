extends Area2D

@export var speed: float = 600.0
@export var damage: int = 35

var direction := Vector2.RIGHT  # overridden on spawn

@onready var lifetime: Timer = $Lifetime


func _ready() -> void:
	# Direction is determined by rotation (set by the shooter before adding to tree)
	direction = Vector2.RIGHT.rotated(rotation)
	lifetime.timeout.connect(_on_lifetime_timeout)
	# Connect the body_entered signal for detecting CharacterBody2D zombies
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta


func _on_body_entered(body: Node2D) -> void:
	# If the body has a take_damage method, call it
	if body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()


func _on_lifetime_timeout() -> void:
	queue_free()
