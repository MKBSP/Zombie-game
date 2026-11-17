extends RefCounted
## Where a shot or a bat lands: a burst shaped by the surface it hit
## (Balance.IMPACT: dust off ground and walls, sparks off metal, shards off
## glass, chips off wood) and, on most surfaces, a bullet hole. Shared by the
## shooter (viewmodel.gd) and armed survivors (npc_3d.gd), so their holes share
## one budget. A collider names its surface with meta "surface"; otherwise the
## hit normal decides ground vs wall. Checked headless by test/test_impact_fx.gd.

const B := preload("res://scripts/balance.gd")
const LOOT_LAYER := 64     # physics layer 7: pickups, seen only by the interact ray
## What a shot (gun, survivor, bat) can hit: everything but zombies' movement
## capsules (their part hitboxes take the hit) and loot on the ground.
const SHOT_MASK := 0xFFFFFFFF & ~(2 | LOOT_LAYER)

static var _hole_tex: Texture2D
static var _dot_tex: Texture2D   # soft round sprite, so bits read as dust and sparks, not squares
static var _blood_tex: Texture2D
static var _holes: Array = []   # oldest first, capped at IMPACT.decal_cap


static func surface_of(collider: Object, normal: Vector3) -> String:
	if collider and collider.has_meta("surface"):
		return collider.get_meta("surface")
	return "ground" if normal.y > 0.7 else "wall"


## Where effects go: the running scene (survives the shooter or unit that fired).
static func root_of(n: Node) -> Node:
	return n.get_tree().current_scene if n.get_tree().current_scene else n.get_tree().root


## `decal` false for hits that dent nothing (the bat). `dir` = the shot's travel
## direction: blood sprays on along it and splats on what is behind.
static func spawn(root: Node, pos: Vector3, normal: Vector3, surface: String, decal := true, dir := Vector3.ZERO) -> void:
	var s: Dictionary = B.IMPACT.get(surface, B.IMPACT.wall)
	if decal and s.decal:
		_hole(root, pos, normal)
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 32
		t.height = 32
		_dot_tex = t
	var p := particles(s.count, s.life, _dot_tex)
	p.direction = normal
	p.spread = 40.0
	p.initial_velocity_min = s.speed.x
	p.initial_velocity_max = s.speed.y
	p.gravity = Vector3(0, -s.gravity, 0)
	p.scale_amount_min = s.size.x
	p.scale_amount_max = s.size.y
	p.color = s.color
	(p.mesh.surface_get_material(0) as StandardMaterial3D).shading_mode = \
		BaseMaterial3D.SHADING_MODE_UNSHADED if s.unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	root.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	if s.get("splat", false):
		_splat(p, pos, dir if dir != Vector3.ZERO else Vector3.DOWN)


## A one-shot burst of billboard quads that frees itself when done. It starts
## idle: the caller adds it to the tree, places it, then sets emitting = true.
static func particles(amount: int, life: float, tex: Texture2D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false  # a new one already reports true, so the caller's "true" would do nothing
	p.one_shot = true
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := QuadMesh.new()
	pm.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true  # else every particle draws 1 m wide
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if tex:
		mat.albedo_texture = tex
	pm.material = mat
	p.mesh = pm
	p.finished.connect(p.queue_free)
	return p


## Blood on the first wall or floor within IMPACT.splat_m along `dir`.
static func _splat(at: Node3D, pos: Vector3, dir: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(pos, pos + dir.normalized() * B.IMPACT.splat_m, 1)
	var hit := at.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	if _blood_tex == null:  # a few overlapping blobs: reads as a splash, not a disc
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var blobs := [[Vector2(32, 32), 13.0]]
		for i in 9:
			var a := rng.randf() * TAU
			blobs.append([Vector2(32, 32) + Vector2(cos(a), sin(a)) * rng.randf_range(8, 24), rng.randf_range(2.0, 6.0)])
		for y in 64:
			for x in 64:
				var k := 0.0
				for b in blobs:
					k = maxf(k, clampf((b[1] - Vector2(x, y).distance_to(b[0])) / 2.0, 0.0, 1.0))
				img.set_pixel(x, y, Color(0.3, 0.01, 0.01, k * 0.9))
		_blood_tex = ImageTexture.create_from_image(img)
	_place(at.get_parent(), _blood_tex, B.IMPACT.splat_size_m, hit.position, hit.normal)


static func _hole(root: Node, pos: Vector3, normal: Vector3) -> void:
	if _hole_tex == null:  # dark core, scorched rim
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var r := Vector2(x - 31.5, y - 31.5).length() / 32.0
				var a := 1.0 if r < 0.22 else clampf(1.0 - (r - 0.22) / 0.3, 0.0, 1.0) * 0.7
				img.set_pixel(x, y, Color(0.03, 0.03, 0.03, a) if r < 0.22 else Color(0.12, 0.11, 0.1, a))
		_hole_tex = ImageTexture.create_from_image(img)
	_place(root, _hole_tex, 0.12, pos, normal)


## A decal of `size` metres lying on the surface at pos; oldest goes past the cap.
static func _place(root: Node, tex: Texture2D, size: float, pos: Vector3, normal: Vector3) -> void:
	var dec := Decal.new()
	dec.texture_albedo = tex
	dec.size = Vector3(size, 0.3, size)
	var y := normal.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	root.add_child(dec)
	dec.global_transform = Transform3D(Basis(x, y, x.cross(y)), pos)
	_holes = _holes.filter(is_instance_valid)  # a scene reload frees them
	_holes.append(dec)
	if _holes.size() > B.IMPACT.decal_cap:
		_holes.pop_front().queue_free()
