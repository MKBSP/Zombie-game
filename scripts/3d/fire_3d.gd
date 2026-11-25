class_name Fire3D
extends Node3D
## A fire: rising flames, a smoke column and a flickering orange light that
## casts shadows. Shared by burning cars, dumpsters, barrels and the museum's
## carryable fire. `size` scales all three (1 = a barrel fire, ~1 m across).

const Flicker := preload("res://scripts/test/flicker_light.gd")

@export var size := 1.0


func _ready() -> void:
	var dot := GradientTexture2D.new()  # soft round sprite, like impact_fx's dust
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = g
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(0.5, 0.0)

	var flames := _emitter(dot, 48, 0.7, true)
	flames.emission_box_extents = Vector3(0.35, 0.05, 0.35) * size
	flames.gravity = Vector3(0, 2.5, 0) * size
	flames.initial_velocity_min = 0.6 * size
	flames.initial_velocity_max = 1.4 * size
	flames.scale_amount_min = 0.35 * size
	flames.scale_amount_max = 0.7 * size
	flames.color_ramp = _ramp([Color(1, 0.9, 0.5, 0.9), Color(1, 0.45, 0.1, 0.8), Color(0.6, 0.1, 0.02, 0)])
	add_child(flames)

	var smoke := _emitter(dot, 24, 3.5, false)
	smoke.position.y = 0.6 * size
	smoke.emission_box_extents = Vector3(0.25, 0.05, 0.25) * size
	smoke.gravity = Vector3(0.3, 0.9, 0) * size  # a slight drift
	smoke.initial_velocity_min = 0.4 * size
	smoke.initial_velocity_max = 0.8 * size
	smoke.scale_amount_min = 0.8 * size
	smoke.scale_amount_max = 1.6 * size
	smoke.color_ramp = _ramp([Color(0.1, 0.09, 0.08, 0), Color(0.12, 0.11, 0.1, 0.45), Color(0.15, 0.14, 0.13, 0)])
	add_child(smoke)

	var light := OmniLight3D.new()
	light.set_script(Flicker)
	light.light_color = Color(1, 0.55, 0.22)
	light.light_energy = 2.5 * size
	light.omni_range = 9.0 * size
	light.shadow_enabled = true
	light.position.y = 0.7 * size
	light.shimmer = 0.3
	light.shimmer_speed = 6.0
	light.dip_chance = 0.6
	light.dip_depth = 0.3
	add_child(light)


func _emitter(tex: Texture2D, amount: int, life: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.direction = Vector3.UP
	p.spread = 12.0
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	if additive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	return p


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	g.colors = PackedColorArray(colors)
	return g
