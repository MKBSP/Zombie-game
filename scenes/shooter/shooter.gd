extends CharacterBody2D

# --- Tunable values ---
@export var speed: float = 210.0
@export var max_hp: int = 100
@export var contact_damage_per_second: float = 12.0

# --- State ---
var hp: int
var can_shoot: bool = true
var is_dead: bool = false
var _damage_accumulator: float = 0.0


# --- Node references (filled in _ready) ---
@onready var gun_tip: Marker2D = $GunTip
@onready var shoot_cooldown: Timer = $ShootCooldown

# --- Signals ---
signal hp_changed(new_hp: int)
signal player_died

# Preload the bullet scene so we can instance it
var bullet_scene: PackedScene = preload("res://scenes/bullet/bullet.tscn")


func _ready() -> void:
	hp = max_hp
	# Connect the cooldown timer — when it finishes, allow shooting again
	shoot_cooldown.timeout.connect(_on_shoot_cooldown_timeout)


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# --- Movement ---
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right") #move with A and D 
	input_dir.y = Input.get_axis("move_up", "move_down")       # W/S 

	# Normalise so diagonal movement isn't faster
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()

	velocity = input_dir * speed
	move_and_slide()

	# --- Aim toward mouse ---
	var mouse_pos := get_global_mouse_position()
	look_at(mouse_pos)

	# --- Shooting ---
	if Input.is_action_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		shoot()


func shoot() -> void:
	if not can_shoot or is_dead:
		return

	can_shoot = false
	shoot_cooldown.start()

	# Spawn a bullet at the gun tip, rotated to match the shooter's facing
	var bullet := bullet_scene.instantiate()
	bullet.global_position = gun_tip.global_position
	bullet.rotation = global_rotation
	bullet.direction = Vector2.from_angle(global_rotation)
	# Add the bullet to the world (parent of the shooter), not to the shooter itself
	get_tree().current_scene.add_child(bullet)


func _on_shoot_cooldown_timeout() -> void:
	can_shoot = true


func take_damage(amount: float) -> void:
	if is_dead:
		return
	_damage_accumulator += amount
	var whole_damage := int(_damage_accumulator)
	if whole_damage >= 1:
		hp -= whole_damage
		_damage_accumulator -= whole_damage
		hp = max(hp, 0)
		hp_changed.emit(hp)
		if hp <= 0:
			die()


func die() -> void:
	is_dead = true
	player_died.emit()
	# Don't queue_free — we want the body to stay so the game over screen shows
