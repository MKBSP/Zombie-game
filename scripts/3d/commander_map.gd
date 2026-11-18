extends Control
## The zombie commander's minimap, top right of its HUD (commander.gd): the whole
## city from above under the horde's fog of war (never seen = black, explored =
## dim, seen now = clear) with the share explored; our zombies (green, selected
## white); enemies only while a zombie sees them (red shooter, yellow survivors);
## the camera's view on the ground; and each gunshot as a ring the size of
## zombie hearing (Balance.ZOMBIE_3D.hearing_m): an Aggressive zombie inside it
## may have heard the shot. LMB (click or drag) moves the camera there, RMB
## sends the selection there. Checked by test/test_commander_map.gd.

const WIDTH := 320.0
const RING_S := 4.0          # seconds a gunshot ring stays on the map
const EXPLORED_DIM := 0.45   # brightness of explored ground no zombie sees now
const FOG_SHADER := """
shader_type canvas_item;
uniform sampler2D seen_tex : filter_linear;
uniform float dim = 0.45;
void fragment() {
	float lit = max(texture(TEXTURE, UV).r, texture(seen_tex, UV).r * dim);
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - lit);
}
"""

var rect := Rect2()          # world XZ shown: the fog's map
var rings: Array = []        # [world position, age s]
var explored := 0.0          # share of the map the horde has seen, 0..1
var _cmd: Node3D
var _fog: Node
var _marks: Control          # dots, rings and the view outline, over the fog
var _explore_t := 0.0


static func to_map(p: Vector3, r: Rect2, s: Vector2) -> Vector2:
	return (Vector2(p.x, p.z) - r.position) / r.size * s


static func to_world(m: Vector2, r: Rect2, s: Vector2) -> Vector3:
	var xz := r.position + m / s * r.size
	return Vector3(xz.x, 0.0, xz.y)


## Share of white (seen) pixels, on a 64 px wide copy so it stays cheap.
static func explored_frac(img: Image) -> float:
	var small := img.duplicate() as Image
	if small.get_width() > 64:
		small.resize(64, maxi(1, roundi(64.0 * img.get_height() / img.get_width())), Image.INTERPOLATE_BILINEAR)
	var n := 0
	for y in small.get_height():
		for x in small.get_width():
			if small.get_pixel(x, y).r > 0.5:
				n += 1
	return float(n) / (small.get_width() * small.get_height())


func setup(cmd: Node3D, fog: Node) -> void:
	_cmd = cmd
	_fog = fog
	rect = fog.rect
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -14.0 - WIDTH
	offset_right = -14.0
	offset_top = 14.0
	offset_bottom = 14.0 + WIDTH * rect.size.y / rect.size.x
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_snapshot()
	var shade := TextureRect.new()
	shade.texture = fog.vis_tex
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = FOG_SHADER
	mat.set_shader_parameter("seen_tex", fog.seen_tex)
	mat.set_shader_parameter("dim", EXPLORED_DIM)
	shade.material = mat
	_fill(shade)
	_marks = Control.new()
	_fill(_marks)
	_marks.draw.connect(_draw_marks)


func hear(pos: Vector3) -> void:
	rings.append([pos, 0.0])


func ring_px() -> float:
	return Balance.ZOMBIE_3D.hearing_m / rect.size.x * size.x


## The city from straight above, rendered once: north up, lit flat and bright
## (the night look is for the 3D view, not the map).
func _snapshot() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(Vector2(WIDTH, WIDTH * rect.size.y / rect.size.x) * 2.0)
	sub.world_3d = _cmd.get_world_3d()
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(sub)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = rect.size.x
	cam.near = 1.0
	cam.far = 600.0
	cam.cull_mask = 1  # the city only: no commander markers, no fog quad, no hidden enemies
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.75)
	cam.environment = env
	cam.position = Vector3(rect.get_center().x, 300.0, rect.get_center().y)
	cam.rotation = Vector3(-PI / 2.0, 0.0, 0.0)  # looking down, screen up = -Z = north
	sub.add_child(cam)
	var tex := TextureRect.new()
	tex.texture = sub.get_texture()
	_fill(tex)


func _fill(c: Control) -> void:
	if c is TextureRect:
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_SCALE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)


func _process(delta: float) -> void:
	for r in rings:
		r[1] += delta
	rings = rings.filter(func(r): return r[1] < RING_S)
	if not is_visible_in_tree():
		return
	_explore_t -= delta
	if _explore_t <= 0.0 and DisplayServer.get_name() != "headless":  # ponytail: a GPU readback once a second; count on the GPU if it ever shows up as a hitch
		_explore_t = 1.0
		var img: Image = _fog.seen_tex.get_image() if _fog.seen_tex else null
		if img and not img.is_empty():
			explored = explored_frac(img)
	_marks.queue_redraw()


func _draw_marks() -> void:
	var s := size
	var cam: Camera3D = _cmd._cam
	var vs := get_viewport_rect().size
	var view := PackedVector2Array()  # where the screen corners meet the ground
	for c in [Vector2.ZERO, Vector2(vs.x, 0.0), vs, Vector2(0.0, vs.y)]:
		var o := cam.project_ray_origin(c)
		var d := cam.project_ray_normal(c)
		view.append(to_map(o + d * (minf(-o.y / d.y, 400.0) if d.y < -0.05 else 400.0), rect, s))
	view.append(view[0])
	_marks.draw_polyline(view, Color(1, 1, 1, 0.7), 1.0)
	for r in rings:
		var a: float = 1.0 - r[1] / RING_S
		var at := to_map(r[0], rect, s)
		_marks.draw_arc(at, ring_px() * minf(r[1] / 0.5, 1.0), 0.0, TAU, 48, Color(1, 0.55, 0.1, a), 1.5)
		_marks.draw_circle(at, 3.0, Color(1, 0.55, 0.1, a))
	for e in _fog.visible_enemies:
		if is_instance_valid(e):
			_marks.draw_circle(to_map(e.global_position, rect, s), 3.0, Color(1, 0.2, 0.15) if e.is_in_group("shooter") else Color(1, 0.85, 0.2))
	for z in _cmd._units():
		_marks.draw_circle(to_map(z.global_position, rect, s), 2.5, Color.WHITE if z in _cmd.selected else Color(0.35, 1, 0.4))
	_marks.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.4), false, 1.0)
	_marks.draw_string(ThemeDB.fallback_font, Vector2(6, 16), "Explored %d%%" % roundi(explored * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		if not _cmd.selected.is_empty():
			_cmd._order_move(to_world(e.position, rect, size), Color(0.3, 1.0, 0.35))
	elif (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
			or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_cmd._focus = to_world(e.position, rect, size)
	else:
		return
	accept_event()
