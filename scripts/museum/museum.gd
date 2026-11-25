extends Node3D
## Test museum (scenes/museum/museum.tscn), opened from the main menu's TEST
## MUSEUM. One open-air hall, built in code so new assets need no scene edits:
##   zoo (north)    every character, zombie variant, weapon, loot item, street-light
##                  state and assets/props model, with signs. Rows are filled by
##                  listing the asset folders, so a dropped-in .glb just shows up.
##   lab (centre)   L opens the lighting panel: sun / moon / ambient / fog, three
##                  presets, carryable lights (G grabs and drops), facade sliders.
##   facades (south) every city facade variant on the real city shader.
##   survivors (east) three survivors and three crates in the open.
## The shared rig (scenes/game/rig.tscn) gives the shooter, commander, HUDs and
## the ESC menu, whose "Go to" list calls areas() / go().
## Plan: docs/superpowers/plans/2026-11-25-3d-game.md, phase 2.

const Prop3D := preload("res://scripts/3d/prop_3d.gd")
const Fire3D := preload("res://scripts/3d/fire_3d.gd")
const Flicker := preload("res://scripts/test/flicker_light.gd")
const StreetLight := preload("res://scripts/3d/street_light.gd")
const ZombieBody := preload("res://scripts/3d/zombie_body.gd")
const Npc := preload("res://scripts/3d/npc_3d.gd")
const Crate := preload("res://scripts/3d/loot_crate.gd")
const Pickup3D := preload("res://scripts/3d/pickup_3d.gd")
const BUILDING := preload("res://shader/city_building.gdshader")
const GRID := preload("res://shader/grid_floor.gdshader")

const GRAB_LAYER := 256  # physics layer 9: only the G ray looks at it
const ROW_W := 80.0      # zoo rows wrap past this width
const AREAS := {
	"LIGHTING LAB": [Vector3(0, 0, 8), 0.0],
	"ZOO": [Vector3(0, 0, -6), 0.0],
	"FACADE WALL": [Vector3(0, 0, 18), PI],
	"SURVIVORS + CRATES": [Vector3(46, 0, 0), -PI / 2],
}
## Weapon models fitted to a real length (m), as pickup_3d / npc_3d do.
const WEAPON_LEN := {pistol = 0.22, uzi = 0.4, shotgun = 0.95, rifle = 1.1, bat = 0.85, fp_arms = 0.7}
## Hit FX per street prop (default metal); vehicles are all metal.
const SURFACE := {cinder_block = "wall", pallet = "wood", damaged_couch = "wood",
	construction_barrier = "wood", traffic_barrier = "wood", traffic_barrier_b = "wood",
	trash_bag = "ground", trash_bags = "ground", plastic_barrier = "ground", traffic_cone = "ground"}
## Shown again burnt and burning.
const BURNS := ["vehicles", "street/dumpster", "street/container_green", "street/barrel", "street/trash_can"]
## 24-patch colour chart, standard sRGB values, row by row.
const CHART := ["735244", "c29682", "627a9d", "576c43", "8580b1", "67bdaa",
	"d67e2c", "505ba6", "c15a63", "5e3c6c", "9dbc40", "e0a32e",
	"383d96", "469449", "af363c", "e7c71f", "bb5695", "0885a1",
	"f3f3f2", "c8c8c8", "a0a0a0", "7a7a79", "555555", "343434"]

var _city: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _player: Node3D
var _hud: Node
var _loot: Node3D
var _spin: Array = []
var _facade_mats: Array = []
var _panel: CanvasLayer
var _sliders := {}
var _carry: Node3D = null


# ------------------------------------------------------------------ setup

func _enter_tree() -> void:
	# Before the rig's commander bakes the navmesh from City in its _ready.
	var cmd := get_node("Rig/Commander")
	cmd.spawn_horde = false
	cmd.spawn_npcs = false
	cmd.spawn_crates = false
	_city = get_node("City")
	_build_floor()
	_build_facades()
	_wall("Building_cover_a", Vector3(72, 0, -12), Vector3(0.4, 3.0, 24.0))
	_wall("Building_cover_b", Vector3(60, 0, -14), Vector3(12.0, 3.0, 0.4))


func _ready() -> void:
	_env = $WorldEnvironment.environment
	_player = get_node("Rig/TestPlayer")
	_hud = get_node("Rig/TuningHUD")
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.shadow_enabled = true
	_sun.visible = false
	add_child(_sun)
	_loot = Node3D.new()
	_loot.name = "Loot"
	add_child(_loot)
	_build_zoo()
	_lookdev_stand(Vector3(-5, 0, 3))
	_build_panel()
	go("LIGHTING LAB")
	(func() -> void: _moon().light_energy = _sliders.moon.value).call_deferred()
	_after_navmesh()


func _after_navmesh() -> void:
	var map := get_world_3d().navigation_map
	for f in 600:  # the bake is threaded; query only once the map has synced
		if NavigationServer3D.map_get_iteration_id(map) > 0 \
				and NavigationServer3D.map_get_closest_point(map, Vector3(50, 0, 0)) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	for i in 3:
		var npc = Npc.new()
		npc.model = i
		npc.position = Vector3(54, 0, -5 + i * 5)
		add_child(npc)
	_reset_loot()


## Crates by the survivors, plus the zoo's loot row (closed crate, opened crate,
## one of every pickup). The lab's RESET LOOT puts them all back.
func _reset_loot() -> void:
	for c in _loot.get_children():
		c.queue_free()
	for i in 3:
		var c = Crate.new()
		c.rng.seed = 11 + i
		c.guarantee_weapon = i == 0
		c.position = Vector3(64, 0, -5 + i * 5)
		_loot.add_child(c)
	var z := -22.0
	_sign("LOOT", Vector3(-13.5, 0, z), 1.4, HORIZONTAL_ALIGNMENT_RIGHT, _loot)
	var shut = Crate.new()
	shut.position = Vector3(-11, 0, z)
	_loot.add_child(shut)
	_sign("crate", Vector3(-11, 0, z + 0.8), 0.6, HORIZONTAL_ALIGNMENT_CENTER, _loot)
	var opened = Crate.new()
	opened.rng.seed = 3
	opened.position = Vector3(-7, 0, z)
	_loot.add_child(opened)
	opened.open()
	_sign("crate, opened", Vector3(-7, 0, z + 0.8), 0.6, HORIZONTAL_ALIGNMENT_CENTER, _loot)
	var x := -2.0
	for k in Pickup3D.Kind.size():
		Pickup3D.drop(_loot, Vector3(x, 0.05, z), k)
		_sign(Pickup3D.Kind.keys()[k].to_lower(), Vector3(x, 0, z + 0.8), 0.6, HORIZONTAL_ALIGNMENT_CENTER, _loot)
		x += 3.0


# ------------------------------------------------------------- the hall

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(220, 1, 180)
	shape.position.y = -0.5
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(220, 180)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = GRID
	mi.material_override = mat
	body.add_child(mi)
	body.position = Vector3(0, 0, 10)
	_city.add_child(body)
	for x in range(-50, 51, 5):  # metre rulers along the two axes through spawn
		_floor_mark(str(x), Vector3(x, 0.01, 12))
	for z in range(-70, 91, 5):
		_floor_mark(str(z), Vector3(-48, 0.01, z))


func _floor_mark(t: String, at: Vector3) -> void:
	var l := Label3D.new()
	l.text = t
	l.font_size = 48
	l.pixel_size = 0.006
	l.rotation_degrees.x = -90
	l.modulate = Color(0.1, 0.1, 0.1)
	l.outline_size = 0
	l.position = at
	_city.add_child(l)


## A plain grey wall: cover for the survivors, and a "Building" for zombie sight.
func _wall(n: String, at: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = at + Vector3(0, size.y / 2, 0)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	mi.add_child(body)
	_city.add_child(mi)


## One row per wall type (city_building.gdshader `side`), each with brick and
## stucco at 7, 13 and 19 m. Same vertex data the Blender city build bakes:
## UV = metres (along, up), UV2 = (length, height), COLOR.rg = seeds.
func _build_facades() -> void:
	var rows := [[3, "SHOP STREET"], [2, "RESIDENTIAL STREET"], [1, "ALLEY"], [0, "BACK / YARD"], [4, "PARTY WALL (ghost signs)"]]
	var n := 0
	for r in rows.size():
		var side: int = rows[r][0]
		var mat := ShaderMaterial.new()
		mat.shader = BUILDING
		mat.set_shader_parameter("side", side)
		_facade_mats.append(mat)
		var z := 26.0 + r * 16.0
		_sign(rows[r][1], Vector3(-38, 0, z - 1.5), 1.4, HORIZONTAL_ALIGNMENT_RIGHT)
		var x := -36.0
		for brick in [true, false]:
			for h in [7.0, 13.0, 19.0]:
				n += 1
				var seed := fposmod(sin(n * 12.9898) * 43758.5453, 1.0)
				_facade(n, Vector3(x, 0, z), 10.0, h, seed, 0.3 if brick else 0.9, mat)
				_sign("%s %d m" % ["brick" if brick else "stucco", int(h)], Vector3(x + 5, 0, z - 1.0))
				x += 12.0
	var roof := ShaderMaterial.new()
	roof.shader = BUILDING
	roof.set_shader_parameter("is_roof", true)
	_facade_mats.append(roof)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	mi.mesh = pm
	mi.material_override = roof
	mi.position = Vector3(40, 0.03, 26)
	_city.add_child(mi)
	_sign("ROOF", Vector3(40, 0, 20))


func _facade(n: int, at: Vector3, length: float, height: float, seed: float, seed2: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0, 0), Vector2(length, 0), Vector2(length, height), Vector2(0, height)]
	for i in [0, 2, 1, 0, 3, 2]:
		var c: Vector2 = corners[i]
		st.set_normal(Vector3(0, 0, -1))  # faces the lab (north)
		st.set_uv(c)
		st.set_uv2(Vector2(length, height))
		st.set_color(Color(seed, seed2, 0.5, 1.0))
		st.add_vertex(Vector3(c.x, c.y, 0))
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Building_facade_%d" % n
	mi.mesh = mesh
	mi.position = at
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(length, height, 0.3)
	shape.position = Vector3(length / 2, height / 2, 0.15)
	body.add_child(shape)
	mi.add_child(body)
	_city.add_child(mi)


# ------------------------------------------------------------------ zoo

func _build_zoo() -> void:
	# characters + zombie variants, idling on turntables
	var people := [["adventurer", "res://assets/characters/adventurer.glb", "CharacterArmature|", 1.0]]
	for m in Npc.MODELS:
		people.append([m[0].get_file().get_basename(), m[0], m[1], m[2]])
	var row := []
	for p in people:
		var model: Node3D = load(p[1]).instantiate()
		model.scale = Vector3.ONE * p[3]
		for ap: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
			if ap.has_animation(p[2] + "Idle"):
				ap.play(p[2] + "Idle")
		row.append([_spinner(model), 2.0, p[0]])
	for v in ["standard", "fast", "fat", "master"]:
		var zb = ZombieBody.new()
		var holder := _spinner(zb)
		row.append([holder, 2.0, "zombie, " + v])
		zb.set_meta("variant", ["standard", "fast", "fat", "master"].find(v))
	_row("CHARACTERS", -10.0, row)
	for item in row:  # zombie bodies need to be in the tree before setup()
		for zb in item[0].get_children():
			if zb.has_meta("variant"):
				zb.setup(zb, zb.get_meta("variant"))
				zb.set_hittable(false)

	# weapons on pedestals
	row = []
	for f: String in _glbs("res://assets/weapons"):
		var base := f.get_file().get_basename()
		var holder := Node3D.new()
		_pedestal(holder)
		var model: Node3D = load(f).instantiate()
		holder.add_child(model)
		row.append([holder, 1.6, base, model, WEAPON_LEN.get(base, 0.8)])
	_row("WEAPONS", -16.0, row)
	for item in row:
		_fit(item[3], item[4], Vector3(0, 1.0, 0))

	# street lights, one per state, arm pointing along the row
	row = []
	for s in StreetLight.State.size():
		if s == StreetLight.State.AUTO:
			continue
		var lamp = StreetLight.new()
		lamp.state = s
		lamp.rotation.y = PI / 2
		row.append([lamp, 6.0, StreetLight.State.keys()[s].to_lower()])
	_row("STREET LIGHTS", -30.0, row)

	# props: every model under assets/props/<category>, then the burnables again
	var z := -40.0
	for cat in ["street", "vehicles", "nature"]:
		row = []
		for f: String in _glbs("res://assets/props/" + cat):
			row.append(_prop(f, Prop3D.State.INTACT))
		z = _row(cat.to_upper(), z, row) - 10.0
	for st in [Prop3D.State.BURNT, Prop3D.State.BURNING]:
		row = []
		for cat in ["vehicles", "street"]:
			for f: String in _glbs("res://assets/props/" + cat):
				if BURNS.any(func(b): return f.contains("/props/" + b)):
					row.append(_prop(f, st))
		z = _row(("BURNT" if st == Prop3D.State.BURNT else "BURNING"), z, row) - 10.0


## [node, width, label] for one assets/props model in the given state.
func _prop(path: String, st: int) -> Array:
	var p = Prop3D.new()
	var base := path.get_file().get_basename()
	var vehicle := path.contains("/vehicles/")
	p.surface = "metal" if vehicle else SURFACE.get(base, "metal")
	p.solid = not path.contains("/nature/")
	p.state = st
	p.model = load(path)
	if vehicle:
		p.rotation.y = PI / 2  # side on
	return [p, -1.0, base]


## Lays out [node, width (-1 = measure), label] in lines of at most ROW_W
## metres, each line centred on x = 0 (rows run north, toward -Z). Returns the
## z of the last line used.
func _row(title: String, z: float, items: Array) -> float:
	var z0 := z
	var sized := []  # [node, width, depth, label]
	for it in items:
		var node: Node3D = it[0]
		_city.add_child(node)
		var w: float = it[1]
		var d := 2.0
		if w < 0.0:  # a Prop3D: its bounds, turned with it
			var box := _bounds(node)
			w = box.size.x
			d = box.size.z
		sized.append([node, w, d, it[2]])
	var lines := [[]]
	var lw := 0.0
	for it in sized:
		if lw + it[1] > ROW_W and not lines[-1].is_empty():
			lines.append([])
			lw = 0.0
		lines[-1].append(it)
		lw += it[1] + 1.5
	var left := ROW_W / 2
	for line in lines:
		var width := -1.5
		var depth := 0.0
		for it in line:
			width += it[1] + 1.5
			depth = maxf(depth, it[2])
		var x := -width / 2
		left = minf(left, x)
		for it in line:
			it[0].position += Vector3(x + it[1] / 2, 0, z)
			_sign(it[3], Vector3(x + it[1] / 2, 0, z + it[2] / 2 + 0.8))
			x += it[1] + 1.5
		if line != lines[-1]:
			z -= depth + 4.0
		else:
			z -= depth
	_sign(title, Vector3(left - 1.5, 0, z0), 1.4, HORIZONTAL_ALIGNMENT_RIGHT)
	return z


func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (n.global_transform.affine_inverse() * m.global_transform) * m.get_aabb()
		b = Transform3D(n.basis, Vector3.ZERO) * b
		box = b if first else box.merge(b)
		first = false
	return box


func _spinner(model: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.add_child(model)
	_spin.append(holder)
	return holder


func _pedestal(holder: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.2, 1.0, 0.6)
	mi.mesh = bm
	mi.position.y = 0.5
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = bm.size
	body.add_child(shape)
	mi.add_child(body)
	holder.add_child(mi)


## Scale `model` so its longest side is `length` m and stand it at `at`.
func _fit(model: Node3D, length: float, at: Vector3) -> void:
	var box := _bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest <= 0.0:
		return
	if box.size.z > box.size.x:
		model.rotation.y += PI / 2  # side on to the viewer, not end on
	model.scale *= length / longest
	box = _bounds(model)
	model.position = at - Vector3(box.get_center().x, box.position.y, box.get_center().z)


func _glbs(dir: String) -> Array:
	var out := []
	for f in ResourceLoader.list_directory(dir):
		if f.ends_with(".glb"):
			out.append(dir.path_join(f))
	return out


func _sign(t: String, at: Vector3, size := 0.6, align := HORIZONTAL_ALIGNMENT_CENTER, parent: Node = null) -> void:
	var l := Label3D.new()
	l.text = t.to_upper()
	l.font = UIStyle.font(UIStyle.FONT_MONO)
	l.font_size = 64
	l.pixel_size = size / 160.0
	l.outline_size = 12
	l.horizontal_alignment = align
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y  # readable from any side
	l.position = at + Vector3(0, 0.3 if size < 1.0 else 0.8, 0)
	(parent if parent else _city).add_child(l)


# -------------------------------------------------------- lighting lab

func _lookdev_stand(at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "LookdevStand"
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.03
	cm.height = 1.3
	post.mesh = cm
	post.position.y = 0.65
	root.add_child(post)
	for i in 2:  # 18% grey (linear) and chrome
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		ball.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.46, 0.46, 0.46) if i == 0 else Color.WHITE
		m.metallic = 0.0 if i == 0 else 1.0
		m.roughness = 0.6 if i == 0 else 0.03
		ball.material_override = m
		ball.position = Vector3(-0.2 + i * 0.4, 1.45, 0)
		root.add_child(ball)
	for i in CHART.size():
		var patch := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.1, 0.1, 0.02)
		patch.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(CHART[i])
		m.roughness = 0.9
		patch.material_override = m
		patch.position = Vector3(-0.275 + (i % 6) * 0.11, 1.15 - (i / 6) * 0.11, 0.05)
		root.add_child(patch)
	root.position = at
	_grabbable(root, Vector3(0.8, 1.7, 0.4))
	add_child(root)
	return root


func _add_light(kind: String) -> void:
	var at := _ahead(3.0)
	var root
	match kind:
		"lamp":
			root = Node3D.new()
			var pole := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.03
			cm.bottom_radius = 0.04
			cm.height = 2.2
			pole.mesh = cm
			pole.position.y = 1.1
			root.add_child(pole)
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.08
			sm.height = 0.16
			bulb.mesh = sm
			var m := StandardMaterial3D.new()
			m.emission_enabled = true
			m.emission = Color(1, 0.8, 0.55)
			m.emission_energy_multiplier = 4.0
			bulb.material_override = m
			bulb.position.y = 2.25
			root.add_child(bulb)
			var light := OmniLight3D.new()
			light.set_script(Flicker)
			light.light_color = Color(1, 0.8, 0.55)
			light.light_energy = 3.0
			light.omni_range = 10.0
			light.shadow_enabled = true
			light.shimmer = 0.35
			light.dip_chance = 1.2
			light.position.y = 2.25
			root.add_child(light)
		"fire":
			root = Prop3D.new()
			root.state = Prop3D.State.BURNING
			root.model = load("res://assets/props/street/barrel.glb")
		"street":
			root = StreetLight.new()
			root.state = StreetLight.State.WORKING
			root.rotation.y = PI / 2
		"stand":
			_lookdev_stand(at)
			return
	root.position = at
	_grabbable(root, Vector3(0.8, 2.0, 0.8))
	add_child(root)


## An Area3D on GRAB_LAYER so G's ray can find it (bullets and bodies ignore it).
func _grabbable(root: Node3D, size: Vector3) -> void:
	var a := Area3D.new()
	a.collision_layer = GRAB_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.set_meta("grab_root", root)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	shape.position.y = size.y / 2
	a.add_child(shape)
	root.add_child(a)


func _ahead(dist: float) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	var p := cam.global_position + fwd.normalized() * dist
	return Vector3(p.x, 0.0, p.z)


func _grab() -> void:
	if _carry:
		_carry = null
		return
	var cam := get_viewport().get_camera_3d()
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 8.0, GRAB_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider.has_meta("grab_root"):
		_carry = hit.collider.get_meta("grab_root")


func _process(delta: float) -> void:
	for s in _spin:
		s.rotation.y += 0.35 * delta
	if is_instance_valid(_carry):
		_carry.global_position = _ahead(2.5)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_node("Rig/Commander").active:
		return
	match (event as InputEventKey).keycode:
		KEY_G:
			_grab()
		KEY_L:
			_panel.visible = not _panel.visible
			_free_mouse(_panel.visible)


## Sliders need the cursor: free it like the old ESC did; clicking the world
## (unhandled LMB) captures it again (test_player.gd).
func _free_mouse(on: bool) -> void:
	_player.set("_mouse_freed", on)
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_panel() -> void:
	_panel = CanvasLayer.new()
	_panel.layer = 8
	_panel.visible = false
	add_child(_panel)
	var box := PanelContainer.new()
	box.theme = get_window().theme
	box.theme_type_variation = "ModalPanel"
	box.position = Vector2(14, 14)
	box.custom_minimum_size = Vector2(300, 0)
	_panel.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	_head(v, "LIGHT   [L] CLOSE")
	var presets := HBoxContainer.new()
	v.add_child(presets)
	for p in ["NIGHT", "TORCH", "DAY"]:
		var b := Button.new()
		b.text = p
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_preset.bind(p))
		presets.add_child(b)
	_slider(v, "sun", "Sun strength", 0.0, 3.0, 0.0, func(x: float) -> void:
		_sun.light_energy = x
		_sun.visible = x > 0.0)
	_slider(v, "sun_h", "Sun height (deg)", 2.0, 90.0, 45.0, func(x: float) -> void: _sun.rotation_degrees.x = -x)
	_slider(v, "sun_d", "Sun direction (deg)", 0.0, 360.0, 30.0, func(x: float) -> void: _sun.rotation_degrees.y = x)
	_slider(v, "moon", "Moon strength", 0.0, 1.0, 0.08, func(x: float) -> void:
		var m := _moon()
		if m:
			m.light_energy = x)
	_slider(v, "amb", "Ambient", 0.0, 1.5, _env.ambient_light_energy, func(x: float) -> void: _env.ambient_light_energy = x)
	_slider(v, "fog", "Haze (distance fog)", 0.0, 0.1, _env.fog_density, func(x: float) -> void:
		_env.fog_density = x
		_env.fog_enabled = x > 0.0)
	_slider(v, "mist", "Mist (volumetric)", 0.0, 0.1, _env.volumetric_fog_density, func(x: float) -> void:
		_env.volumetric_fog_density = x
		_env.volumetric_fog_enabled = x > 0.0)

	_head(v, "ADD A LIGHT   [G] GRAB / DROP")
	for k in [["lamp", "FLICKERING LAMP"], ["fire", "FIRE"], ["street", "STREET LIGHT"], ["stand", "GREY + CHROME BALL, CHART"]]:
		var b := Button.new()
		b.text = k[1]
		b.pressed.connect(_add_light.bind(k[0]))
		v.add_child(b)

	_head(v, "FACADES (city_building shader)")
	_slider(v, "lit", "Lit windows", 0.0, 1.0, 0.26, _facade_param.bind("lit_windows"))
	_slider(v, "wglow", "Window glow", 0.0, 10.0, 3.5, _facade_param.bind("window_glow"))
	_slider(v, "sglow", "Shop glow", 0.0, 6.0, 1.8, _facade_param.bind("shop_glow"))
	_slider(v, "signg", "Sign glow", 0.0, 6.0, 2.2, _facade_param.bind("sign_glow"))
	_slider(v, "shop", "Shop chance", 0.0, 1.0, 0.35, _facade_param.bind("shop_chance"))

	_head(v, "LOOT")
	var reset := Button.new()
	reset.text = "RESET CRATES + LOOT"
	reset.pressed.connect(_reset_loot)
	v.add_child(reset)


func _head(v: Control, t: String) -> void:
	var l := Label.new()
	l.text = t
	l.theme_type_variation = "MicroLabel"
	l.add_theme_color_override("font_color", UIStyle.INFECTION)
	v.add_child(MenuWidgets.spacer(6.0))
	v.add_child(l)


func _slider(v: Control, key: String, label: String, lo: float, hi: float, val: float, cb: Callable) -> void:
	var l := Label.new()
	l.theme_type_variation = "MicroLabel"
	v.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 200.0
	s.value_changed.connect(func(x: float) -> void:
		l.text = "%s: %.3f" % [label, x]
		cb.call(x))
	v.add_child(s)
	_sliders[key] = s
	s.value = val
	l.text = "%s: %.3f" % [label, val]
	cb.call(val)


func _facade_param(x: float, param: String) -> void:
	for m in _facade_mats:
		m.set_shader_parameter(param, x)


func _moon() -> DirectionalLight3D:
	return get_node_or_null("Rig/Moon")


func _preset(p: String) -> void:
	var day := p == "DAY"
	_env.background_color = Color(0.45, 0.58, 0.75) if day else Color(0.008, 0.011, 0.02)
	_env.ambient_light_color = Color(0.62, 0.66, 0.75) if day else Color(0.09, 0.11, 0.17)
	_hud.set("adapt_gain", 1.0 if day else 2.0)  # no "eyes adjusting" in daylight
	_player.set("flashlight_enabled", not day)
	_sliders.sun.value = 1.3 if day else 0.0
	_sliders.moon.value = 0.08 if p == "NIGHT" else 0.0
	_sliders.amb.value = {NIGHT = 0.04, TORCH = 0.0, DAY = 0.5}[p]
	_sliders.fog.value = 0.0 if day else 0.022
	_sliders.mist.value = 0.0 if day else 0.05


# ------------------------------------------------------- ESC menu: Go to

func areas() -> Array:
	return AREAS.keys()


func go(area: String) -> void:
	var a: Array = AREAS[area]
	_player.global_position = a[0]
	_player.set("aim_yaw", a[1])
	_player.rotation.y = a[1]
