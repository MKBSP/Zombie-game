extends Node3D
## The zombie model (assets/characters/zombie.glb — bachosoftdesign, CC-BY 3.0)
## for scripts/3d/zombie_3d.gd. Picks a clip per variant and state and speeds it
## up to match how fast the body moves, strips the clips' root motion once (the
## CharacterBody moves the zombie), carries the six part hitboxes of spec §6 on
## the bones, and hides a destroyed limb by scaling its bone to ~0 (spec §8.1's
## fallback: no stump, but no Blender work and it works on any rig).

const MODEL := preload("res://assets/characters/zombie.glb")
const HEIGHT := 1.8
const HITBOX_LAYER := 32       # physics layer 6: weapon rays hit it, bodies never do
const P := "Armature|"
const LOOPS := ["Idle", "Walk", "Walk2", "Running_Crawl", "Crawl", "Bite_ground"]
## part -> [[bone, child bone, radius at standard size (m)], ...]
const PARTS := {
	head = [["mixamorig_Head", "mixamorig_HeadTop_End", 0.13]],
	body = [["mixamorig_Hips", "mixamorig_Neck", 0.2]],
	arm_l = [["mixamorig_LeftArm", "mixamorig_LeftForeArm", 0.065], ["mixamorig_LeftForeArm", "mixamorig_LeftHand", 0.06]],
	arm_r = [["mixamorig_RightArm", "mixamorig_RightForeArm", 0.065], ["mixamorig_RightForeArm", "mixamorig_RightHand", 0.06]],
	leg_l = [["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.09], ["mixamorig_LeftLeg", "mixamorig_LeftFoot", 0.07]],
	leg_r = [["mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.09], ["mixamorig_RightLeg", "mixamorig_RightFoot", 0.07]],
}
## Bone scaled to ~0 when that part is destroyed (children go with it).
const LIMB_ROOT := {head = "mixamorig_Head", arm_l = "mixamorig_LeftArm", arm_r = "mixamorig_RightArm",
		leg_l = "mixamorig_LeftUpLeg", leg_r = "mixamorig_RightUpLeg"}
## Per variant: move clip, idle clip, attack clip, size, tint.
const LOOK := [
	["Walk2", "Idle", "Attack", 1.0, Color.WHITE],
	["Running_Crawl", "Crawl", "Running_Crawl", 0.95, Color(1.0, 0.92, 0.75)],
	["Walk", "Idle", "Attack", 1.3, Color(0.8, 0.95, 0.72)],
	["Walk", "Idle", "Attack", 1.2, Color(0.85, 0.65, 1.0)],
]
const ATTACK_S := 0.9           # an attack clip is squeezed into this

var crawling := false           # both legs gone: Crawl / Bite_ground
var _unit: Node3D
var _variant := 0
var _model: Node3D
var _mesh: MeshInstance3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var _hider: LimbHider
var _hitboxes := {}             # part -> [Hitbox]
var _destroyed: Array[String] = []
var _scale := 1.0
var _attack_t := 0.0
var _dead := false

static var _height := 0.0       # model rest height, skeleton units
static var _natural := {}       # clip -> forward speed in skeleton units / s


## A bone-attached hit zone: weapon rays land here and are routed to the unit.
class Hitbox extends StaticBody3D:
	var unit: Node3D
	var part := ""

	func take_hit(damage: float, _pos: Vector3, _dir: Vector3) -> void:
		unit.take_part_hit(part, damage)


## Runs after the animation each frame: squashes destroyed limbs to nothing.
class LimbHider extends SkeletonModifier3D:
	var bones: Array[int] = []

	func _process_modification_with_delta(_delta: float) -> void:
		_hide()

	func _process_modification() -> void:
		_hide()

	func _hide() -> void:
		var sk := get_skeleton()
		for b in bones:
			sk.set_bone_pose_scale(b, Vector3.ONE * 0.001)


func setup(unit: Node3D, variant: int) -> void:
	_unit = unit
	_variant = variant
	_model = MODEL.instantiate()
	add_child(_model)
	_sk = _model.find_children("*", "Skeleton3D", true, false)[0]
	_ap = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_mesh = _model.find_children("*", "MeshInstance3D", true, false)[0]
	if _height == 0.0:
		_prepare_clips()
	_scale = HEIGHT * LOOK[variant][3] / _height
	_model.scale = Vector3.ONE * _scale
	_model.rotation.y = PI  # the model faces +Z
	if LOOK[variant][4] != Color.WHITE:
		var m := _mesh.get_active_material(0).duplicate() as StandardMaterial3D
		m.albedo_color = LOOK[variant][4]
		_mesh.material_override = m
	_hider = LimbHider.new()
	_sk.add_child(_hider)
	_build_hitboxes()
	_play(LOOK[variant][1], 1.0)


## A copy of the skinned mesh with another material (the commander's rim silhouette).
func overlay(mat: Material, layers: int) -> void:
	var xr := _mesh.duplicate() as MeshInstance3D
	xr.material_override = mat
	xr.layers = layers
	xr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.get_parent().add_child(xr)


func animate(delta: float, speed_mps: float) -> void:
	if _dead:
		return
	if _attack_t > 0.0:
		_attack_t -= delta
		return
	var move: String = "Crawl" if crawling else LOOK[_variant][0]
	var idle: String = "Bite_ground" if crawling else LOOK[_variant][1]
	if speed_mps > 0.15:
		var natural: float = _natural.get(move, 1.0) * _scale
		_play(move, clampf(speed_mps / maxf(natural, 0.05), 0.5, 3.5))
	else:
		_play(idle, 1.0)


func attack() -> void:
	if _dead:
		return
	var clip: String = "Bite_ground" if crawling else LOOK[_variant][2]
	_ap.play(P + clip, 0.1)
	_ap.seek(0.0, true)
	_ap.speed_scale = _ap.get_animation(P + clip).length / ATTACK_S
	_attack_t = ATTACK_S


func die() -> void:
	_dead = true
	set_hittable(false)
	_ap.speed_scale = 1.0
	_ap.play(P + ("Die" if randf() < 0.5 else "Die2"), 0.15)


func destroy(part: String) -> void:
	_destroyed.append(part)
	for hb in _hitboxes.get(part, []):
		hb.collision_layer = 0
	if LIMB_ROOT.has(part):
		_hider.bones.append(_sk.find_bone(LIMB_ROOT[part]))


func set_hittable(on: bool) -> void:
	for part in _hitboxes:
		for hb in _hitboxes[part]:
			hb.collision_layer = HITBOX_LAYER if on and not part in _destroyed else 0


## Merge lock-in pulse, 0..1; -1 resets.
func pulse(p: float) -> void:
	var s := 1.0 if p < 0.0 else 1.0 + 0.12 * absf(sin(p * 30.0))
	_model.scale = Vector3(s, 1.0, s) * _scale


func _play(clip: String, rate: float) -> void:
	if _ap.current_animation != P + clip:
		_ap.play(P + clip, 0.25)
	_ap.speed_scale = rate


func _build_hitboxes() -> void:
	var size: float = LOOK[_variant][3]
	for part in PARTS:
		_hitboxes[part] = []
		for seg in PARTS[part]:
			var b := _sk.find_bone(seg[0])
			var c := _sk.find_bone(seg[1])
			if b < 0 or c < 0:
				continue
			var tip: Vector3 = _sk.get_bone_global_rest(b).affine_inverse() * _sk.get_bone_global_rest(c).origin
			var att := BoneAttachment3D.new()
			att.bone_name = seg[0]
			_sk.add_child(att)
			var hb := Hitbox.new()
			hb.unit = _unit
			hb.part = part
			hb.collision_layer = HITBOX_LAYER
			hb.collision_mask = 0
			var cap := CapsuleShape3D.new()
			cap.radius = seg[2] * size / _scale
			cap.height = maxf(tip.length() + cap.radius, cap.radius * 2.0 + 0.01)
			var cs := CollisionShape3D.new()
			cs.shape = cap
			cs.transform = Transform3D(Basis(Quaternion(Vector3.UP, tip.normalized())), tip / 2.0)
			hb.add_child(cs)
			att.add_child(hb)
			_hitboxes[part].append(hb)


## Once per run (the clips are shared by every instance): measure the model,
## loop the looping clips, and take the forward drift out of the hips track,
## remembering it as the clip's natural speed.
func _prepare_clips() -> void:
	var top := _sk.find_bone("mixamorig_HeadTop_End")
	var foot := _sk.find_bone("mixamorig_LeftToe_End")
	_height = _sk.get_bone_global_rest(top).origin.y - _sk.get_bone_global_rest(foot).origin.y
	for name in _ap.get_animation_list():
		var a := _ap.get_animation(name)
		var clip := String(name).trim_prefix(P)
		if clip in LOOPS:
			a.loop_mode = Animation.LOOP_LINEAR
		if clip.begins_with("Die"):
			continue  # keep the fall
		for t in a.get_track_count():
			if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not String(a.track_get_path(t)).ends_with("mixamorig_Hips"):
				continue
			var n := a.track_get_key_count(t)
			if n < 2 or a.length <= 0.0:
				continue
			var drift: Vector3 = a.track_get_key_value(t, n - 1) - a.track_get_key_value(t, 0)
			drift.y = 0.0
			_natural[clip] = drift.length() / a.length
			for k in n:
				var f := a.track_get_key_time(t, k) / a.length
				a.track_set_key_value(t, k, a.track_get_key_value(t, k) - drift * f)
