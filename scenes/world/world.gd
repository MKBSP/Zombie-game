extends Node2D

var shooter_scene := preload("res://scenes/shooter/shooter.tscn")
var zombie_scene := preload("res://scenes/zombie/zombie.tscn")
var master_zombie_scene := preload("res://scenes/zombie/master_zombie.tscn")

var shooter: CharacterBody2D = null
var master_zombie: CharacterBody2D = null


func _ready() -> void:
	_create_grid()
	_spawn_shooter()
	_spawn_master_zombie()
	_spawn_standard_zombies()


func _create_grid() -> void:
	var grid := GridDrawer.new()
	grid.z_index = -1  # draw behind everything
	add_child(grid)


func _spawn_shooter() -> void:
	shooter = shooter_scene.instantiate()
	shooter.global_position = Vector2(300, 300)
	add_child(shooter)
	shooter.player_died.connect(_on_player_died)


func _spawn_master_zombie() -> void:
	master_zombie = master_zombie_scene.instantiate()
	master_zombie.global_position = Vector2(2700, 2700)
	add_child(master_zombie)
	master_zombie.set_target(shooter)
	master_zombie.master_zombie_died.connect(_on_master_zombie_died)


func _spawn_standard_zombies() -> void:
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
		add_child(z)
		z.set_target(shooter)
		z.zombie_died.connect(_on_zombie_died)


func _on_zombie_died(_zombie: Node2D) -> void:
	pass


func _on_master_zombie_died() -> void:
	_show_game_over("YOU WIN!")


func _on_player_died() -> void:
	_show_game_over("YOU DIED")


func _show_game_over(message: String) -> void:
	print(message)
	get_tree().paused = true


# Inner class — draws grid lines on its own Node2D
class GridDrawer extends Node2D:
	func _draw() -> void:
		var map_size := 3000
		var spacing := 64
		for x in range(0, map_size + 1, spacing):
			draw_line(Vector2(x, 0), Vector2(x, map_size), Color(1, 1, 1, 0.08), 1.0)
		for y in range(0, map_size + 1, spacing):
			draw_line(Vector2(0, y), Vector2(map_size, y), Color(1, 1, 1, 0.08), 1.0)
		draw_rect(Rect2(0, 0, map_size, map_size), Color(1, 1, 1, 0.3), false, 2.0)
