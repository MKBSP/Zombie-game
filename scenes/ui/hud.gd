extends Control

@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_label: Label = $HPLabel
@onready var compass_label: Label = $CompassLabel
@onready var debug_coords: Label = $DebugCoords

var shooter: Node2D = null
var master_zombie: Node2D = null
var debug_visible: bool = true


func setup(p_shooter: Node2D, p_master_zombie: Node2D) -> void:
	shooter = p_shooter
	master_zombie = p_master_zombie
	# Connect to the shooter's hp_changed signal
	if shooter.has_signal("hp_changed"):
		shooter.hp_changed.connect(_on_hp_changed)


func _process(_delta: float) -> void:
	if shooter == null:
		return

	# Update compass
	_update_compass()

	# Update debug coordinates
	if debug_visible:
		debug_coords.text = "X: %d  Y: %d" % [int(shooter.global_position.x), int(shooter.global_position.y)]
	else:
		debug_coords.text = ""


func _unhandled_input(event: InputEvent) -> void:
	# Toggle debug info with F1
	if event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible


func _on_hp_changed(new_hp: int) -> void:
	hp_bar.value = new_hp
	hp_label.text = "HP %d" % new_hp


func _update_compass() -> void:
	if master_zombie == null or not is_instance_valid(master_zombie):
		compass_label.text = "Master Zombie: DEAD"
		return

	var dir := (master_zombie.global_position - shooter.global_position).normalized()
	var angle := dir.angle()

	# Convert angle to a compass arrow
	# 8 directions
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	# angle is in radians: 0 = right, PI/2 = down, etc.
	# Shift by half a segment (PI/8) so boundaries line up
	var index := int(round(angle / (PI / 4.0))) % 8
	if index < 0:
		index += 8

	compass_label.text = "Master Zombie: %s  (%dm)" % [arrows[index], int(shooter.global_position.distance_to(master_zombie.global_position) / 10)]
