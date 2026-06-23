extends Area2D

@export var speed: float = 600.0
@export var damage: float = 35.0
@export var lifetime: float = 1.8

var direction: Vector2 = Vector2.ZERO
## Range falloff, set by Weapons.fire(). origin = muzzle position.
var origin: Vector2 = Vector2.ZERO
var optimal_range_px: float = 0.0
var zero_range_px: float = 0.0
## Weapon backing the falloff curve. null = no falloff (full damage).
var weapon: WeaponData = null

func _ready() -> void:
	# Simulation (movement, collisions, despawn) is server-only; clients just
	# render the synced position. Server queue_free despawns replicas too.
	set_physics_process(multiplayer.is_server())
	lifetime = Balance.BULLET.lifetime  # damage/speed are set per-weapon by Weapons.fire()
	if origin == Vector2.ZERO:
		origin = global_position
	if multiplayer.is_server():
		var timer := get_tree().create_timer(lifetime)
		timer.timeout.connect(queue_free)
		body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	# Despawn at max range so out-of-range shots don't keep flying.
	if zero_range_px > 0.0 and origin.distance_to(global_position) >= zero_range_px:
		queue_free()

## Damage to apply on hit, scaled by range falloff when a weapon is set.
func _damage_for_hit() -> float:
	if weapon == null:
		return damage
	return damage * AimModel.damage_mult(weapon, origin.distance_to(global_position))

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("shooter"):
		# Never hit the shooter (bullets spawn near its body)
		return
	if body.is_in_group("zombies"):
		# Center-mass crit: 4x when the shot's path threads the zombie's core.
		var dmg := _damage_for_hit()
		if AimModel.is_headshot(origin, direction, body.global_position, Balance.HEADSHOT.radius_px):
			dmg *= Balance.HEADSHOT.mult
		if body.has_method("take_damage"):
			body.take_damage(dmg)
		queue_free()
	elif body.is_in_group("npcs"):
		# Deal damage to the NPC
		if body.has_method("take_damage"):
			body.take_damage(_damage_for_hit())
		queue_free()
	elif body is TileMapLayer:
		# Hit a building or edge tile — despawn
		queue_free()
	elif body is StaticBody2D:
		# Hit a prop (car, fence, etc.) — despawn
		queue_free()
