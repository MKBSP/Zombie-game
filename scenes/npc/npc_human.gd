extends CharacterBody2D

## Human NPC in a zombie apocalypse.
## Behaviour: sneaks between hiding spots (walkable tiles next to buildings),
## hides 10-20s, then meanders via random waypoints to a new spot.
## A zombie touching it starts an inevitable 5s conversion (freeze + pulse +
## progress bar), then a standard zombie spawns in its place.
## The shooter touching it makes it follow him permanently, ~1 tile behind.
## Bullets can kill it at any time — death spawns no zombie.

signal converted(zombie: Node2D)

const ZOMBIE_SCENE := preload("res://scenes/zombie/zombie.tscn")

@export var speed: float = 50.0
@export var max_hp: int = 50
@export var hide_min: float = 10.0
@export var hide_max: float = 20.0
@export var hide_radius: int = 12  # tiles to search for the next hiding spot

const CONVERT_DURATION: float = 5.0
const FOLLOW_DISTANCE: float = 64.0  # 1 tile behind the shooter
const FOLLOW_DEADZONE: float = 12.0
const WALKABLE: Array[String] = ["road", "sidewalk", "grass", "parking"]

var hp: int

# References injected by the spawner (world.gd)
var ground_layer: TileMapLayer
var building_layer: TileMapLayer
var shooter: Node2D

enum State { HIDDEN, RELOCATING, FOLLOWING, CONVERTING }
var state: State = State.HIDDEN

var _hide_timer: float = 0.0
var _waypoints: Array[Vector2] = []
var _convert_timer: float = 0.0
var _last_shooter_dir: Vector2 = Vector2.RIGHT
var _progress_bar: Node2D = null

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var conversion_zone: Area2D = $ConversionZone


func _ready() -> void:
	hp = max_hp
	nav_agent.path_desired_distance = 8.0
	nav_agent.target_desired_distance = 8.0
	conversion_zone.body_entered.connect(_on_zone_body_entered)
	# Short randomized first wait so NPCs don't all move at once
	_start_hidden(randf_range(1.0, 4.0))


func _physics_process(delta: float) -> void:
	match state:
		State.CONVERTING:
			_process_converting(delta)
		State.HIDDEN:
			_hide_timer -= delta
			if _hide_timer <= 0.0:
				_plan_relocation()
		State.RELOCATING:
			if nav_agent.is_navigation_finished():
				if _waypoints.is_empty():
					_start_hidden(randf_range(hide_min, hide_max))
				else:
					nav_agent.target_position = _waypoints.pop_front()
			else:
				_nav_move()
		State.FOLLOWING:
			_process_following()


func _nav_move() -> void:
	var next_pos: Vector2 = nav_agent.get_next_path_position()
	velocity = (next_pos - global_position).normalized() * speed
	move_and_slide()


func _start_hidden(duration: float) -> void:
	state = State.HIDDEN
	_hide_timer = duration
	_waypoints.clear()
	velocity = Vector2.ZERO


## True if the tile is a walkable ground type with no building on it.
func _is_walkable(tile: Vector2i) -> bool:
	if ground_layer == null:
		return false
	var td: TileData = ground_layer.get_cell_tile_data(tile)
	if td == null or not td.get_custom_data("tile_type") in WALKABLE:
		return false
	if building_layer and building_layer.get_cell_tile_data(tile) != null:
		return false
	return true


## A hiding tile is walkable and adjacent to at least one building tile.
func _is_hiding_tile(tile: Vector2i) -> bool:
	if not _is_walkable(tile):
		return false
	if building_layer == null:
		return false
	for n in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if building_layer.get_cell_tile_data(tile + n) != null:
			return true
	return false


func _find_hiding_spot() -> Vector2i:
	var current_tile: Vector2i = ground_layer.local_to_map(
		ground_layer.to_local(global_position)
	)
	for _attempt in range(40):
		var candidate := current_tile + Vector2i(
			randi_range(-hide_radius, hide_radius),
			randi_range(-hide_radius, hide_radius)
		)
		if _is_hiding_tile(candidate):
			return candidate
	return Vector2i(-1, -1)


## Build a meandering waypoint path to a new hiding spot.
func _plan_relocation() -> void:
	if ground_layer == null:
		_start_hidden(randf_range(1.0, 3.0))
		return

	var spot := _find_hiding_spot()
	if spot == Vector2i(-1, -1):
		_start_hidden(randf_range(1.0, 3.0))
		return

	var start_tile: Vector2i = ground_layer.local_to_map(
		ground_layer.to_local(global_position)
	)
	_waypoints.clear()

	# 2-4 intermediate waypoints jittered off the straight line, so the path
	# looks like nervous wandering instead of a beeline
	var steps := randi_range(2, 4)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var line_tile := Vector2i((Vector2(start_tile) + (Vector2(spot) - Vector2(start_tile)) * t).round())
		for _try in range(8):
			var jittered := line_tile + Vector2i(randi_range(-3, 3), randi_range(-3, 3))
			if _is_walkable(jittered):
				_waypoints.append(ground_layer.map_to_local(jittered))
				break

	_waypoints.append(ground_layer.map_to_local(spot))
	state = State.RELOCATING
	nav_agent.target_position = _waypoints.pop_front()


func _process_following() -> void:
	if not is_instance_valid(shooter):
		_start_hidden(randf_range(1.0, 3.0))
		return

	if "velocity" in shooter and shooter.velocity.length() > 5.0:
		_last_shooter_dir = shooter.velocity.normalized()

	var follow_point: Vector2 = shooter.global_position - _last_shooter_dir * FOLLOW_DISTANCE
	if global_position.distance_to(follow_point) < FOLLOW_DEADZONE:
		velocity = Vector2.ZERO
		return

	nav_agent.target_position = follow_point
	if not nav_agent.is_navigation_finished():
		_nav_move()
	else:
		velocity = Vector2.ZERO


func _on_zone_body_entered(body: Node2D) -> void:
	if state == State.CONVERTING:
		return  # Conversion is inevitable — ignore further contact
	if body.is_in_group("zombies"):
		_start_conversion()
	elif body.is_in_group("shooter") and state != State.FOLLOWING:
		state = State.FOLLOWING


func _start_conversion() -> void:
	state = State.CONVERTING
	_convert_timer = 0.0
	velocity = Vector2.ZERO
	nav_agent.target_position = global_position

	_progress_bar = ConversionProgressBar.new()
	add_child(_progress_bar)
	_progress_bar.position = Vector2(0, -24)


func _process_converting(delta: float) -> void:
	velocity = Vector2.ZERO
	_convert_timer += delta

	if _progress_bar and _progress_bar is ConversionProgressBar:
		_progress_bar.progress = _convert_timer / CONVERT_DURATION

	var pulse: float = 0.6 + 0.4 * abs(sin(_convert_timer * 4.0))
	modulate = Color(pulse, pulse, pulse, 1.0)

	if _convert_timer >= CONVERT_DURATION:
		_finish_conversion()


func _finish_conversion() -> void:
	var new_zombie: Node2D = ZOMBIE_SCENE.instantiate()
	new_zombie.global_position = global_position
	get_parent().add_child(new_zombie)
	if is_instance_valid(shooter) and new_zombie.has_method("set_target"):
		new_zombie.set_target(shooter)
	converted.emit(new_zombie)
	queue_free()


## Called by bullets. Death never spawns a zombie — shooting a converting
## NPC before the bar fills is the only way to stop a conversion.
func take_damage(amount: float) -> void:
	hp -= int(amount)
	modulate = Color(1.0, 0.3, 0.3, 1.0)
	get_tree().create_timer(0.05).timeout.connect(func():
		if is_instance_valid(self) and state != State.CONVERTING:
			modulate = Color.WHITE
	)
	if hp <= 0:
		queue_free()


## Small progress bar drawn above the NPC during conversion.
## Mirrors MergeManager.MergeProgressBar, sized for the 32x32 NPC.
class ConversionProgressBar extends Node2D:
	var progress: float = 0.0
	const BAR_WIDTH: float = 32.0
	const BAR_HEIGHT: float = 4.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var bg_rect := Rect2(-BAR_WIDTH / 2, -BAR_HEIGHT / 2, BAR_WIDTH, BAR_HEIGHT)
		draw_rect(bg_rect, Color(0.2, 0.2, 0.2, 0.8))
		var fill_width: float = BAR_WIDTH * clampf(progress, 0.0, 1.0)
		var fill_rect := Rect2(-BAR_WIDTH / 2, -BAR_HEIGHT / 2, fill_width, BAR_HEIGHT)
		draw_rect(fill_rect, Color(1.0, 0.8, 0.0, 1.0))
		draw_rect(bg_rect, Color.WHITE, false, 1.0)
