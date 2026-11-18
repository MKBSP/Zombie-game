extends Node
## Commander fog of war (Phase 10 S8, first cut), owned by scripts/3d/commander.gd.
##
## The city is building footprints pushed straight up, so street-level sight is
## a 2D problem, and this is the 2D game's ZombieLighting idea reused: a
## top-down SubViewport where every zombie is a shadow-casting PointLight2D
## (radius = its vision) and every building footprint a LightOccluder2D that
## only casts from its far side, so seeing a building's front lights its whole
## footprint (= "that building is known") and the shadow starts behind it.
## White = seen right now. A second SubViewport adds that up into "explored".
## A full-screen quad on the commander's render layer then shades each pixel by
## the state at its world XZ: unexplored black (no streets, no buildings, no
## light), explored dim with bright light (torches, lamps) glowing through,
## seen full.
##
## Enemies (groups "shooter" / "npcs") are drawn for the commander only while a
## zombie can see them (Zombie3D.seen_by_horde): otherwise their meshes move to
## HIDDEN_LAYER, which shooter cameras draw and the commander camera doesn't.

const Z := preload("res://scripts/3d/zombie_3d.gd")
const MPP := 0.5            # metres per fog pixel
const HIDDEN_LAYER := 8     # render layer 4
const LIGHT_TEX := 256
## Footprints only cast shadow from their far edges, so a building whose front
## a zombie sees is lit (known) inside. Matches outlines()' winding.
const OCCLUDER_CULL := OccluderPolygon2D.CULL_COUNTER_CLOCKWISE

var visible_enemies: Array = []
var vis_tex: Texture2D      # white = a zombie sees it now (the minimap reads these two)
var seen_tex: Texture2D     # white = seen at some point
var rect: Rect2:            # map, world XZ
	get:
		return _rect
var _rect := Rect2()
var _vis: SubViewport
var _lights := {}           # zombie -> PointLight2D
var _light_tex: GradientTexture2D
var _t := 0.0


func setup(city: Node3D, cam: Camera3D) -> void:
	var meshes := city.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in meshes:
		var box: AABB = mi.global_transform * mi.get_aabb()
		var r := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		_rect = r if _rect.size == Vector2.ZERO else _rect.merge(r)
	var size := Vector2i((_rect.size / MPP).ceil())
	var occluders: Array = []
	for mi: MeshInstance3D in meshes:
		if not String(mi.name).begins_with("Building"):
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i) as ShaderMaterial
			if mat and mat.get_shader_parameter("is_roof"):
				var a := mi.mesh.surface_get_arrays(i)
				var v := PackedVector2Array()
				for p in a[Mesh.ARRAY_VERTEX]:
					v.append(_px(mi.global_transform * p))
				occluders.append_array(outlines(v, a[Mesh.ARRAY_INDEX]))

	_vis = _viewport(size)
	_vis.transparent_bg = false
	var mod := CanvasModulate.new()  # unlit = black, lit by a zombie = white
	mod.color = Color.BLACK
	_vis.add_child(mod)
	var white := ColorRect.new()
	white.size = Vector2(size)
	_vis.add_child(white)
	for loop in occluders:
		var poly := OccluderPolygon2D.new()
		poly.polygon = loop
		poly.cull_mode = OCCLUDER_CULL
		var occ := LightOccluder2D.new()
		occ.occluder = poly
		_vis.add_child(occ)

	var seen := _viewport(size)  # explored memory: add this frame's sight, never clear
	seen.transparent_bg = true
	seen.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	var acc := TextureRect.new()
	acc.texture = _vis.get_texture()
	acc.size = Vector2(size)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	acc.material = add
	seen.add_child(acc)

	var g := Gradient.new()  # crisp sight radius with a soft rim
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color.BLACK)
	g.add_point(0.82, Color.WHITE)
	_light_tex = GradientTexture2D.new()
	_light_tex.gradient = g
	_light_tex.fill = GradientTexture2D.FILL_RADIAL
	_light_tex.fill_from = Vector2(0.5, 0.5)
	_light_tex.fill_to = Vector2(1.0, 0.5)
	_light_tex.width = LIGHT_TEX
	_light_tex.height = LIGHT_TEX

	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var fog := ShaderMaterial.new()
	fog.shader = load("res://shader/commander_fog.gdshader")
	fog.render_priority = Material.RENDER_PRIORITY_MIN  # before the commander's markers
	vis_tex = _vis.get_texture()
	seen_tex = seen.get_texture()
	fog.set_shader_parameter("vis_tex", vis_tex)
	fog.set_shader_parameter("seen_tex", seen_tex)
	fog.set_shader_parameter("map_rect", Vector4(_rect.position.x, _rect.position.y, _rect.size.x, _rect.size.y))
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = fog
	mi.layers = Z.COMMANDER_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	cam.add_child(mi)
	cam.cull_mask &= ~HIDDEN_LAYER


func _process(delta: float) -> void:
	if _vis == null:
		return
	for z in get_tree().get_nodes_in_group("zombies"):
		if not _lights.has(z):
			var l := PointLight2D.new()
			l.texture = _light_tex
			l.shadow_enabled = true
			l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
			_vis.add_child(l)
			_lights[z] = l
	for z in _lights.keys():
		var l: PointLight2D = _lights[z]
		if not is_instance_valid(z) or z.is_dead:
			l.queue_free()
			_lights.erase(z)
			continue
		l.visible = z.visible
		l.position = _px(z.global_position)
		l.texture_scale = 2.0 * z.vision_m / MPP / LIGHT_TEX
	_t -= delta
	if _t <= 0.0:  # 10 Hz is plenty for who-sees-whom
		_t = 0.1
		_update_enemies()


func _update_enemies() -> void:
	visible_enemies.clear()
	for e in get_tree().get_nodes_in_group("shooter") + get_tree().get_nodes_in_group("npcs"):
		var seen: bool = Z.seen_by_horde(get_tree(), e.global_position)
		if seen:
			visible_enemies.append(e)
		for g: GeometryInstance3D in e.find_children("*", "GeometryInstance3D", true, false):
			if not g.has_meta("fog_layers"):
				g.set_meta("fog_layers", g.layers)
			g.layers = g.get_meta("fog_layers") if seen else HIDDEN_LAYER


## Outer outlines of a triangulated roof (2D points + triangle indices): the
## directed edges with no twin, chained into loops, all wound the same way.
## Holes (courtyards) wind the other way and are dropped: from the street a
## courtyard is as hidden as the building around it.
static func outlines(v: PackedVector2Array, idx: PackedInt32Array) -> Array:
	var key := func(p: Vector2) -> Vector2i: return Vector2i((p * 50.0).round())
	var edges := {}
	var tri_area := 0.0
	for t in range(0, idx.size() - 2, 3):
		var a := v[idx[t]]
		var b := v[idx[t + 1]]
		var c := v[idx[t + 2]]
		tri_area += (b - a).cross(c - a)
		for e in [[a, b], [b, c], [c, a]]:
			edges[[key.call(e[0]), key.call(e[1])]] = e
	var next := {}
	for k in edges:
		if not edges.has([k[1], k[0]]):
			next[k[0]] = [k[1], edges[k][0]]
	var loops: Array = []
	while not next.is_empty():
		var start: Vector2i = next.keys()[0]
		var loop := PackedVector2Array()
		var at := start
		while next.has(at) and loop.size() < 4096:
			var n: Array = next[at]
			next.erase(at)
			loop.append(n[1])
			at = n[0]
			if at == start:
				break
		var area := 0.0
		for i in loop.size():
			area += loop[i].cross(loop[(i + 1) % loop.size()])
		if loop.size() >= 3 and signf(area) == signf(tri_area):
			if area < 0.0:
				loop.reverse()  # every outer loop counter-clockwise (y down)
			loops.append(loop)
	return loops


func _px(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _rect.position) / MPP


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp
