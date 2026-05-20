extends Node
class_name MergeManager

## Manages the zombie merging process.
## Controls the walk-to-merge, lock-in timer, and spawn of the new zombie.

signal merge_started       # Emitted when zombies begin walking to merge
signal merge_locked_in     # Emitted when timer starts (no cancel)
signal merge_completed     # Emitted when new zombie spawns
signal merge_cancelled     # Emitted when merge is cancelled

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

# Distance threshold for "touching" (pixels)
const TOUCH_DISTANCE: float = 30.0


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


## Check if a specific zombie is part of the current merge.
func is_merging(zombie: Node2D) -> bool:
	return zombie in merge_zombies


func _process_walking() -> void:
	# Remove any dead zombies from the merge
	merge_zombies = merge_zombies.filter(func(z): return is_instance_valid(z))

	var required: int = 2 if merge_type == "fast" else 3
	if merge_zombies.size() < required:
		# Not enough zombies left — cancel
		cancel_merge()
		return

	# Check if all zombies are close enough to each other
	var all_touching := true
	for i in range(merge_zombies.size()):
		for j in range(i + 1, merge_zombies.size()):
			var dist: float = merge_zombies[i].global_position.distance_to(
				merge_zombies[j].global_position
			)
			if dist > TOUCH_DISTANCE:
				all_touching = false
				break
		if not all_touching:
			break

	if all_touching:
		# Transition to locked state
		state = MergeState.LOCKED
		lock_duration = 2.0 * float(merge_zombies.size())
		lock_timer = 0.0

		# Freeze all merging zombies
		for z in merge_zombies:
			z.command_mode = true
			z.command_target = z.global_position  # Stay in place
			z.velocity = Vector2.ZERO

		merge_locked_in.emit()


func _process_locked(delta: float) -> void:
	lock_timer += delta

	if lock_timer >= lock_duration:
		_complete_merge()


func _complete_merge() -> void:
	# Calculate spawn position (midpoint)
	var midpoint := Vector2.ZERO
	for z in merge_zombies:
		if is_instance_valid(z):
			midpoint += z.global_position
	midpoint /= float(merge_zombies.size())

	# Calculate HP percentage average
	var hp_pct_sum: float = 0.0
	var count: int = 0
	for z in merge_zombies:
		if is_instance_valid(z):
			# Assumes zombie has `hp` and `max_hp` properties
			if "hp" in z and "max_hp" in z:
				hp_pct_sum += float(z.hp) / float(z.max_hp)
				count += 1
	var avg_hp_pct: float = hp_pct_sum / float(max(count, 1))

	# Remove the old zombies
	for z in merge_zombies:
		if is_instance_valid(z):
			z.queue_free()

	# Spawn the new zombie
	var scene: PackedScene = null
	if merge_type == "fast":
		scene = fast_zombie_scene
	elif merge_type == "fat":
		scene = fat_zombie_scene

	if scene:
		var new_zombie: Node2D = scene.instantiate()
		new_zombie.global_position = midpoint
		get_tree().current_scene.add_child(new_zombie)

		# Set HP based on average percentage
		if "hp" in new_zombie and "max_hp" in new_zombie:
			new_zombie.hp = roundi(float(new_zombie.max_hp) * avg_hp_pct)

	# Reset state
	merge_zombies.clear()
	merge_type = ""
	state = MergeState.IDLE
	merge_completed.emit()
