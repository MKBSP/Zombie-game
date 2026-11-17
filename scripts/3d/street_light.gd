@tool
class_name StreetLight
extends Node3D
## One 3D street light: a cobra-head lamp on a 7 m pole, built from primitives.
## Origin = pole foot on the pavement, -Z = toward the road (the arm reaches out
## that way). Drop one in a scene (Add Node -> StreetLight) or let
## scripts/3d/street_lights.gd line the kerbs with them.
##
## State AUTO rolls the state from the lamp's position (roll()), so the same map
## gives the same lamps on every machine without syncing anything. Odds come
## from Balance.STREET_LIGHTS and blend from "calm" to "wrecked" by a slow noise
## over the map. Fallen lamps come in four builds (lean, snapped, toppled,
## folded), each with its own random angle / break height / direction, and may
## keep live, sparking wires. A shot to the lens shatters it (shatter()): the
## glass bursts and the lamp goes dark, or sparks. Checked headless by
## test/test_street_lights.gd.

const B := preload("res://scripts/balance.gd")  # consts only: works in the editor too
const ImpactFx := preload("res://scripts/3d/impact_fx.gd")

enum State { AUTO, WORKING, BLINKING, DEAD, SPARKING, LEANING, SNAPPED, TOPPLED, FOLDED }
const FALLEN := [State.LEANING, State.SNAPPED, State.TOPPLED, State.FOLDED]
const KIND := {working = State.WORKING, blinking = State.BLINKING, dead = State.DEAD, sparking = State.SPARKING}

const H := 7.0         # pole height
const R0 := 0.1        # pole radius at the foot
const R1 := 0.055      # ... and at the top
const LENS := Vector3(0.0, 0.09, -1.9)  # lens centre, from the pole top
const VIEWMODEL_LAYER := 2  # first-person arms have their own lights (viewmodel.gd)
const DEBRIS_LAYER := 16    # physics layer 5: hit by bullet rays (all layers), not by bodies (mask 1)

@export var state: State = State.AUTO:
	set(v):
		state = v
		if is_inside_tree():
			_build()
## Change to get another roll (variant, angles) at the same spot.
@export var salt := 0:
	set(v):
		salt = v
		if is_inside_tree():
			_build()

var kind: State = State.WORKING  # the state actually built (AUTO resolved)
var shattered := false
var _light: SpotLight3D
var _lens: MeshInstance3D
var _lens_box: StaticBody3D
var _sparks: GPUParticles3D
var _flash: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _lit := false
var _target := false
var _stutter := false
var _t := 0.0
var _st := 0.0

static var _mats := {}
static var _noise: FastNoiseLite


## Map damage 0 (calm) .. 1 (wrecked) at a world position: slow single-octave
## simplex, stretched so patches read as clearly lit or clearly smashed.
static func damage_at(pos: Vector3) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = B.STREET_LIGHTS.seed
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_noise.frequency = 1.0 / B.STREET_LIGHTS.decay_zone_m
	return smoothstep(-0.45, 0.45, _noise.get_noise_2d(pos.x, pos.z))


## Deterministic roll for a lamp at `pos`: the state plus every random number
## its build needs. damage < 0 = take it from damage_at().
static func roll(pos: Vector3, salt_ := 0, damage := -1.0) -> Dictionary:
	var S: Dictionary = B.STREET_LIGHTS
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([S.seed, salt_, roundi(pos.x * 10.0), roundi(pos.z * 10.0)])
	if damage < 0.0:
		damage = damage_at(pos)
	var w := {}
	var total := 0.0
	for k: String in S.calm:
		w[k] = lerpf(S.calm[k], S.wrecked[k], damage)
		total += w[k]
	var pick := rng.randf() * total
	var st: int = State.WORKING
	for k: String in w:
		pick -= w[k]
		if pick < 0.0:
			st = FALLEN[rng.randi() % FALLEN.size()] if k == "fallen" else KIND[k]
			break
	return {
		state = st,
		yaw = rng.randf_range(-1.2, 1.2),  # fall direction, 0 = straight into the road
		t = rng.randf(),                   # lean angle / break height, per build
		t2 = rng.randf(),
		side = 1.0 if rng.randf() < 0.5 else -1.0,
		sparks = rng.randf() < S.fallen_sparks,
		glass = rng.randf() >= S.smashed_glass,
		tint = rng.randf_range(-1.0, 1.0),
	}


func _ready() -> void:
	_build()


func _build() -> void:
	for c in get_children():
		c.free()
	_light = null
	_sparks = null
	_lens_box = null
	_flash = null
	var r := roll(global_position, salt)
	kind = (r.state as State) if state == State.AUTO else state
	_rng.seed = hash([r.t, r.t2, salt])
	var d := Basis(Vector3.UP, r.yaw) * Vector3.FORWARD
	var fallen := kind in FALLEN
	var b := H  # break / bend height
	if kind == State.SNAPPED:
		b = lerpf(0.5, 2.2, r.t)
	elif kind == State.FOLDED:
		b = lerpf(1.8, 3.0, r.t)

	var lower := _node(self)
	_mesh(lower, _cyl(0.24, 0.24, 0.6), Vector3(0, -0.25, 0), "concrete")  # footing, mostly buried
	_segment(lower, 0.0, b, kind == State.TOPPLED)
	var upper := _node(self if kind == State.SNAPPED else lower)
	upper.position.y = b
	if b < H:
		_segment(upper, b, H, kind == State.SNAPPED or kind == State.FOLDED)
	var top := _node(upper)
	top.position.y = H - b
	_head(top, kind == State.WORKING or kind == State.BLINKING)

	match kind:
		State.LEANING:
			lower.basis = Basis(Vector3.UP.cross(d), deg_to_rad(lerpf(10.0, 32.0, r.t))) \
					* Basis(Vector3.UP, (r.t2 - 0.5) * 1.2)
			_scar(0.32)
		State.TOPPLED:  # uprooted, footing and all
			lower.transform = Transform3D(_tip(d, acos((0.1 - 0.25) / H), r.side, 0.35), Vector3(0, 0.25, 0))
			_scar(0.42)
		State.SNAPPED:  # stump stays, the rest lies beside it
			var jag := _mesh(lower, _cyl(0.02, _r(b), 0.14), Vector3(0, b + 0.05, 0), "metal")
			jag.rotation.z = 0.35  # torn metal at the break
			upper.transform = Transform3D(_tip(d, acos((0.08 - 0.12) / (H - b)), r.side, 0.3),
					Vector3(0, 0.12, 0) + d * lerpf(0.3, 1.0, r.t2))
		State.FOLDED:  # kinked, head hanging toward the pavement
			var t1 := deg_to_rad(lerpf(4.0, 12.0, r.t2))
			lower.basis = Basis(Vector3.UP.cross(d), t1)
			var bend_h := b * cos(t1)
			var th := acos(clampf((0.6 - bend_h) / (H - b), -1.0, 1.0))
			upper.basis = lower.basis.inverse() * _tip(d, th, r.side, 0.3)

	if _lens:
		_lens.visible = kind == State.WORKING or kind == State.BLINKING or (kind == State.DEAD and r.glass) \
				or (fallen and r.glass)
	if _lens.visible:
		_lens_box = LensHitbox.new()
		_lens_box.light = self
		_lens_box.collision_layer = DEBRIS_LAYER
		_lens_box.set_meta("surface", "glass")
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.22
		cs.shape = sh
		_lens_box.add_child(cs)
		_lens_box.position = LENS
		_lens.get_parent().add_child(_lens_box)
	if kind == State.WORKING or kind == State.BLINKING:
		var c: Color = B.STREET_LIGHTS.color
		_light.light_color = Color(c.r, c.g + r.tint * 0.04, c.b + r.tint * 0.06)
		_set_lit(true)
	if kind == State.SPARKING or (fallen and r.sparks):
		var at: Node3D = lower if kind == State.SNAPPED else top
		_make_sparks(at, Vector3(0, b + 0.1, 0) if kind == State.SNAPPED else LENS)
		_t = _rng.randf_range(0.2, 2.0)
	if kind == State.BLINKING:
		_t = _rng.randf_range(0.5, 5.0)
	set_process(_sparks != null or kind == State.BLINKING)


## The lens was shot: glass bursts, the light dies, and some lamps keep sparking.
## ponytail: local only; S10 has to replicate which lamps are shattered.
func shatter() -> void:
	if shattered or not _lens.visible:
		return
	shattered = true
	_lens_box.collision_layer = 0
	ImpactFx.spawn(self, _lens.global_position, Vector3.DOWN, "glass")
	_lens.visible = false
	if _light:
		_light.queue_free()
		_light = null
	if _rng.randf() < B.STREET_LIGHTS.shatter_spark_chance:
		kind = State.SPARKING
		if _sparks == null:
			_make_sparks(_lens.get_parent(), LENS)
		_t = 0.0
	else:
		kind = State.DEAD
	set_process(_sparks != null)


## The lens's hit zone: weapon rays land here (DEBRIS_LAYER, which bodies ignore).
class LensHitbox extends StaticBody3D:
	var light: Node3D

	func take_hit(_damage: float, _pos: Vector3, _dir: Vector3) -> void:
		light.shatter()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _flash:
		_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 50.0)
	_t -= delta
	if kind == State.BLINKING:
		_blink(delta)
	elif _t <= 0.0:  # spark burst; a third of them crackle twice in quick succession
		_sparks.restart()
		_flash.light_energy = _rng.randf_range(2.0, 5.0)
		_t = _rng.randf_range(0.06, 0.25) if _rng.randf() < 0.35 else _rng.randf_range(0.4, 3.5)


## Failing lamp: on for a while, stutters out, dark for a bit, stutters back.
func _blink(delta: float) -> void:
	if _stutter:
		_st -= delta
		if _st <= 0.0:
			_set_lit(not _lit)
			_st = _rng.randf_range(0.03, 0.15)
	if _t > 0.0:
		return
	if _stutter:
		_stutter = false
		_set_lit(_target)
		_t = _rng.randf_range(1.0, 7.0) if _target else _rng.randf_range(0.15, 3.5)
	else:
		_stutter = true
		_target = not _lit
		_t = _rng.randf_range(0.15, 0.9)


func _set_lit(on: bool) -> void:
	_lit = on
	_light.visible = on
	_lens.material_override = _mat("lens_on" if on else "lens_off")


# --- build helpers -----------------------------------------------------------

func _head(top: Node3D, lit: bool) -> void:
	_mesh(top, _sphere(0.08, 1.0), Vector3.ZERO, "metal")
	_rod(top, Vector3(0, 0.0, 0), Vector3(0, 0.16, -1.6), 0.035)
	var head := _mesh(top, _capsule(), Vector3(0, 0.15, -1.88), "metal")
	head.rotation.x = PI / 2
	head.scale = Vector3(1, 1, 0.45)
	_lens = _mesh(top, _sphere(0.14, 1.0), LENS, "lens_off")
	_lens.scale = Vector3(0.9, 0.25, 2.0)
	if not lit:
		return
	_light = SpotLight3D.new()
	_light.position = LENS + Vector3(0, -0.04, 0)
	_light.rotation.x = -PI / 2
	_light.visible = false
	var S: Dictionary = B.STREET_LIGHTS
	_light.light_energy = S.energy
	_light.spot_range = S.range_m
	_light.spot_angle = S.angle_deg
	_light.spot_angle_attenuation = 0.6
	_light.shadow_enabled = true
	_light.light_cull_mask = 0xFFFFF & ~VIEWMODEL_LAYER
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = S.fade_m
	_light.distance_fade_shadow = S.shadow_fade_m
	_light.distance_fade_length = 15.0
	top.add_child(_light)


func _make_sparks(parent: Node3D, at: Vector3) -> void:
	_sparks = GPUParticles3D.new()
	_sparks.position = at
	_sparks.amount = 36
	_sparks.lifetime = 1.4
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.explosiveness = 0.9
	_sparks.randomness = 0.5
	_sparks.collision_base_size = 0.02
	_sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	_sparks.visibility_aabb = AABB(Vector3(-5, -9, -5), Vector3(10, 11, 10))
	_sparks.process_material = _mat("spark_process")
	var q := QuadMesh.new()
	q.size = Vector2(0.02, 0.18)
	q.material = _mat("spark")
	_sparks.draw_pass_1 = q
	parent.add_child(_sparks)
	var floor_ := GPUParticlesCollisionBox3D.new()  # sparks bounce on the pavement
	floor_.size = Vector3(12, 0.4, 12)
	floor_.position.y = -0.2
	add_child(floor_)
	_flash = OmniLight3D.new()
	_flash.position = at
	_flash.light_color = Color(0.8, 0.88, 1.0)
	_flash.omni_range = 7.0
	_flash.light_energy = 0.0
	_flash.light_volumetric_fog_energy = 2.0
	_flash.light_cull_mask = 0xFFFFF & ~VIEWMODEL_LAYER
	parent.add_child(_flash)


## Tip the pole `angle` from vertical toward d, rolled so the arm lies sideways
## and a little up (never buried in the ground).
func _tip(d: Vector3, angle: float, side: float, lift: float) -> Basis:
	var axis := Vector3.UP.cross(d).normalized()
	var yaw := atan2(-d.x, -d.z) + side * PI / 2
	var bs := Basis(axis, angle) * Basis(Vector3.UP, yaw + lift)
	if (bs * Vector3.FORWARD).y < 0.0:
		bs = Basis(axis, angle) * Basis(Vector3.UP, yaw - lift)
	return bs


## Cracked pavement / dirt where the pole was torn or pushed.
func _scar(radius: float) -> void:
	_mesh(self, _cyl(radius, radius, 0.02), Vector3(0, 0.012, 0), "dirt")


## debris: a piece lying on / hanging near the ground. Bullets still hit it,
## but people and zombies step over it instead of snagging (DEBRIS_LAYER).
func _segment(parent: Node3D, y0: float, y1: float, debris := false) -> void:
	var h := y1 - y0
	_mesh(parent, _cyl(_r(y1), _r(y0), h), Vector3(0, h / 2, 0), "metal")
	var body := StaticBody3D.new()
	body.set_meta("surface", "metal")
	if debris:
		body.collision_layer = DEBRIS_LAYER
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = _r(y0)
	sh.height = h
	cs.shape = sh
	cs.position.y = h / 2
	body.add_child(cs)
	parent.add_child(body)


func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float) -> void:
	var mi := _mesh(parent, _cyl(radius, radius, a.distance_to(b)), (a + b) / 2, "metal")
	mi.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


func _r(y: float) -> float:
	return lerpf(R0, R1, y / H)


func _node(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = _mat(mat)
	parent.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 12
	m.rings = 1
	return m


func _sphere(radius: float, h_mult: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * h_mult
	m.radial_segments = 16
	m.rings = 8
	return m


func _capsule() -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = 0.17
	m.height = 0.8
	return m


## Shared materials, built once per run.
static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	if key == "spark_process":
		var p := ParticleProcessMaterial.new()
		p.direction = Vector3.DOWN
		p.spread = 80.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 4.5
		p.gravity = Vector3(0, -9.8, 0)
		p.damping_min = 0.3
		p.damping_max = 1.2
		p.scale_min = 0.5
		p.scale_max = 1.4
		p.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		p.collision_bounce = 0.3
		p.collision_friction = 0.4
		var g := Gradient.new()
		g.set_color(0, Color(14.0, 10.0, 5.0))
		g.set_color(1, Color(0, 0, 0))
		g.add_point(0.35, Color(9.0, 3.5, 0.8))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		gt.use_hdr = true
		p.color_ramp = gt
		m = p
	else:
		var s := StandardMaterial3D.new()
		match key:
			"metal":
				s.albedo_color = Color(0.2, 0.22, 0.21)
				s.metallic = 0.5
				s.roughness = 0.6
			"concrete":
				s.albedo_color = Color(0.42, 0.41, 0.39)
				s.roughness = 0.95
			"dirt":
				s.albedo_color = Color(0.09, 0.08, 0.07)
				s.roughness = 1.0
			"lens_on":
				s.albedo_color = Color(1.0, 0.9, 0.7)
				s.emission_enabled = true
				s.emission = B.STREET_LIGHTS.color
				s.emission_energy_multiplier = 8.0
			"lens_off":
				s.albedo_color = Color(0.3, 0.28, 0.25)
				s.roughness = 0.15
			"spark":
				s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				s.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
				s.vertex_color_use_as_albedo = true
				s.cull_mode = BaseMaterial3D.CULL_DISABLED
		m = s
	_mats[key] = m
	return m
