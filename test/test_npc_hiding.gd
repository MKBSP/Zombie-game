extends SceneTree

## Headless check for where 3D survivors and crates may stand
## (scripts/3d/npc_3d.gd): outdoors only (the hollow building shells leave
## navmesh islands inside), and how deep in cover a spot is. Builds real
## colliders, so it runs after the first frames. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_npc_hiding.gd

var _failures := 0
var N = load("res://scripts/3d/npc_3d.gd")


func _initialize() -> void:
	await process_frame
	_building("Building_block", Vector3(0, 5, 0), Vector3(10, 10, 10))
	_building("Building_angled", Vector3(0, 5, 100), Vector3(10, 10, 10), PI / 4)
	# an alley 2 m wide between two long blocks, and a lone long wall
	_building("Building_alley_w", Vector3(-6, 5, 200), Vector3(10, 10, 40))
	_building("Building_alley_e", Vector3(6, 5, 200), Vector3(10, 10, 40))
	_building("Building_wall", Vector3(100, 5, 200), Vector3(10, 10, 40))
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	_check("inside a block is not outdoors", not N.outdoors(space, Vector3(0, 0, 0)))
	_check("beside a block is outdoors", N.outdoors(space, Vector3(6, 0, 0)))
	_check("open street is outdoors", N.outdoors(space, Vector3(40, 0, 40)))
	var face := Vector3(1, 0, 1).normalized()  # the angled block's face normal
	_check("wall at 45 degrees, 1.2 m off, counts", N.next_to_building(space, Vector3(0, 0, 100) + face * (5.0 + 1.2)))
	_check("open street has no wall", not N.next_to_building(space, Vector3(40, 0, 40)))
	var w: Vector3 = N.wall_spot(space, Vector3(9, 0, 1), 8.0)
	_check("4 m out in the street slides to the wall (got %s)" % w, w != Vector3.INF and absf(w.x - 5.45) < 0.1 and absf(w.z - 1.0) < 0.3 and is_zero_approx(w.y))
	_check("slid spot is beside the wall, outdoors", N.next_to_building(space, w) and N.outdoors(space, w))
	_check("no wall in reach: INF", N.wall_spot(space, Vector3(40, 0, 40), 8.0) == Vector3.INF)
	_check("alley is deep cover (%d)" % N.cover_score(space, Vector3(0, 0, 200)), N.cover_score(space, Vector3(0, 0, 200)) >= 6)
	_check("against one wall (%d)" % N.cover_score(space, Vector3(106, 0, 200)), N.cover_score(space, Vector3(106, 0, 200)) == 3)
	_check("open street (%d)" % N.cover_score(space, Vector3(40, 0, 40)), N.cover_score(space, Vector3(40, 0, 40)) == 0)
	# --- reachable: an enclosed courtyard is its own navmesh island, and a path
	# to it stops at the nearest point of ours ---
	var to := Vector3(25, 0.45, 5)
	_check("path that arrives", N.path_arrives(PackedVector3Array([Vector3(1, 0.45, 1), Vector3(24.6, 0.45, 5.2)]), to))
	_check("path that stops short (other island)", not N.path_arrives(PackedVector3Array([Vector3(1, 0.45, 1), Vector3(10, 0.45, 5)]), to))
	_check("no path", not N.path_arrives(PackedVector3Array(), to))
	var z := Vector3(0, 0, 0)
	_check("route straight away keeps away", N.path_keeps_away(PackedVector3Array([Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(20, 0, 15)]), z, 9.0))
	_check("route round the block back past the zombie doesn't", not N.path_keeps_away(PackedVector3Array([Vector3(10, 0, 0), Vector3(10, 0, 4), Vector3(3, 0, 6), Vector3(-20, 0, 6)]), z, 9.0))

	# --- spotted by a zombie: 20% freeze, 80% run (one roll per sighting) ---
	_check("a 10 m run at 4.5 m/s is on time at 3 s", not N.leg_overdue(3.0, 10.0, 4.5))
	_check("...and overdue (blocked) at 7 s", N.leg_overdue(7.0, 10.0, 4.5))
	_check("19% roll freezes", N.react(0.19) == N.State.COWERING)
	_check("20% roll runs", N.react(0.2) == N.State.FLEEING)
	_check("freeze chance is 20%", is_equal_approx(Balance.NPC_3D.freeze_chance, 0.2))
	_check("new states keep the old numbers", N.State.CONVERTING == 3 and N.State.FLEEING == 4 and N.State.COWERING == 5)
	_check("fleeing outruns a standard zombie, not a fast one", Balance.NPC_3D.flee_mps > Balance.ZOMBIE_3D.speed_mps.standard and Balance.NPC_3D.flee_mps < 6.06)
	# --- cower pose: a frame of an existing clip, frozen (character_anim.gd) ---
	var Anim = load("res://scripts/3d/character_anim.gd")
	for md: Array in N.MODELS:
		var body: Node3D = load(md[0]).instantiate()
		var ap: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
		_check("%s has its cower clip %s" % [md[0].get_file(), md[3]], ap.has_animation(md[1] + md[3]))
		body.free()
	var host := CharacterBody3D.new()
	root.add_child(host)
	var model: Node3D = load(N.MODELS[0][0]).instantiate()
	model.set_script(Anim)
	model.prefix = N.MODELS[0][1]
	host.add_child(model)
	await process_frame
	var map_ap: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	model.freeze(N.MODELS[0][3], N.MODELS[0][4])
	await process_frame
	await process_frame
	_check("frozen on the cower clip, paused", model.frozen and map_ap.assigned_animation == N.MODELS[0][1] + N.MODELS[0][3] and not map_ap.is_playing())
	model.unfreeze()
	await process_frame
	_check("unfrozen: back to idle, playing", not model.frozen and map_ap.current_animation == N.MODELS[0][1] + "Idle" and map_ap.is_playing())
	host.free()
	var corpse := DeadBody.new()
	root.add_child(corpse)
	var dm: Node3D = load(N.MODELS[0][0]).instantiate()
	dm.set_script(Anim)
	dm.prefix = N.MODELS[0][1]
	corpse.add_child(dm)
	var dap: AnimationPlayer = dm.find_children("*", "AnimationPlayer", true, false)[0]
	var end := Time.get_ticks_msec() + int((dap.get_animation(N.MODELS[0][1] + "Death").length + 0.6) * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
	_check("a corpse stays down: Death plays once", dap.assigned_animation == N.MODELS[0][1] + "Death" and not dap.is_playing())
	corpse.free()

	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


## A building as the city has them: a body under a node named "Building...".
func _building(name: String, center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var holder := Node3D.new()
	holder.name = name
	root.add_child(holder)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	holder.add_child(body)
	body.global_position = center
	body.rotation.y = yaw


class DeadBody extends CharacterBody3D:
	var is_dead := true


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
