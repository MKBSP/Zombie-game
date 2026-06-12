extends Area2D

@export var speed: float = 600.0
@export var damage: float = 35.0
@export var lifetime: float = 1.8

var direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Despawn after lifetime expires
	var timer := get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

	# Connect to body_entered for TileMapLayer collision (buildings)
	body_entered.connect(_on_body_entered)
	# Connect to area_entered if zombies use Area2D (depends on your Phase 1 setup)
	# If zombies are CharacterBody2D, they're detected by body_entered too.

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("shooter"):
		# Never hit the shooter (bullets spawn near its body)
		return
	if body.is_in_group("zombies"):
		# Deal damage to the zombie
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	elif body.is_in_group("npcs"):
		# Deal damage to the NPC
		if body.has_method("take_damage"):
			body.take_damage(damage)
		queue_free()
	elif body is TileMapLayer:
		# Hit a building or edge tile — despawn
		queue_free()
	elif body is StaticBody2D:
		# Hit a prop (car, fence, etc.) — despawn
		queue_free()
