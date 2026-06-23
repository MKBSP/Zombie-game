extends Node
class_name MergeManager

## Manages the zombie merging process (server-authoritative).
## Controls the walk-to-merge, lock-in timer, and spawn of the new zombie.
## Visual: during lock phase, all zombies except one are hidden. The remaining
## one pulses and shows a progress bar (rendered per-peer from the zombie's
## synced merge_progress). On completion it's replaced by the new type.

signal merge_started
signal merge_locked_in
signal merge_completed
signal merge_cancelled

@export var fast_zombie_scene: PackedScene
@export var fat_zombie_scene: PackedScene
@export var ground_layer: TileMapLayer

# Merge state
enum MergeState { IDLE, WALKING, LOCKED }
var state: MergeState = MergeState.IDLE

# The zombies involved in the current merge
var merge_zombies: Array[Node2D] = []
var merge_type: String = ""  # "fast" or "fat"

# Lock-in timer
var lock_timer: float = 0.0
var lock_duration: float = 0.0

# The one zombie kept visible during lock phase
var _visible_zombie: Node2D = null

# Touch distance + lock timing live in Balance.MERGE.


func _ready() -> void:
	# Merge simulation runs on the server only (true in single player too)
	set_process(multiplayer.is_server())


func _process(delta: float) -> void:
	match state:
		MergeState.WALKING:
			_process_walking()
		MergeState.LOCKED:
			_process_locked(delta)


## Start a merge. zombies: the standard zombies to merge. type: "fast" or "fat".
func start_merge(zombies: Array[Node2D], type: String) -> void:
	if state != MergeState.IDLE:
		return

	merge_zombies = zombies.duplicate()
	merge_type = type
	state = MergeState.WALKING

	# Calculate midpoint — zombies walk toward each other
	var midpoint := Vector2.ZERO
	for z in merge_zombies:
		midpoint += z.global_position
	midpoint /= float(merge_zombies.size())

	# Command each zombie to walk to the midpoint
	for z in merge_zombies:
		if z.has_method("set_command"):
			z.set_command(midpoint)

	merge_started.emit()


## Cancel the current merge (only works during WALKING state).
func cancel_merge() -> void:
	if state != MergeState.WALKING:
		return

	# Revert zombies to AI mode
	for z in merge_zombies:
		if is_instance_valid(z):
			z.command_mode = false

	merge_zombies.clear()
	merge_type = ""
	state = MergeState.IDLE
	merge_cancelled.emit()


## Abort a merge from the LOCKED phase (e.g. the visible zombie was killed).
func _abort_locked() -> void:
	for z in merge_zombies:
		if is_instance_valid(z):
			z.command_mode = false
			z.visible = true
			z.merge_progress = -1.0
	merge_zombies.clear()
	merge_type = ""
	state = MergeState.IDLE
	merge_cancelled.emit()


## Check if a specific zombie is part of the current merge.
func is_merging(zombie: Node2D) -> bool:
	return zombie in merge_zombies


func _process_walking() -> void:
	# Remove any dead zombies from the merge
	merge_zombies = merge_zombies.filter(func(z): return is_instance_valid(z))

	var required: int = 2 if merge_type == "fast" else 3
	if merge_zombies.size() < required:
		cancel_merge()
		return

	# Check if all zombies are close enough to each other
	var all_touching := true
	for i in range(merge_zombies.size()):
		for j in range(i + 1, merge_zombies.size()):
			var dist: float = merge_zombies[i].global_position.distance_to(
				merge_zombies[j].global_position
			)
			if dist > Balance.MERGE.touch_distance:
				all_touching = false
				break
		if not all_touching:
			break

	if all_touching:
		_enter_locked_state()


func _enter_locked_state() -> void:
	state = MergeState.LOCKED
	lock_duration = Balance.MERGE.lock_seconds_per_zombie * float(merge_zombies.size())
	lock_timer = 0.0

	# Calculate midpoint for the visible zombie
	var midpoint := Vector2.ZERO
	for z in merge_zombies:
		midpoint += z.global_position
	midpoint /= float(merge_zombies.size())

	# Keep the first zombie visible, hide and freeze the rest
	_visible_zombie = merge_zombies[0]
	_visible_zombie.global_position = midpoint
	_visible_zombie.command_mode = true
	_visible_zombie.command_target = midpoint
	_visible_zombie.velocity = Vector2.ZERO
	_visible_zombie.merge_progress = 0.0  # synced; peers render bar + pulse

	for i in range(1, merge_zombies.size()):
		var z := merge_zombies[i]
		z.command_mode = true
		z.command_target = z.global_position
		z.velocity = Vector2.ZERO
		z.visible = false  # Hide — absorbed into the merge (synced)

	merge_locked_in.emit()


func _process_locked(delta: float) -> void:
	if not is_instance_valid(_visible_zombie):
		# The merging zombie was killed mid-lock — abort instead of
		# completing at a bogus position
		_abort_locked()
		return

	lock_timer += delta
	_visible_zombie.merge_progress = lock_timer / lock_duration

	if lock_timer >= lock_duration:
		_complete_merge()


func _complete_merge() -> void:
	# Calculate HP percentage average from ALL merge zombies (including hidden ones)
	var hp_pct_sum: float = 0.0
	var count: int = 0
	for z in merge_zombies:
		if is_instance_valid(z):
			if "hp" in z and "max_hp" in z:
				hp_pct_sum += float(z.hp) / float(z.max_hp)
				count += 1
	var avg_hp_pct: float = hp_pct_sum / float(max(count, 1))

	# Get spawn position from the visible zombie
	var spawn_pos := Vector2.ZERO
	if is_instance_valid(_visible_zombie):
		spawn_pos = _visible_zombie.global_position

	# Get the target (shooter) from any merge zombie so we can assign it to the new one
	var existing_target: Node2D = null
	for z in merge_zombies:
		if is_instance_valid(z) and "target" in z and z.target != null:
			existing_target = z.target
			break

	# Remove all old zombies
	for z in merge_zombies:
		if is_instance_valid(z):
			z.queue_free()
	_visible_zombie = null

	# Spawn the new zombie under Entities so the MultiplayerSpawner replicates it
	var scene: PackedScene = null
	if merge_type == "fast":
		scene = fast_zombie_scene
	elif merge_type == "fat":
		scene = fat_zombie_scene

	if scene:
		var new_zombie: Node2D = scene.instantiate()
		new_zombie.global_position = spawn_pos
		var parent: Node = get_tree().current_scene.get_node_or_null("Entities")
		if parent == null:
			parent = get_tree().current_scene
		parent.add_child(new_zombie, true)

		# Set HP based on average percentage
		if "hp" in new_zombie and "max_hp" in new_zombie:
			new_zombie.hp = roundi(float(new_zombie.max_hp) * avg_hp_pct)

		# Assign the shooter target so the new zombie has something to chase
		if existing_target and new_zombie.has_method("set_target"):
			new_zombie.set_target(existing_target)

	# Reset state
	merge_zombies.clear()
	merge_type = ""
	state = MergeState.IDLE
	merge_completed.emit()


## Simple progress bar drawn above a merging/converting zombie.
## Instantiated per-peer by zombie.gd from the synced merge_progress.
class MergeProgressBar extends Node2D:
	var progress: float = 0.0
	const BAR_WIDTH: float = 40.0
	const BAR_HEIGHT: float = 6.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var bg_rect := Rect2(-BAR_WIDTH / 2, -BAR_HEIGHT / 2, BAR_WIDTH, BAR_HEIGHT)
		draw_rect(bg_rect, Color(0.2, 0.2, 0.2, 0.8))
		var fill_width: float = BAR_WIDTH * clampf(progress, 0.0, 1.0)
		var fill_rect := Rect2(-BAR_WIDTH / 2, -BAR_HEIGHT / 2, fill_width, BAR_HEIGHT)
		draw_rect(fill_rect, Color(1.0, 0.8, 0.0, 1.0))
		draw_rect(bg_rect, Color.WHITE, false, 1.0)
