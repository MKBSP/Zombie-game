extends Node2D

var shooter_scene := preload("res://scenes/shooter/shooter.tscn")
var zombie_scene := preload("res://scenes/zombie/zombie.tscn")
var master_zombie_scene := preload("res://scenes/zombie/master_zombie.tscn")

var shooter: CharacterBody2D = null
var master_zombie: CharacterBody2D = null


func _ready() -> void:
	_spawn_shooter()
	_spawn_master_zombie()
	_spawn_standard_zombies()


func _spawn_shooter() -> void:
	shooter = shooter_scene.instantiate()
	shooter.global_position = Vector2(300, 300)  # bottom-left area
	add_child(shooter)
	# Connect the death signal
	shooter.player_died.connect(_on_player_died)


func _spawn_master_zombie() -> void:
	master_zombie = master_zombie_scene.instantiate()
	master_zombie.global_position = Vector2(2700, 2700)  # far corner
	master_zombie.target = shooter
	add_child(master_zombie)
	# Connect win condition
	master_zombie.master_zombie_died.connect(_on_master_zombie_died)


func _spawn_standard_zombies() -> void:
	# Spawn 5 zombies near the Master Zombie
	var spawn_offsets := [
		Vector2(-100, -100),
		Vector2(100, -100),
		Vector2(-100, 100),
		Vector2(100, 100),
		Vector2(0, -150),
	]
	for offset in spawn_offsets:
		var z := zombie_scene.instantiate()
		z.global_position = master_zombie.global_position + offset
		z.target = shooter
		add_child(z)
		z.zombie_died.connect(_on_zombie_died)


func _on_zombie_died(_zombie: Node2D) -> void:
	# Standard zombie died — nothing special in Phase 1
	pass


func _on_master_zombie_died() -> void:
	# Player wins
	_show_game_over("YOU WIN!")


func _on_player_died() -> void:
	_show_game_over("YOU DIED")


func _show_game_over(message: String) -> void:
	# We'll build a proper overlay in Part 7. For now, print to console.
	print(message)
	get_tree().paused = true
