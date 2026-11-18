extends Node3D
## First-person arms + weapons for the 3D test player. Child of the player's
## Camera3D (scenes/test/camera_test_v6_small_city.tscn).
##
## Keys 1-8 / mouse wheel: hands, torch, pistol, pistol + torch, shotgun, rifle,
## uzi, bat. LMB fires (uzi: hold) or swings, RMB aims (owned by test_player),
## R reloads, F toggles the torch (test_hud), T refills ammo (test convenience).
## Two-handed weapons mean no torch: test_player.torch_in_hand goes false.
## Rules are the 2D ones (scripts/3d/fp_loadout.gd + Balance); shots are hitscan
## from the eye through a random point in the player's reticle volume.
##
## How it is put together:
##  * Drawn at VIEW_SCALE and that much closer, with the camera near plane
##    pulled in: identical from the eye, but the gun never pokes into a wall.
##    Anything that must live in the WORLD (torch beam + light, muzzle light,
##    smoke, shells) is placed where the viewmodel APPEARS to be: _apparent().
##  * Viewmodel geometry sits on render layer VIEWMODEL_LAYER. World lights skip
##    that layer (no torch lighting its own handle); the arms get their own dim
##    fill, torch spill and muzzle-flash lights instead.
##  * Drawn through its own fixed FOV (VM_FOV), whatever the camera's: no
##    stretched forearms at the screen edge, and the gun doesn't zoom with ADS.
##  * Arms are skinned (assets/weapons/fp_arms.glb, baked by
##    assets/blender/other/build_fp_arms.py). Each frame a hand is put exactly on
##    its grip and the forearm is aimed at a fixed elbow point off-screen; the
##    wrist and elbow bones bend to fit. Recoil / reload / swing motion on the
##    weapon carries the hands with it.
##  * Recoil is springs (kick fast, settle slower): one on the gun (push back into
##    the shoulder + muzzle climb), one on the view (punch that mostly returns,
##    plus a small permanent climb from Balance.FP).

const L := preload("res://scripts/3d/fp_loadout.gd")
const W := preload("res://scripts/weapons.gd")
const MeleeMath := preload("res://scripts/melee.gd")
const ImpactFx := preload("res://scripts/3d/impact_fx.gd")
const Zombie3D := preload("res://scripts/3d/zombie_3d.gd")
const Pickup3D := preload("res://scripts/3d/pickup_3d.gd")
const ARMS: PackedScene = preload("res://assets/weapons/fp_arms.glb")

const VIEW_SCALE := 0.1
const VIEWMODEL_LAYER := 2           # keep in sync with test_player.VIEWMODEL_LAYER
const INTERACT_LAYER := 64           # = ImpactFx.LOOT_LAYER: pickups; only the interact ray sees them
const WORLD_LAYERS := 0xFFFFF & ~VIEWMODEL_LAYER
const VM_FOV := 62.0
const VM_FOV_ADS := 50.0
## Forearms aim at these (off-screen, below and behind the hands); the short
## upper-arm stub points from the elbow to the shoulder.
const ELBOW_R := Vector3(0.30, -0.50, 0.15)
const ELBOW_L := Vector3(-0.30, -0.50, 0.15)
## Aimed: elbows drop and splay, so the forearms leave the bottom of the
## screen on a diagonal instead of standing under the gun like a pillar.
const ELBOW_R_ADS := Vector3(0.22, -0.45, 0.12)
const ELBOW_L_ADS := Vector3(-0.22, -0.45, 0.12)
## Shouldered long gun: the trigger elbow goes out to the side.
const ELBOW_R_STOCK := Vector3(0.40, -0.35, 0.05)
const SHOULDER_R := Vector3(0.18, -0.24, 0.12)
const SHOULDER_L := Vector3(-0.18, -0.24, 0.12)
const FOREARM_M := 0.27
## Arm bones per side: upper, fore, hand, knuckle root, then two finger roots
## that give the palm's width (pinky side, index side).
const BONES := {
	L = ["UpperArm.L", "LowerArm.L", "Hand.L", "DoubleFingersBeginning", "DoubleFingers.L", "Index.L"],
	R = ["UpperArm.R.001", "LowerArm.R.001", "Hand.R.001", "DoubleFingersBeginning.001", "DoubleFingers.R.001", "Index.R.001"],
}
## Fist-hole centre relative to the palm origin, in the hand frame.
const FIST := Vector3(0.0, -0.03, -0.02)
const TORCH_LENS := Vector3(0.0, 0.0, -0.085)
const HOLSTER_TIME := 0.18
const DRAW_TIME := 0.22
const ADS_TIME := 0.22
const SIGHT_DROP := -0.012           # sight sits just under screen centre when aimed
const BEAM_LENGTH := 4.0           # visible shaft only; the fog carries the beam further
const PUNCH_K := 150.0               # view-punch spring stiffness
const PUNCH_ZETA := 0.7
const GUN_ZETA := 0.5

## Weapon models: "Weapons Pack 002 – In Case of Zombies" by CreativeTrio (CC0).
## They ship lying on their side (muzzle -Z, top -X); points are in that raw
## model space, measured off a top-down render. _ready stands them up.
## recoil = peak displacement of the gun spring: back/up (m), pitch/yaw/roll (deg,
## yaw + roll randomised), k = stiffness (higher = snappier).
## flash = [star size, flame length] (m); smoke = puff count.
const MODELS := {
	W.PISTOL: {scene = "res://assets/weapons/pistol.glb", scale = 0.44,
		grip_r = Vector3(0.103, 0, 0.125), axis_r = Vector3(-0.85, 0, -0.5),
		muzzle = Vector3(-0.045, 0, -0.21), sight = Vector3(-0.065, 0, -0.05), ads_dist = 0.55,
		eject = Vector3(-0.058, 0, -0.07), flash = [0.11, 0.13], smoke = 3,
		recoil = {back = 0.03, up = 0.006, pitch = 9.0, yaw = 1.5, roll = 3.0, k = 220.0}},
	W.SHOTGUN: {scene = "res://assets/weapons/shotgun.glb", scale = 0.48,
		grip_r = Vector3(0.14, 0, 0.224), axis_r = Vector3(-0.7, 0, -0.7),
		grip_l = Vector3(0.048, 0, -0.37), axis_l = Vector3(0, 0, -1),
		muzzle = Vector3(-0.011, 0, -1.18), sight = Vector3(-0.03, 0, -0.3), ads_dist = 0.36,
		breech = Vector3(-0.02, 0, -0.1), flash = [0.24, 0.36], smoke = 8,
		recoil = {back = 0.07, up = 0.012, pitch = 16.0, yaw = 2.0, roll = 5.0, k = 110.0}},
	W.RIFLE: {scene = "res://assets/weapons/rifle.glb", scale = 0.5,
		grip_r = Vector3(0.143, 0, 0.27), axis_r = Vector3(-0.7, 0, -0.7),
		grip_l = Vector3(0.044, 0, -0.39), axis_l = Vector3(0, 0, -1),
		muzzle = Vector3(0.0, 0, -1.29), sight = Vector3(-0.088, 0, -0.08), ads_dist = 0.3,
		eject = Vector3(-0.03, 0, 0.05), flash = [0.15, 0.26], smoke = 4,
		recoil = {back = 0.06, up = 0.01, pitch = 12.0, yaw = 1.5, roll = 3.0, k = 130.0}},
	W.MACHINEGUN: {scene = "res://assets/weapons/uzi.glb", scale = 0.44,
		grip_r = Vector3(0.213, 0, 0.29), axis_r = Vector3(-0.8, 0, -0.6),
		grip_l = Vector3(0.05, 0, -0.25), axis_l = Vector3(0, 0, -1),
		muzzle = Vector3(-0.02, 0, -0.556), sight = Vector3(-0.09, 0, 0.0), ads_dist = 0.42,
		eject = Vector3(-0.075, 0, 0.02), flash = [0.08, 0.10], smoke = 1,
		recoil = {back = 0.014, up = 0.003, pitch = 3.5, yaw = 1.5, roll = 2.0, k = 330.0}},
	W.MELEE: {scene = "res://assets/weapons/bat.glb", scale = 0.46,
		grip_r = Vector3(0, 0, 0.40), axis_r = Vector3(0, 0, -1),
		grip_l = Vector3(0, 0, 0.58), axis_l = Vector3(0, 0, -1),
		muzzle = Vector3(0, 0, -1.0), sight = Vector3.ZERO, ads_dist = 0.3},
}
## Hip poses of the held item's grip in camera space: [position, euler degrees].
const HIP := {
	L.PISTOL: [Vector3(0.14, -0.16, -0.34), Vector3(2, 4, 0)],
	L.PISTOL_TORCH: [Vector3(0.14, -0.16, -0.34), Vector3(2, 4, 0)],
	L.SHOTGUN: [Vector3(0.14, -0.17, -0.30), Vector3(3, 5, 0)],
	L.RIFLE: [Vector3(0.13, -0.17, -0.28), Vector3(3, 5, 0)],
	L.UZI: [Vector3(0.13, -0.16, -0.28), Vector3(3, 6, 0)],
}
const TORCH_HIP := [Vector3(0.15, -0.15, -0.38), Vector3(2, 5, 0)]
const TORCH_ADS := [Vector3(0.10, -0.13, -0.42), Vector3(0, 2, 0)]
## Pistol + torch. At the hip the torch is out on the left, overhand, apart from
## the gun (how Amnesia: The Bunker etc. show it: each hand readable on its own
## side). Aiming brings it under the gun wrist into the Harries hold: backs of
## the hands together, torch parallel to the barrel and tipped up a touch so
## light and sights meet. TORCH_SIDE is camera space; HARRIES is the torch
## origin in the pistol's grip frame.
const TORCH_SIDE := [Vector3(-0.15, -0.14, -0.40), Vector3(3, -4, 0)]
const HARRIES := [Vector3(0.0, -0.07, -0.01), Vector3(4, 0, 0)]
## Ice-pick grip point on the torch: right at the tail cap (thumb on the switch),
## so the body sticks out forward from the little-finger side.
const TORCH_TAIL := Vector3(0.0, 0.0, 0.085)
## Open hands for loadout 1: [position, thumb direction].
const OPEN_R := [Vector3(0.19, -0.19, -0.36), Vector3(-0.6, 0.6, -0.5)]
const OPEN_L := [Vector3(-0.19, -0.19, -0.36), Vector3(0.6, 0.6, -0.5)]
## Bat swing: [time s, grip position, euler degrees, easing INTO this key].
## Short wind-up (starts from a cocked pose so it reads without lag), a strike
## that accelerates into contact, follow-through, slower recovery.
const SWING := [
	[0.00, Vector3(0.20, -0.24, -0.36), Vector3(50, 35, -15), ""],
	[0.10, Vector3(0.26, -0.12, -0.26), Vector3(105, 35, 15), "out"],
	[0.16, Vector3(0.18, -0.15, -0.42), Vector3(20, -60, -60), "in"],
	[0.20, Vector3(0.02, -0.20, -0.48), Vector3(5, 5, -80), "lin"],
	[0.30, Vector3(-0.22, -0.26, -0.34), Vector3(-10, 100, -80), "out"],
	[0.44, Vector3(-0.02, -0.26, -0.40), Vector3(40, 60, -35), "inout"],
	[0.62, Vector3(0.20, -0.24, -0.36), Vector3(50, 35, -15), "inout"],
]
const SWING_HIT := 0.20
const SWING_TRAIL := Vector2(0.10, 0.34)   # time window the swoosh is drawn
const HITSTOP := 0.07


class Spring:
	extends RefCounted
	var x := Vector3.ZERO
	var v := Vector3.ZERO
	var k := 150.0
	var zeta := 0.5

	func _init(stiffness: float, damping: float) -> void:
		k = stiffness
		zeta = damping

	## Peak displacement `peak` -> launch velocity, for an impulse kick.
	func kick(peak: Vector3) -> void:
		v += peak * sqrt(k) / (0.46 if zeta > 0.6 else 0.55)

	func step(dt: float) -> void:
		var c := 2.0 * zeta * sqrt(k)
		var left := minf(dt, 0.1)
		while left > 0.0:
			var h := minf(left, 1.0 / 240.0)
			v += (-k * x - c * v) * h
			x += v * h
			left -= h


@export var player_path: NodePath = ^"../../../TestPlayer"
@export var start_loadout: int = L.START

var loadout := L.START
var heavy := -1          # carried heavy: Weapons.SHOTGUN / RIFLE / MACHINEGUN, or -1
var melee := -1          # Weapons.MELEE when the bat is carried
var cheat := false       # debug builds, F9: every weapon, no carry limit, T refills
var _player: CharacterBody3D
var _cam: Camera3D
var _rig: Node
var _base_aim_fov := 45.0
var _geo: Node3D         # all viewmodel geometry (hidden while scoped)
var _arms := {}          # "R_grip" / "R_open" / "L_grip" / "L_open" -> MeshInstance3D
var _rigs := {}          # "grip" / "open" -> {skel, L: {bones, rests, palm frame}, R: ...}
var _vm_k := 1.0         # X/Y stretch that turns the camera's FOV into VM_FOV
var _torch: MeshInstance3D
var _lens: StandardMaterial3D
var _anchor: Marker3D    # torch lens where it APPEARS: the beam starts here
var _w := {}             # weapon id -> {holder, muzzle, sight, grip_l, axis_r, axis_l, eject, breech}
var _ammo := {}          # weapon id -> {mag, reserve}
var _pending := -1
var _sw := 0.0           # 0 drawn .. 1 fully holstered
var _ads := 0.0
var _cooldown := 0.0
var _reload_left := 0.0
var _reload_total := 1.0
var _gun_pos := Spring.new(220.0, GUN_ZETA)
var _gun_rot := Spring.new(220.0, GUN_ZETA)
var _punch := Spring.new(PUNCH_K, PUNCH_ZETA)
var _shake := 0.0
var _swing := -1.0
var _swing_hit_done := false
var _swing_whoosh := false
var _hitstop := 0.0
var _next_swing := 0.0
var _melee_hits: Array[float] = []
var _fatigued := false
var _trail: Array = []   # [[head, mid], ...] in viewmodel space, newest last
var _trail_mesh: ImmediateMesh
var _sway := Vector2.ZERO
var _prev_look := Vector2.ZERO
var _bob := 0.0
var _flash_t := 9.0      # seconds since the last shot
var _flash_dur := 0.04
var _flash_root: Node3D
var _flash_star: MeshInstance3D
var _flash_flame: MeshInstance3D
var _flash_world: OmniLight3D
var _flash_vm: OmniLight3D
var _fill: OmniLight3D
var _spill: OmniLight3D
var _beam: MeshInstance3D
var _beam_mesh: CylinderMesh
var _smoke_tex: Texture2D
var _shells: Array[Node3D] = []
var _hud_ammo: Label
var _hud_hp: Label
var _hurt: ColorRect        # red flash on each bite
var _dead: Label
var _last_hp := -1
var _scope: ColorRect
var _marker: Control        # hitmarker: four ticks around the crosshair
var _prompt: Label          # "E  open crate" etc. under the crosshair
var _marker_t := 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_cam = get_parent() as Camera3D
	if _player == null or _cam == null:
		push_warning("viewmodel: needs a Camera3D parent and player_path")
		set_process(false)
		return
	_rig = _cam.get_parent()
	_player.aim_pitch_range = Balance.FP.pitch_deg
	if _rig != null and "aim_fov" in _rig:
		_base_aim_fov = _rig.aim_fov
	_cam.near = 0.01
	scale = Vector3.ONE * VIEW_SCALE
	_geo = Node3D.new()
	add_child(_geo)
	_build_arms()
	_build_weapons()
	_build_flash()
	_build_lights()
	_build_hud()
	for id in MODELS:
		_ammo[id] = L.new_ammo(id)
	for g: GeometryInstance3D in _geo.find_children("*", "GeometryInstance3D", true, false):
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.layers = VIEWMODEL_LAYER
	_prev_look = _look()
	_show(start_loadout)


# --- build -------------------------------------------------------------------

func _build_arms() -> void:
	var src := ARMS.instantiate()
	for pose in ["grip", "open"]:
		var skel := src.find_child("Arms_" + pose, true, false).find_child("Skeleton3D", false, false) as Skeleton3D
		skel.get_parent().remove_child(skel)
		for n in [skel] + skel.find_children("*", "", true, false):
			n.owner = null
		_geo.add_child(skel)
		var rig := {skel = skel}
		for side in ["L", "R"]:
			var b: Array = BONES[side].map(func(n: String) -> int: return skel.find_bone(n))
			var g: Array = b.map(func(i: int) -> Transform3D: return skel.get_bone_global_rest(i))
			# rest palm frame, same convention as the hand targets: fingers -Z, palm -Y
			var fingers: Vector3 = (g[3].origin - g[2].origin).normalized()
			var across: Vector3 = g[4].origin - g[5].origin
			var palm: Vector3 = fingers.cross(across).normalized() * (1.0 if side == "R" else -1.0)
			var y := -palm
			var z := -fingers
			rig[side] = {upper = b[0], fore = b[1], hand = b[2],
				upper_rest = g[0], fore_rest = g[1], hand_rest = g[2],
				palm = Transform3D(Basis(y.cross(z), y, z).orthonormalized(), g[2].origin.lerp(g[3].origin, 0.55)),
				fore_len = g[2].origin.distance_to(g[1].origin), upper_len = g[1].origin.distance_to(g[0].origin)}
			_arms[side + "_" + pose] = skel.get_node("Arm%s_%s" % [side, pose])
		skel.scale = Vector3.ONE * (FOREARM_M / rig.R.fore_len)
		_rigs[pose] = rig
	# the source skin/gloves are 40% metallic and the skin glossy: plastic hot
	# spots and black shading. Matte cloth and skin instead.
	for m: MeshInstance3D in _arms.values():
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i) as StandardMaterial3D
			if mat != null:
				mat.metallic = 0.0
				mat.roughness = maxf(mat.roughness, 0.8)
	_torch = src.find_child("Torch", true, false) as MeshInstance3D
	_torch.owner = null
	_torch.get_parent().remove_child(_torch)
	_geo.add_child(_torch)
	src.free()
	# the lens glows while the torch is on, so the light visibly comes from it
	for i in _torch.mesh.get_surface_count():
		var m := _torch.mesh.surface_get_material(i) as StandardMaterial3D
		if m != null and m.resource_name == "LightBlue":
			_lens = m.duplicate() as StandardMaterial3D
			_lens.emission_enabled = true
			_lens.emission = Color(1.0, 0.95, 0.82)
			_torch.set_surface_override_material(i, _lens)
	_anchor = Marker3D.new()
	_anchor.top_level = true
	add_child(_anchor)
	_trail_mesh = ImmediateMesh.new()
	var trail := MeshInstance3D.new()
	trail.mesh = _trail_mesh
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.cull_mode = BaseMaterial3D.CULL_DISABLED
	tm.vertex_color_use_as_albedo = true
	trail.material_override = tm
	_geo.add_child(trail)


func _build_weapons() -> void:
	var up := Basis(Vector3(0, 0, 1), -PI / 2)  # raw model top (-X) -> +Y
	for id in MODELS:
		var m: Dictionary = MODELS[id]
		var b: Basis = up.scaled(Vector3.ONE * m.scale)
		var holder := Node3D.new()
		holder.name = "Weapon%d" % id
		var model: Node3D = load(m.scene).instantiate()
		model.transform = Transform3D(b, -(b * m.grip_r))
		holder.add_child(model)
		# the pack imports everything 40% metallic (wood too); near-black guns
		# then read as flat silhouettes. Less metal, broader highlights.
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
				if mat != null:
					mat.metallic = 0.15
					mat.roughness = 0.55
		_geo.add_child(holder)
		_w[id] = {
			holder = holder,
			muzzle = b * (m.muzzle - m.grip_r),
			sight = b * (m.sight - m.grip_r),
			grip_l = b * (m.get("grip_l", m.grip_r) - m.grip_r),
			axis_r = up * m.axis_r,
			axis_l = up * m.get("axis_l", Vector3.FORWARD),
			eject = b * (m.eject - m.grip_r) if m.has("eject") else null,
			breech = b * (m.breech - m.grip_r) if m.has("breech") else null,
		}


## Muzzle flash, drawn with the gun (so it never clips): a camera-facing star
## for the burst plus two crossed flame planes along the barrel, which is what
## actually reads from behind the gun. Additive + HDR so the glow catches it.
func _build_flash() -> void:
	_flash_root = Node3D.new()
	_geo.add_child(_flash_root)
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_mat.billboard_keep_scale = true
	star_mat.albedo_texture = _star_texture()
	star_mat.albedo_color = Color(3.0, 2.5, 1.8)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_flash_star = MeshInstance3D.new()
	_flash_star.mesh = quad
	_flash_star.material_override = star_mat
	_flash_root.add_child(_flash_star)

	# two quads crossing along -Z: base at the muzzle (v=0), tip forward (v=1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [Vector3.RIGHT, Vector3.UP]:
		var a: Vector3 = side * 0.5
		var quad_pts := [[-a, Vector2(0, 0)], [a, Vector2(1, 0)], [a + Vector3.FORWARD, Vector2(1, 1)], [-a + Vector3.FORWARD, Vector2(0, 1)]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad_pts[i][1])
			st.add_vertex(quad_pts[i][0])
	var flame_mat := star_mat.duplicate() as StandardMaterial3D
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame_mat.albedo_texture = _flame_texture()
	_flash_flame = MeshInstance3D.new()
	_flash_flame.mesh = st.commit()
	_flash_flame.material_override = flame_mat
	_flash_root.add_child(_flash_flame)
	_flash_root.visible = false

	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var soft := GradientTexture2D.new()
	soft.gradient = grad
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	_smoke_tex = soft


## Five-point burst: hot white core, thin rays, orange rim.
func _star_texture() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / (n * 0.5) - 1.0, (y + 0.5) / (n * 0.5) - 1.0)
			var r := p.length()
			var ang := p.angle()
			var rays := 0.0
			for i in 5:
				var d := absf(wrapf(ang - (i * TAU / 5.0 + 0.3), -PI, PI))
				rays = maxf(rays, exp(-pow(d * (2.0 + r * 14.0), 2.0)) * exp(-r * 2.4))
			var core := exp(-r * r / 0.012)
			var glow := exp(-r * r / 0.10) * 0.35
			var a := clampf(core + rays * 0.9 + glow, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, r))
			var hot := clampf(core * 1.6 + rays * 0.4, 0.0, 1.0)
			var c := Color(1.0, 0.45, 0.12).lerp(Color(1.0, 0.95, 0.78), hot)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


## Flame tongue: wide and white-hot at the muzzle (row 0), narrowing to an
## orange tip, with a ragged edge.
func _flame_texture() -> Texture2D:
	var wdt := 64
	var hgt := 128
	var img := Image.create(wdt, hgt, false, Image.FORMAT_RGBA8)
	for y in hgt:
		var v := float(y) / (hgt - 1)
		var width := 0.55 * pow(1.0 - v, 0.55) * (0.85 + 0.3 * sin(v * 23.0) * sin(v * 7.0)) + 0.04
		for x in wdt:
			var u := absf((x + 0.5) / (wdt * 0.5) - 1.0)
			var a := (1.0 - smoothstep(width * 0.35, width, u)) * pow(1.0 - v, 1.3) * smoothstep(0.0, 0.04, v)
			var c := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.4, 0.08), clampf(v * 1.4 + u, 0.0, 1.0))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


func _omni(color: Color, mask: int) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.top_level = true
	l.shadow_enabled = false
	l.light_color = color
	l.light_cull_mask = mask
	l.light_energy = 0.0
	if mask == VIEWMODEL_LAYER:
		# a few cm from the arms 1/d falloff would multiply it ~30x: keep it flat
		l.omni_attenuation = 0.0
	add_child(l)
	return l


## World lights live where the viewmodel APPEARS; viewmodel lights live at the
## tiny geometry and only touch VIEWMODEL_LAYER.
func _build_lights() -> void:
	_flash_world = _omni(Color(1.0, 0.72, 0.38), WORLD_LAYERS)
	_flash_world.omni_range = 6.0
	_flash_vm = _omni(Color(1.0, 0.75, 0.42), VIEWMODEL_LAYER)
	_flash_vm.omni_range = 0.15
	_fill = _omni(Color(0.62, 0.7, 0.9), VIEWMODEL_LAYER)
	_fill.omni_range = 0.25
	_fill.light_energy = 0.45
	_spill = _omni(Color(1.0, 0.95, 0.85), VIEWMODEL_LAYER)
	_spill.omni_range = 0.05

	# visible torch beam: an additive cone, soft against geometry, faint dust
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = 0.0
	_beam_mesh.height = BEAM_LENGTH
	_beam_mesh.cap_top = false
	_beam_mesh.cap_bottom = false
	_beam_mesh.radial_segments = 32
	_beam_mesh.rings = 8
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.96, 0.86);
uniform float intensity = 0.22;
uniform float beam_length = 12.0;
uniform float soft = 0.6;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
varying float t_axis;
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), u.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { t_axis = (0.5 * beam_length - VERTEX.y) / beam_length; }
void fragment() {
	float along = smoothstep(0.0, 0.03, t_axis) * (1.0 - smoothstep(0.1, 0.85, t_axis));
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -sv.z / sv.w;
	float fade = clamp((scene_z + VERTEX.z) / soft, 0.0, 1.0);
	float dust = 0.65 + 0.35 * n(vec2(UV.x * 14.0, t_axis * 9.0 - TIME * 0.12));
	float dither = (h(FRAGCOORD.xy) - 0.5) * 0.004;  // breaks up 8-bit banding
	ALBEDO = max(color * intensity * along * facing * fade * dust + dither, vec3(0.0));
}"""
	var bm := ShaderMaterial.new()
	bm.shader = sh
	bm.set_shader_parameter("beam_length", BEAM_LENGTH)
	_beam = MeshInstance3D.new()
	_beam.top_level = true
	_beam.mesh = _beam_mesh
	_beam.material_override = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.layers = VIEWMODEL_LAYER  # the shooter's own view: drawn after the commander's fog, it showed through it anywhere
	add_child(_beam)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_scope = ColorRect.new()
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float aspect = 1.78;
void fragment() {
	vec2 p = vec2((UV.x - 0.5) * aspect, UV.y - 0.5);
	float outside = smoothstep(0.43, 0.445, length(p));
	float hair = step(abs(p.y), 0.0012) + step(abs(p.x), 0.0012);
	COLOR = vec4(0.0, 0.0, 0.0, max(outside, clamp(hair, 0.0, 1.0) * 0.85));
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_scope.material = sm
	_scope.visible = false
	layer.add_child(_scope)
	var ls := LabelSettings.new()
	ls.font_size = 20
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.85)
	_hud_ammo = Label.new()
	_hud_ammo.label_settings = ls
	_hud_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_ammo.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hud_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud_ammo.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hud_ammo.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud_ammo.position = Vector2(-24, -20)
	layer.add_child(_hud_ammo)
	_hud_hp = Label.new()
	_hud_hp.label_settings = ls
	_hud_hp.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hud_hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_hp.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)  # bottom-left is the minimap
	_hud_hp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud_hp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hud_hp.position.y = -20
	layer.add_child(_hud_hp)
	_hurt = ColorRect.new()
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.6, 0.0, 0.0, 0.0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hurt)
	_dead = Label.new()
	_dead.label_settings = ls
	_dead.set_anchors_preset(Control.PRESET_CENTER)
	_dead.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead.text = "YOU DIED - the zombies win\nENTER to restart"
	_dead.visible = false
	layer.add_child(_dead)
	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_CENTER)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var tick := Line2D.new()
		tick.width = 2.5
		tick.points = PackedVector2Array([d * 7.0, d * 15.0])
		_marker.add_child(tick)
	_marker.modulate.a = 0.0
	layer.add_child(_marker)
	var ps := LabelSettings.new()
	ps.font_size = 16
	ps.outline_size = 5
	ps.outline_color = Color(0, 0, 0, 0.85)
	_prompt = Label.new()
	_prompt.label_settings = ps
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.position.y = 40
	layer.add_child(_prompt)


## Colour and size of the hitmarker for a Zombie3D.Hit; empty = no marker.
static func marker_look(result) -> Dictionary:
	var M: Dictionary = Balance.FP.hitmarker
	match result:
		Zombie3D.Hit.HIT:
			return {color = M.hit, scale = 1.0}
		Zombie3D.Hit.LIMB:
			return {color = M.limb, scale = 1.0}
		Zombie3D.Hit.KILL:
			return {color = M.kill, scale = M.kill_scale}
	return {}


func _mark(result) -> void:
	var look := marker_look(result)
	if look.is_empty():
		return
	_marker.modulate = look.color
	_marker.scale = Vector2.ONE * look.scale
	_marker_t = Balance.FP.hitmarker.show_s


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _player.get("is_dead"):
		if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ENTER:
			get_tree().reload_current_scene()
		return
	if event.is_action_pressed("interact"):
		_interact()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_8:
			select(k - KEY_1)
		elif k == KEY_R:
			_try_reload()
		elif k == KEY_T and cheat:
			for id in MODELS:
				_ammo[id] = L.new_ammo(id)
		elif k == Balance.FP.cheat_key and OS.is_debug_build():
			cheat = not cheat
			if cheat:
				for id in MODELS:
					_ammo[id] = L.new_ammo(id)
			else:
				select(L.fallback(_target(), _avail()))
	elif event is InputEventMouseButton and event.pressed:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(_cycle(-1))
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(_cycle(1))
		elif b.button_index == MOUSE_BUTTON_LEFT and _captured():
			_trigger()


func select(n: int) -> void:
	if n == _target() or not n in _avail():
		return
	_pending = n
	_reload_left = 0.0  # switching cancels a reload, as in 2D


func _target() -> int:
	return _pending if _pending >= 0 else loadout


func _avail() -> Array:
	return L.available(heavy, melee, cheat)


## Next / previous selectable loadout (the wheel).
func _cycle(step: int) -> int:
	var av := _avail()
	return av[posmod(av.find(_target()) + step, av.size())]


## Pick up weapon `id` and draw it: fresh ammo, or `ammo` ({mag, reserve}) when
## a survivor hands it back. Carry rules in fp_loadout.take(); returns the weapon
## dropped to make room (-1 = none).
func give(id: int, ammo := {}) -> int:
	var t: Dictionary = L.take(heavy, melee, id)
	heavy = t.heavy
	melee = t.melee
	_ammo[id] = ammo if not ammo.is_empty() else L.new_ammo(id)
	select(L.WEAPON.find(id))
	return t.dropped


func add_pistol_mag() -> void:
	_ammo[W.PISTOL].reserve += W.get_data(W.PISTOL).mag_size


func _captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Camera-space point/transform of the drawn viewmodel -> where it appears in
## the world (undoes VIEW_SCALE and the VM_FOV stretch; -Z is kept exact).
func _apparent(local: Transform3D) -> Transform3D:
	var t := _cam.global_transform * Transform3D(Basis.from_scale(Vector3(_vm_k, _vm_k, 1.0)), Vector3.ZERO) * local
	return Transform3D(Basis.looking_at(-t.basis.z, t.basis.y), t.origin)


## What the interact ray (E) points at within reach: a crate, a pickup, a
## survivor, or a wall (nothing to do). Pickups sit on INTERACT_LAYER only.
func _interact_target() -> Object:
	var from := _cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from - _cam.global_transform.basis.z * Balance.NPC_3D.give_m, 1 | 8 | INTERACT_LAYER)
	q.exclude = [_player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return null if hit.is_empty() else hit.collider


func _interact() -> void:
	var c := _interact_target()
	if c == null:
		return
	if c.has_method("open"):
		c.open()
	elif c.has_method("collect"):
		c.collect(self)
	elif c.has_method("receive_weapon") and c.get("shooter") == _player:
		_hand_over(c)


func _prompt_text(c: Object) -> String:
	if c == null:
		return ""
	if c.has_method("open"):
		return "" if c.opened else "E  open crate"
	if c.has_method("collect"):
		return "E  take " + c.label()
	if c.has_method("receive_weapon") and c.get("shooter") == _player:
		if c.weapon_id != -1:
			return "E  take back " + L.NAMES[L.WEAPON.find(c.weapon_id)]
		if _giveable() != -1:
			return "E  give " + L.NAMES[L.WEAPON.find(_giveable())]
	return ""


## The weapon in hand a follower may take: the carried heavy (any gun but the
## pistol under the cheat), else -1.
func _giveable() -> int:
	var id: int = L.WEAPON[_target()]
	if id < 0 or id == W.PISTOL or id == W.MELEE or not (id == heavy or cheat):
		return -1
	return id


## A follower gets the heavy in your hand with its ammo, as in 2D; E on an
## armed follower takes it back (your current heavy, if different, drops).
func _hand_over(npc: Object) -> void:
	if npc.weapon_id != -1:
		var d: Dictionary = npc.surrender_weapon()
		var mag: int = mini(W.get_data(d.id).mag_size, d.total)
		var dropped := give(d.id, {mag = mag, reserve = d.total - mag})
		if dropped != -1:
			_drop(dropped)
		return
	var id := _giveable()
	if id == -1:
		return
	var a: Dictionary = _ammo[id]
	npc.receive_weapon(id, a.mag + a.reserve)
	if id == heavy:
		heavy = -1
	_ammo[id] = L.new_ammo(id)
	select(L.fallback(_target(), _avail()))


## A weapon you had to let go of lands at your feet.
func _drop(id: int) -> void:
	var fwd := -_cam.global_transform.basis.z
	fwd.y = 0.0
	Pickup3D.drop(_fx_root(), _player.global_position + fwd.normalized() * 0.7, Pickup3D.weapon_kind(id))


# --- per frame -----------------------------------------------------------------

## HP readout, a red flash per bite (stronger the closer to death), death screen.
func _update_health(delta: float) -> void:
	var hp: int = _player.get("hp") if _player.get("hp") != null else 0
	if _last_hp >= 0 and hp < _last_hp:
		_hurt.color.a = 0.25 + 0.3 * (1.0 - float(hp) / _player.max_hp)
	_last_hp = hp
	_hurt.color.a = 0.55 if _player.is_dead else move_toward(_hurt.color.a, 0.0, delta * 0.8)
	_hud_hp.text = "HP %d" % hp
	_hud_hp.modulate = Color(1, 0.35, 0.3) if hp < _player.max_hp * Balance.SHOOTER.injured_hp_frac else Color.WHITE
	_dead.visible = _player.is_dead


func _process(delta: float) -> void:
	_update_health(delta)
	_marker_t = maxf(_marker_t - delta, 0.0)
	_marker.modulate.a = _marker_t / Balance.FP.hitmarker.show_s
	_prompt.text = _prompt_text(_interact_target())
	if _player.get("is_dead"):
		_geo.visible = false
		return
	# switching: holster, swap at the bottom, draw
	if _pending >= 0:
		_sw = move_toward(_sw, 1.0, delta / HOLSTER_TIME)
		if _sw >= 1.0:
			_show(_pending)
			_pending = -1
	else:
		_sw = move_toward(_sw, 0.0, delta / DRAW_TIME)

	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reload_left = 0.0
			L.finish_reload(_ammo[L.WEAPON[loadout]], L.data(loadout))
	if loadout == L.UZI and _captured() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_trigger()
	_update_swing(delta)

	_ads = move_toward(_ads, 1.0 if (_player.aiming and loadout != L.BAT and loadout != L.EMPTY) else 0.0, delta / ADS_TIME)
	_gun_pos.step(delta)
	_gun_rot.step(delta)
	var before := _punch.x
	_punch.step(delta)
	var d := _punch.x - before
	_player.aim_pitch_offset = clampf(_player.aim_pitch_offset + d.x, -_player.aim_pitch_range, _player.aim_pitch_range)
	_player.aim_yaw += deg_to_rad(d.y)
	_shake *= exp(-16.0 * delta)
	_flash_t += delta

	var look := _look()
	var rate := (look - _prev_look) / maxf(delta, 0.001)
	_prev_look = look
	var want := Vector2(clampf(-rate.x * 0.012, -0.07, 0.07), clampf(-rate.y * 0.012, -0.07, 0.07))
	_sway = _sway.lerp(want, 1.0 - exp(-10.0 * delta))
	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_bob += delta * speed * 1.9

	# stretching X/Y by the tan ratio draws the viewmodel as if through VM_FOV
	var vm_fov := lerpf(VM_FOV, VM_FOV_ADS, smoothstep(0.0, 1.0, _ads))
	_vm_k = tan(deg_to_rad(_cam.fov) * 0.5) / tan(deg_to_rad(vm_fov) * 0.5)
	scale = Vector3(_vm_k, _vm_k, 1.0) * VIEW_SCALE

	_pose()
	_update_lights()
	_update_hud()


## [yaw, pitch] of the view in radians, for sway.
func _look() -> Vector2:
	return Vector2(_player.aim_yaw, deg_to_rad(_player.aim_pitch_offset))


func _show(n: int) -> void:
	loadout = n
	var id: int = L.WEAPON[n]
	for wid in _w:
		_w[wid].holder.visible = wid == id
	_torch.visible = L.has_torch(n)
	var two := L.two_handed(n)
	_arms.R_open.visible = n == L.EMPTY
	_arms.L_open.visible = n == L.EMPTY
	_arms.R_grip.visible = n != L.EMPTY
	_arms.L_grip.visible = two or n == L.PISTOL_TORCH
	var d := L.data(n)
	_player.spread_mult = L.spread_mult(d) if d != null and not d.is_melee else 1.0
	_player.torch_in_hand = L.has_torch(n)
	_player.light_anchor = _anchor if L.has_torch(n) else null
	_player.reticle_visible = id >= 0 and not d.is_melee  # only guns aim through it
	if _rig != null and "aim_fov" in _rig:
		_rig.aim_fov = Balance.FP.scope_fov if n == L.RIFLE else _base_aim_fov
	if id >= 0 and MODELS[id].has("recoil"):
		_gun_pos.k = MODELS[id].recoil.k
		_gun_rot.k = MODELS[id].recoil.k
	_swing = -1.0
	_trail.clear()


# --- posing --------------------------------------------------------------------

func _xf(pr: Array) -> Transform3D:
	var e: Vector3 = pr[1]
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z))), pr[0])


func _pose() -> void:
	var ads := smoothstep(0.0, 1.0, _ads)
	var k := smoothstep(0.0, 1.0, _sw)
	var amp := clampf(Vector2(_player.velocity.x, _player.velocity.z).length() / 3.0, 0.0, 1.6) * (1.0 - 0.8 * ads)
	var breathe := sin(Time.get_ticks_msec() * 0.0014) * 0.003
	var o := Transform3D(Basis(Vector3.RIGHT, -0.7 * k), Vector3(0, -0.3 * k, 0.05 * k))  # holster dip
	o *= Transform3D(Basis.from_euler(Vector3(_sway.y, _sway.x, _sway.x * 0.6)), Vector3(_sway.x * 0.08, _sway.y * 0.08, 0))
	o *= Transform3D(Basis(Vector3.FORWARD, sin(_bob) * 0.012 * amp),
		Vector3(sin(_bob) * 0.012 * amp, -absf(cos(_bob)) * 0.014 * amp + breathe, 0))
	if _shake > 0.01:
		var j := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
		o *= Transform3D(Basis.from_euler(j * 0.03), j * 0.008)

	var id: int = L.WEAPON[loadout]
	var reload := sin(PI * (1.0 - _reload_left / _reload_total)) if _reload_left > 0.0 else 0.0
	var wpose := Transform3D.IDENTITY
	if id >= 0:
		var w: Dictionary = _w[id]
		if loadout == L.BAT:
			wpose = o * _swing_pose(maxf(_swing, 0.0))
		else:
			var aimed := Transform3D(Basis(), Vector3(0, SIGHT_DROP, -MODELS[id].ads_dist) - w.sight)
			wpose = _xf(HIP[loadout]).interpolate_with(aimed, ads)
			wpose *= Transform3D(Basis.from_euler(Vector3(-0.5 * reload, 0, 0.45 * reload)), Vector3(0, -0.06 * reload, 0.03 * reload))
			# recoil spring, pivoting on the grip: back into the shoulder + muzzle climb
			var steady := 1.0 - 0.4 * ads
			wpose *= Transform3D(Basis.from_euler(_gun_rot.x * steady), _gun_pos.x)
			wpose = o * wpose
		w.holder.transform = wpose
		_flash_root.transform = Transform3D(wpose.basis, wpose * w.muzzle)

	var tpose := Transform3D.IDENTITY
	if loadout == L.TORCH:
		tpose = o * _xf(TORCH_HIP).interpolate_with(_xf(TORCH_ADS), ads)
	elif loadout == L.PISTOL_TORCH:
		# aimed, it rides on the pistol (hands pressed together), recoil and all
		tpose = (o * _xf(TORCH_SIDE)).interpolate_with(wpose * _xf(HARRIES), ads)
	if L.has_torch(loadout):
		_torch.transform = tpose

	var er := o * ELBOW_R.lerp(ELBOW_R_STOCK if L.two_handed(loadout) else ELBOW_R_ADS, ads)
	var el := o * ELBOW_L.lerp(ELBOW_L_ADS, ads)
	var back := wpose.basis * Vector3.BACK  # pistol grips: wrist straight behind the bore
	match loadout:
		L.EMPTY:
			_place("R", "open", o * OPEN_R[0], o.basis * OPEN_R[1], er)
			_place("L", "open", o * OPEN_L[0], o.basis * OPEN_L[1], el)
		L.TORCH:
			_place("R", "grip", tpose.origin, tpose.basis * Vector3.FORWARD, er)
		L.PISTOL, L.PISTOL_TORCH:
			_place("R", "grip", wpose.origin, wpose.basis * _w[id].axis_r, er, back)
			if loadout == L.PISTOL_TORCH:
				# ice-pick grip: torch out of the little-finger side, thumb on the tail cap
				_place("L", "grip", tpose * TORCH_TAIL, tpose.basis * Vector3.BACK, el)
		_:
			var w: Dictionary = _w[id]
			_place("R", "grip", wpose.origin, wpose.basis * w.axis_r, er, Vector3.ZERO if loadout == L.BAT else back)
			# reloading: the support hand leaves the gun to fetch ammo
			var lp: Vector3 = (wpose * w.grip_l).lerp(wpose.origin + Vector3(-0.06, -0.16, 0.1), reload)
			_place("L", "grip", lp, wpose.basis * w.axis_l, el)

	if L.has_torch(loadout):
		_anchor.global_transform = _apparent(tpose * Transform3D(Basis(), TORCH_LENS))

	# flash: a few frames, randomised per shot in _fire()
	_flash_root.visible = id >= 0 and loadout != L.BAT and _flash_t < _flash_dur

	_draw_trail(id)

	# rifle: past most of the way into aim you are looking through the scope
	var scoped := loadout == L.RIFLE and ads > 0.85 and _sw < 0.01
	_geo.visible = not scoped
	_scope.visible = scoped
	if scoped:
		var vs := get_viewport().get_visible_rect().size
		(_scope.material as ShaderMaterial).set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))


## Hand exactly on a grip: fist around `axis` (thumb side), back of the hand
## toward `wrist` (default: toward the elbow). The forearm then aims at `elbow`
## and the upper-arm stub at the shoulder; wrist and elbow bend to fit. Each
## bend is the shortest-arc swing, so the forearm keeps the hand's roll.
func _place(side: String, pose: String, pos: Vector3, axis: Vector3, elbow: Vector3, wrist := Vector3.ZERO) -> void:
	var x := (-axis if side == "R" else axis).normalized()
	var z := elbow - pos if wrist == Vector3.ZERO else wrist
	z = (z - x * z.dot(x)).normalized()
	var b := Basis(x, z.cross(x), z)
	var rig: Dictionary = _rigs[pose]
	var skel: Skeleton3D = rig.skel
	var a: Dictionary = rig[side]
	var to_skel := skel.transform.affine_inverse()
	var target := to_skel * Transform3D(b, pos - b * FIST)  # palm frame, skeleton space
	var move := Transform3D(target.basis.orthonormalized(), target.origin) * (a.palm as Transform3D).affine_inverse()
	var hand: Transform3D = move * a.hand_rest
	var to_elbow := (to_skel * elbow - hand.origin).normalized()
	var swing := Basis(Quaternion((move.basis * (a.hand_rest.origin - a.fore_rest.origin)).normalized(), -to_elbow))
	var fore := Transform3D(swing * move.basis * a.fore_rest.basis, hand.origin + to_elbow * a.fore_len)
	var u0: Vector3 = (swing * move.basis * (a.fore_rest.origin - a.upper_rest.origin)).normalized()
	var u1 := (fore.origin - to_skel * (SHOULDER_R if side == "R" else SHOULDER_L)).normalized()
	var bend := Basis(Quaternion(u0, u1))
	var upper := Transform3D(bend * swing * move.basis * a.upper_rest.basis, fore.origin - u1 * a.upper_len)
	_set_bone(skel, a.upper, upper)  # a root bone: its pose is in skeleton space
	_set_bone(skel, a.fore, upper.affine_inverse() * fore)
	_set_bone(skel, a.hand, fore.affine_inverse() * hand)


func _set_bone(skel: Skeleton3D, bone: int, t: Transform3D) -> void:
	skel.set_bone_pose_position(bone, t.origin)
	skel.set_bone_pose_rotation(bone, t.basis.get_rotation_quaternion())


func _ease(f: float, kind: String) -> float:
	match kind:
		"in":
			return f * f * f
		"out":
			return 1.0 - pow(1.0 - f, 3.0)
		"lin":
			return f
	return smoothstep(0.0, 1.0, f)


func _swing_pose(t: float) -> Transform3D:
	for i in SWING.size() - 1:
		var a: Array = SWING[i]
		var b: Array = SWING[i + 1]
		if t <= b[0]:
			var f := _ease(clampf((t - a[0]) / (b[0] - a[0]), 0.0, 1.0), b[3])
			return _xf([a[1], a[2]]).interpolate_with(_xf([b[1], b[2]]), f)
	return _xf([SWING[0][1], SWING[0][2]])


## Swoosh behind the bat head during the strike: a ribbon from recent
## head/mid-bat positions, fading with age.
func _draw_trail(id: int) -> void:
	_trail_mesh.clear_surfaces()
	if loadout != L.BAT or _swing < SWING_TRAIL.x or _swing > SWING_TRAIL.y:
		_trail.clear()
		return
	var w: Dictionary = _w[id]
	var xf: Transform3D = w.holder.transform
	if _hitstop <= 0.0:
		_trail.append([xf * w.muzzle, xf * (w.muzzle * 0.45)])
		if _trail.size() > 8:
			_trail.pop_front()
	if _trail.size() < 2:
		return
	_trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _trail.size():
		var a := float(i) / (_trail.size() - 1) * 0.35
		_trail_mesh.surface_set_color(Color(0.92, 0.9, 0.85, a))
		_trail_mesh.surface_add_vertex(_trail[i][0])
		_trail_mesh.surface_set_color(Color(0.92, 0.9, 0.85, 0.0))
		_trail_mesh.surface_add_vertex(_trail[i][1])
	_trail_mesh.surface_end()


func _update_lights() -> void:
	var lit: bool = L.has_torch(loadout) and _player.flashlight_enabled
	_player.update_lights()  # torch beam from _anchor, this frame
	_beam.visible = lit and _geo.visible
	if lit:
		var apex := _anchor.global_position
		var target: Vector3 = _player.reticle_point
		var dir := (target - apex).normalized() if apex.distance_to(target) > 0.5 else -_anchor.global_basis.z
		var radius := BEAM_LENGTH * tan(deg_to_rad(_player.flashlight_angle) * 0.6)
		_beam_mesh.bottom_radius = radius
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var y := -dir
		var x := up.cross(y).normalized()
		_beam.global_transform = Transform3D(Basis(x, y, x.cross(y)), apex + dir * BEAM_LENGTH * 0.5)
		_spill.global_position = _torch.global_transform * TORCH_LENS
		_spill.light_energy = 0.3
	else:
		_spill.light_energy = 0.0
	if _lens != null:
		_lens.emission_energy_multiplier = 5.0 if lit else 0.0
	# dim moonlight from above-left: enough to read the hands' shape at night
	_fill.global_position = _cam.global_transform * Vector3(-0.03, 0.05, -0.01)

	# muzzle flash light: brief and fast-fading, from where the muzzle appears
	var f := clampf(1.0 - _flash_t / (_flash_dur * 1.6), 0.0, 1.0)
	f *= f
	_flash_world.light_energy = 2.2 * f
	_flash_vm.light_energy = 1.6 * f
	_flash_world.visible = f > 0.0
	_flash_vm.visible = f > 0.0
	if f > 0.0:
		_flash_world.global_position = _apparent(Transform3D(Basis(), _flash_root.position)).origin
		_flash_vm.global_position = _flash_root.global_position


# --- weapons -------------------------------------------------------------------

func _trigger() -> void:
	var id: int = L.WEAPON[loadout]
	if id < 0 or _sw > 0.05 or _pending >= 0 or _reload_left > 0.0 or _cooldown > 0.0:
		return
	var d := L.data(loadout)
	if d.is_melee:
		_start_swing()
		return
	var a: Dictionary = _ammo[id]
	if a.mag <= 0:
		_try_reload()
		return
	a.mag -= 1
	_cooldown = maxf(d.cooldown, 0.05)
	_shoot(d)
	_fire_fx(id)
	if a.mag <= 0:
		_try_reload()  # auto-reload the moment the mag runs dry, as in 2D


## Everything that sells the shot except the bullet itself.
func _fire_fx(id: int) -> void:
	var m: Dictionary = MODELS[id]
	var r: Dictionary = m.recoil
	var side := randf_range(-1.0, 1.0)
	_gun_pos.kick(Vector3(0.0, r.up, r.back))
	_gun_rot.kick(Vector3(deg_to_rad(r.pitch), deg_to_rad(r.yaw * side), deg_to_rad(r.roll * randf_range(-1.0, 1.0))))
	var key: String = L.KEY[id]
	var peak: float = Balance.FP.camera_kick_deg[key]
	_punch.kick(Vector3(peak, peak * 0.3 * side, 0.0))
	_player.aim_pitch_offset = clampf(_player.aim_pitch_offset + Balance.FP.climb_deg[key], -_player.aim_pitch_range, _player.aim_pitch_range)

	# flash: 2-4 frames, never the same twice
	_flash_t = 0.0
	_flash_dur = (0.06 if id == W.SHOTGUN else (0.03 if id == W.MACHINEGUN else 0.045)) * randf_range(0.8, 1.2)
	var star: float = m.flash[0] * randf_range(0.75, 1.25)
	_flash_star.scale = Vector3.ONE * star
	_flash_star.rotation = Vector3(0, 0, randf() * TAU)
	_flash_star.position = Vector3(0, 0, -star * 0.15)
	var flame: float = m.flash[1] * randf_range(0.7, 1.3)
	_flash_flame.scale = Vector3(m.flash[0] * 0.6 * randf_range(0.8, 1.2), m.flash[0] * 0.6 * randf_range(0.8, 1.2), flame)
	_flash_flame.rotation = Vector3(0, 0, randf() * TAU)

	var w: Dictionary = _w[id]
	var holder: Node3D = w.holder
	var muzzle := _muzzle(id)
	_smoke(muzzle.origin, -muzzle.basis.z, m.smoke)
	if w.eject != null:
		_shell(_apparent(holder.transform * Transform3D(Basis(), w.eject)), false)


func _try_reload() -> void:
	var id: int = L.WEAPON[loadout]
	if id < 0 or _reload_left > 0.0 or _pending >= 0:
		return
	var d := L.data(loadout)
	if d.is_melee or not L.can_reload(_ammo[id], d):
		return
	_reload_total = d.reload_time
	_reload_left = d.reload_time
	if _w[id].breech != null:  # break-action: the spent shells come out
		var holder: Node3D = _w[id].holder
		for i in d.mag_size - _ammo[id].mag:
			_shell(_apparent(holder.transform * Transform3D(Basis(), _w[id].breech)), true)


## Hitscan from the eye through random points of the reticle volume.
## Where a bullet starts: the gun's muzzle, or the eye when anything (a wall, a
## zombie in your face) sits between eye and muzzle, so the barrel never
## shoots from inside or beyond it.
static func shot_origin(space: PhysicsDirectSpaceState3D, eye: Vector3, muzzle: Vector3, exclude: Array[RID]) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(eye, muzzle, ImpactFx.SHOT_MASK)
	q.exclude = exclude
	return eye if not space.intersect_ray(q).is_empty() else muzzle


## The gun's muzzle as it appears in the world (the viewmodel is drawn squashed).
func _muzzle(id: int) -> Transform3D:
	var w: Dictionary = _w[id]
	var holder: Node3D = w.holder
	return _apparent(Transform3D(holder.transform.basis, holder.transform * w.muzzle))


## Each pellet flies in a straight line from the muzzle to a random point inside
## the reticle sphere (test_player.gd: it grows with distance).
func _shoot(d: Resource) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [_player.get_rid()]
	var origin := shot_origin(space, _cam.global_position, _muzzle(L.WEAPON[loadout]).origin, exclude)
	var best := Zombie3D.Hit.NONE  # a shotgun blast shows its strongest pellet
	for i in d.pellets:
		var r: float = _player.reticle_radius * pow(randf(), 1.0 / 3.0)
		var target: Vector3 = _player.reticle_point + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized() * r
		var dir := (target - origin).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * Balance.FP.max_range_m)
		q.collision_mask = ImpactFx.SHOT_MASK
		q.exclude = [_player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		ImpactFx.spawn(_fx_root(), hit.position, hit.normal, ImpactFx.surface_of(hit.collider, hit.normal), true, dir)
		if hit.collider.has_method("take_hit"):
			var res = hit.collider.take_hit(d.damage * L.falloff(d, origin.distance_to(hit.position)), hit.position, dir)
			if res is int:
				best = maxi(best, res)
	_mark(best)


# --- bat -------------------------------------------------------------------------

func _start_swing() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_swing or _swing >= 0.0:
		return
	_next_swing = now + Balance.MELEE.cooldown
	if not _melee_hits.is_empty() and now - _melee_hits.back() > Balance.MELEE.fatigue_recover:
		_melee_hits.clear()
		_fatigued = false
	_swing = 0.0
	_swing_hit_done = false
	_swing_whoosh = false
	_trail.clear()


func _update_swing(delta: float) -> void:
	if _swing < 0.0:
		return
	if _hitstop > 0.0:  # frozen on contact: the weight of the hit
		_hitstop -= delta
		return
	_swing += delta
	if not _swing_whoosh and _swing >= SWING[1][0]:
		_swing_whoosh = true
		_punch.kick(Vector3(-0.8, 2.0, 0.0))  # the body turns into the swing
	if not _swing_hit_done and _swing >= SWING_HIT:
		_swing_hit_done = true
		_strike()
	if _swing >= SWING[-1][0]:
		_swing = -1.0


## The bat connects: 2D reach/width converted to metres, 2D fatigue rule.
func _strike() -> void:
	var reach: float = Balance.MELEE.range_px / Balance.FP.px_per_m
	var half: float = Balance.MELEE.half_width_px / Balance.FP.px_per_m
	var origin := _cam.global_position
	var fwd := -_cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var landed := false
	var q := PhysicsRayQueryParameters3D.create(origin, origin + fwd * reach, ImpactFx.SHOT_MASK)
	q.exclude = [_player.get_rid()]
	var wall := space.intersect_ray(q)
	if not wall.is_empty():
		ImpactFx.spawn(_fx_root(), wall.position, wall.normal, ImpactFx.surface_of(wall.collider, wall.normal), false, fwd)
		landed = true
	var shape := SphereShape3D.new()
	shape.radius = half
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(Basis(), origin + fwd * (reach - half))
	sq.exclude = [_player.get_rid()]
	sq.collision_mask = ImpactFx.SHOT_MASK
	var now := Time.get_ticks_msec() / 1000.0
	var best := {}  # one part per zombie per swing: the one nearest the swing
	for res in space.intersect_shape(sq, 16):
		var c: Object = res.collider
		if not c.has_method("take_hit"):
			continue
		var who: Object = c.get("unit") if c.get("unit") else c
		var d: float = (c as Node3D).global_position.distance_to(sq.transform.origin)
		if not best.has(who) or d < best[who][1]:
			best[who] = [c, d]
	for who in best:
		var c: Node3D = best[who][0]
		landed = true
		var dmg: float = Balance.MELEE.damage * (Balance.MELEE.fatigue_mult if _fatigued else 1.0)
		var r = c.take_hit(dmg, c.global_position, fwd)
		if r is int:
			_mark(r)
		_melee_hits.append(now)
		if MeleeMath.recent_hit_count(_melee_hits, now, Balance.MELEE.fatigue_window) >= Balance.MELEE.fatigue_hits:
			_fatigued = true
	if landed:
		_hitstop = HITSTOP
		_shake = 1.0
		_punch.kick(Vector3(-1.2, -1.5, 0.0))  # jolt back against the swing


# --- world fx -------------------------------------------------------------------

func _fx_root() -> Node:
	return get_tree().current_scene if get_tree().current_scene else get_tree().root


## Lit (not glowing) smoke: you only see it in the flash or the torch beam.
func _smoke(pos: Vector3, fwd: Vector3, count: int) -> void:
	var p := ImpactFx.particles(count, 1.4, _smoke_tex)
	p.direction = fwd + Vector3.UP * 0.3
	p.spread = 18.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.4
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.gravity = Vector3(0, 0.35, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.75, 0.74, 0.72, 0.35))
	ramp.set_color(1, Color(0.75, 0.74, 0.72, 0.0))
	p.color_ramp = ramp
	_fx_root().add_child(p)
	p.global_position = pos
	p.emitting = true


## Spent case flung out of the port: a real little rigid body, so it bounces.
func _shell(at: Transform3D, shotgun: bool) -> void:
	var body := RigidBody3D.new()
	body.mass = 0.02
	body.continuous_cd = true
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.35
	body.physics_material_override = pmat
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.009 if shotgun else 0.0045
	shape.height = 0.06 if shotgun else 0.019
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = shape.radius
	cyl.bottom_radius = shape.radius
	cyl.height = shape.height
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.08, 0.06) if shotgun else Color(0.85, 0.62, 0.25)
	mat.metallic = 0.2 if shotgun else 1.0
	mat.roughness = 0.5 if shotgun else 0.3
	cyl.material = mat
	mi.mesh = cyl
	body.add_child(mi)
	body.add_collision_exception_with(_player)
	_fx_root().add_child(body)
	body.global_transform = Transform3D(at.basis * Basis(Vector3.FORWARD, PI * 0.5), at.origin)
	var cb := _cam.global_transform.basis
	var throw := Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.0), randf_range(0.2, 0.6)) if shotgun \
		else Vector3(randf_range(1.6, 2.4), randf_range(1.3, 2.0), randf_range(-0.1, 0.5))
	body.linear_velocity = cb * throw + _player.velocity
	body.angular_velocity = Vector3(randfn(0, 15), randfn(0, 15), randfn(0, 15))
	_shells.append(body)
	if _shells.size() > 30:
		var old = _shells.pop_front()  # untyped: its 4 s timer may have freed it already
		if is_instance_valid(old):
			old.queue_free()
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if is_instance_valid(body):
			body.queue_free())


func _update_hud() -> void:
	var id: int = L.WEAPON[loadout]
	var line := String(L.NAMES[loadout]).to_upper()
	if id >= 0 and not L.data(loadout).is_melee:
		var a: Dictionary = _ammo[id]
		line += "   %d / %d" % [a.mag, a.reserve]
		if _reload_left > 0.0:
			line += "   RELOADING"
		elif a.mag == 0 and a.reserve == 0:
			line += "   EMPTY (T refills)" if cheat else "   EMPTY"
	elif loadout == L.BAT and _fatigued:
		line += "   TIRED"
	var keys := " · ".join(_avail().map(func(n): return "%d %s" % [n + 1, String(L.NAMES[n]).to_lower()]))
	_hud_ammo.text = ("CHEAT  " if cheat else "") + keys + " · R reload · E use\n" + line
