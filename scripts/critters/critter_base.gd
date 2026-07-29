extends Node2D
class_name CritterBase

## Shared behavior for rats/bugs/lightning bugs (design spec §5). Rats and bugs
## wander idly and flee from the shooter's flashlight cone or a gunshot noise
## event; lightning bugs never flee, they only nudge aside if a
## zombie/NPC/player walks directly through their path. Placeholder shapes only
## (a ColorRect child) — this script owns behavior, not visuals.

enum Kind { RAT, BUG, FIREFLY }

@export var kind: Kind = Kind.RAT

var _speed: float
var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _last_noise_pos: Variant = null


func _ready() -> void:
	var c: Dictionary = Balance.AMBIENT_LIFE.critters
	match kind:
		Kind.RAT:
			_speed = c.rat_speed
		Kind.BUG:
			_speed = c.bug_speed
		Kind.FIREFLY:
			_speed = c.firefly_speed
	_pick_new_wander_dir()

	var world_node := get_tree().get_first_node_in_group("world")
	if world_node and world_node.has_signal("noise_event"):
		world_node.noise_event.connect(_on_noise)


func _process(delta: float) -> void:
	var c: Dictionary = Balance.AMBIENT_LIFE.critters

	if kind == Kind.FIREFLY:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_new_wander_dir()
		var nudge := _nudge_away_from_nearby(c.nudge_trigger_px)
		global_position += (_wander_dir + nudge) * _speed * delta
		return

	var flee_dir := _flee_direction(c.flee_trigger_px)
	if flee_dir != Vector2.ZERO:
		global_position += flee_dir * _speed * delta
		return

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_wander_dir()
	global_position += _wander_dir * _speed * delta


func _pick_new_wander_dir() -> void:
	var c: Dictionary = Balance.AMBIENT_LIFE.critters
	_wander_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	_wander_timer = c.wander_change_seconds


## Rats/bugs only: away from the nearest shooter's flashlight cone (if inside
## it) or the most recent gunshot, whichever is closer. Vector2.ZERO if neither
## is within trigger range.
func _flee_direction(trigger_px: float) -> Vector2:
	var away := Vector2.ZERO
	var closest := trigger_px
	for s in get_tree().get_nodes_in_group("shooter"):
		if s is Node2D:
			var d: float = global_position.distance_to(s.global_position)
			if d < closest:
				closest = d
				away = (global_position - s.global_position).normalized()
	if _last_noise_pos != null and global_position.distance_to(_last_noise_pos) < closest:
		away = (global_position - _last_noise_pos).normalized()
	return away


## Lightning bugs only: a small push directly away from any zombie/NPC/player
## within `trigger_px` — not fear, just staying out from underfoot.
func _nudge_away_from_nearby(trigger_px: float) -> Vector2:
	var nudge := Vector2.ZERO
	for group in ["zombies", "npcs", "shooter"]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node2D and global_position.distance_to(n.global_position) < trigger_px:
				nudge += (global_position - n.global_position).normalized()
	return nudge


func _on_noise(pos: Vector2, _strength: float) -> void:
	_last_noise_pos = pos
