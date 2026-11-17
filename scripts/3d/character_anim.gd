extends Node3D
## Put on an instanced Quaternius-rig character (e.g. assets/characters/adventurer.glb)
## that is a child of a CharacterBody3D: plays Idle / Walk / Run from how fast the
## body actually moves (measured, so a frozen body idles), and Death once when the
## body's `is_dead` turns true. Clip names are "<prefix><Idle|Walk|Run|Death>".
## freeze() holds one frame of any clip (a survivor cowering) until unfreeze().

@export var prefix := "CharacterArmature|"
@export var walk_above := 0.3   # m/s
@export var run_above := 3.5    # m/s

var _ap: AnimationPlayer
var _body: Node3D
var _last := Vector3.ZERO
var _speed := 0.0
var frozen := false


func _ready() -> void:
	# keep animating even when the body is frozen (the local commander test
	# disables the shooter while you command)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_body = get_parent() as Node3D
	var found := find_children("*", "AnimationPlayer", true, false)
	if found.is_empty() or _body == null:
		set_process(false)
		return
	_ap = found[0]
	for n in ["Idle", "Walk", "Run"]:
		var a := _ap.get_animation(prefix + n)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
	_last = _body.global_position


func _process(delta: float) -> void:
	var moved := _body.global_position - _last
	_last = _body.global_position
	moved.y = 0.0
	_speed = lerpf(_speed, moved.length() / maxf(delta, 0.0001), minf(delta * 10.0, 1.0))
	if frozen and not _body.get("is_dead"):
		return
	var clip := "Idle"
	if _body.get("is_dead"):
		clip = "Death"
	elif _speed > run_above:
		clip = "Run"
	elif _speed > walk_above:
		clip = "Walk"
	if clip == "Death" and _ap.assigned_animation == prefix + clip:
		return  # one-shot: once it has played, the body stays down
	if _ap.current_animation != prefix + clip or not _ap.is_playing():
		_ap.play(prefix + clip, 0.2)


## Hold `clip` at `at` (0..1 of its length): no blend, a startled drop into it.
func freeze(clip: String, at: float) -> void:
	if _ap == null:
		return
	frozen = true
	_ap.play(prefix + clip, 0.0)
	_ap.seek(_ap.get_animation(prefix + clip).length * at, true)
	_ap.pause()


func unfreeze() -> void:
	frozen = false  # the next _process picks Idle / Walk / Run again
