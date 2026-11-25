@tool
class_name Prop3D
extends Node3D
## A street prop from assets/props (cars, dumpsters, barriers, trees...). The
## model is set on the ground, and a box collider from its bounds (layer 1)
## makes it cover and keeps it out of the navmesh. `surface` picks the hit FX
## (ImpactFx.surface_of). `state` BURNT chars it; BURNING adds a Fire3D on top.
## Place one by hand (Add Node → Prop3D, pick `model`) or spawn it in code.

enum State { INTACT, BURNT, BURNING }

@export var model: PackedScene:
	set(v):
		model = v
		_rebuild()
@export var state := State.INTACT:
	set(v):
		state = v
		_rebuild()
@export var surface := "metal"
## Off for grass and plants: walk through them.
@export var solid := true

static var _charred: StandardMaterial3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for c in get_children():
		if c.has_meta("prop_part"):
			remove_child(c)
			c.queue_free()
	if model == null:
		return
	var inst := model.instantiate() as Node3D
	inst.set_meta("prop_part", true)
	add_child(inst)
	var meshes: Array = inst.find_children("*", "MeshInstance3D", true, false)
	var box := AABB()
	for i in meshes.size():
		var b: AABB = (global_transform.affine_inverse() * meshes[i].global_transform) * meshes[i].get_aabb()
		box = b if i == 0 else box.merge(b)
	inst.position.y -= box.position.y  # sit on the ground
	box.position.y = 0.0

	if state != State.INTACT:
		if _charred == null:
			_charred = StandardMaterial3D.new()
			_charred.albedo_color = Color(0.09, 0.075, 0.06)
			_charred.roughness = 1.0
		for m in meshes:
			m.material_override = _charred
	if state == State.BURNING:
		var fire := Fire3D.new()
		fire.size = clampf(minf(box.size.x, box.size.z), 0.5, 2.5)
		fire.position = Vector3(box.get_center().x, box.size.y * 0.55, box.get_center().z)
		fire.set_meta("prop_part", true)
		add_child(fire)

	if solid and not Engine.is_editor_hint():
		var body := StaticBody3D.new()
		body.set_meta("prop_part", true)
		body.set_meta("surface", surface)
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = box.size
		shape.position = box.get_center()
		body.add_child(shape)
		add_child(body)
