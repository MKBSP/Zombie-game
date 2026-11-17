extends SceneTree

## Headless check for scripts/3d/impact_fx.gd: which surface a shot hit, and that
## every surface has a look in Balance.IMPACT. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_impact_fx.gd

var _failures := 0


func _init() -> void:
	var F = load("res://scripts/3d/impact_fx.gd")
	var B = load("res://scripts/balance.gd")
	var o := Node.new()
	_check("floor is ground", F.surface_of(o, Vector3.UP) == "ground")
	_check("wall is wall", F.surface_of(o, Vector3.RIGHT) == "wall")
	_check("steep slope is wall", F.surface_of(o, Vector3(1, 0.5, 0).normalized()) == "wall")
	o.set_meta("surface", "metal")
	_check("meta wins over normal", F.surface_of(o, Vector3.UP) == "metal")
	_check("no collider is wall", F.surface_of(null, Vector3.RIGHT) == "wall")
	for s in ["ground", "wall", "metal", "glass", "wood"]:
		_check("%s has a look" % s, B.IMPACT.has(s))
	_check("glass leaves no hole", not B.IMPACT.glass.decal)
	for s in ["flesh", "gore"]:
		_check("%s bleeds onto what is behind, no hole" % s, B.IMPACT.has(s) and B.IMPACT[s].splat and not B.IMPACT[s].decal)
	o.free()
	# a burst must start idle (emitting = true then fires it; a fresh CPUParticles3D
	# already says true, so setting it again was a no-op and nothing ever showed)
	# and keep its per-particle scale (billboarding drops it otherwise: 1 m quads)
	var p: CPUParticles3D = F.particles(5, 1.0, null)
	_check("burst starts idle", not p.emitting)
	_check("billboard keeps particle scale", (p.mesh.surface_get_material(0) as StandardMaterial3D).billboard_keep_scale)
	p.free()
	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
