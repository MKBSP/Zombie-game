class_name Grunge
extends RefCounted
## Distress/decay decorators ported from the "Game HUD for Zombie Strategy v2"
## Figma Make mockup (src/app/App.tsx): <Grain>, <CrackLines>, <BloodSplat>,
## etc. Each nested class is a small custom-draw Control — add as a child of
## a panel. Everything here is generated or drawn procedurally (no image
## assets, so no .import step — see CLAUDE.md's "new image assets" gotcha).

const BLOOD := Color("8b0000")
const INK := Color("120d05")

static var _grain_tex: ImageTexture = null


## 64×64 tileable monochrome noise — approximates the mockup's feTurbulence
## film-grain filter. Built once and cached for reuse across every panel.
static func grain_texture() -> ImageTexture:
	if _grain_tex != null:
		return _grain_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in size:
		for x in size:
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v, v, v))
	_grain_tex = ImageTexture.create_from_image(img)
	return _grain_tex


## A TextureRect that tiles grain_texture() at low opacity across whatever
## rect it's given — the mockup's `<Grain opacity=.. />`.
static func grain_overlay(opacity: float = 0.13) -> TextureRect:
	var t := TextureRect.new()
	t.texture = grain_texture()
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate = Color(1, 1, 1, opacity)
	return t


## Faint diagonal crack lines across a panel — mockup's <CrackLines>.
class CrackLines:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.12) -> void:
		draw_color = Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.15, 0), Vector2(w * 0.22, h * 0.18), Vector2(w * 0.18, h * 0.26),
			Vector2(w * 0.28, h * 0.55), Vector2(w * 0.24, h)]), draw_color, 0.7)
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.85, h * 0.08), Vector2(w * 0.80, h * 0.35),
			Vector2(w * 0.84, h * 0.48), Vector2(w * 0.76, h)]), draw_color, 0.5)


## Smaller cracks for individual buttons/boxes — mockup's <BoxCracks>.
class BoxCracks:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.18) -> void:
		draw_color = Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.05, h * 0.2), Vector2(w * 0.18, h * 0.35),
			Vector2(w * 0.12, h * 0.55), Vector2(w * 0.20, h * 0.8)]), draw_color, 0.5)
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.8, h * 0.1), Vector2(w * 0.75, h * 0.4), Vector2(w * 0.8, h * 0.6)]), draw_color, 0.4)


## Fine surface scratches — mockup's <Scratches>.
class Scratches:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.05) -> void:
		draw_color = Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_line(Vector2(w * 0.07, h * 0.02), Vector2(w * 0.10, h * 0.98), draw_color, 0.6)
		draw_line(Vector2(w * 0.41, 0), Vector2(w * 0.38, h * 0.6), draw_color, 0.4)
		draw_line(Vector2(w * 0.72, h * 0.18), Vector2(w * 0.75, h * 0.88), draw_color, 0.5)


## Jagged torn-paper edge on one side — mockup's <WornEdge side="top|bottom">.
class WornEdge:
	extends Control
	var edge_side: String
	func _init(side: String = "bottom") -> void:
		edge_side = side
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		var pts := PackedVector2Array()
		var n := 24
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in range(n + 1):
			var x := w * float(i) / float(n)
			var jag := rng.randf_range(0.0, h * 0.6)
			var y := jag if edge_side == "bottom" else h - jag
			pts.append(Vector2(x, y))
		draw_polyline(pts, Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, 0.9), 2.0)


## Repeating diagonal hazard-tape stripe — mockup's <HazardTape>.
class HazardTape:
	extends Control
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := maxf(size.y, 1.0)
		var stripe := 18.0
		var x := -stripe
		while x < w + stripe:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, h), Vector2(x + h, 0), Vector2(x + h + 8.0, 0), Vector2(x + 8.0, h)]),
				Color("c8920a", 0.55))
			x += stripe


## Irregular blood-splatter blob — mockup's <BloodSplat>.
class BloodSplat:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.28) -> void:
		draw_color = Color(Grunge.BLOOD.r, Grunge.BLOOD.g, Grunge.BLOOD.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := minf(w, h) * 0.32
		if r <= 0.0:
			return
		draw_circle(Vector2(w * 0.55, h * 0.5), r, draw_color)
		draw_circle(Vector2(w * 0.78, h * 0.72), r * 0.28, draw_color)
		draw_circle(Vector2(w * 0.26, h * 0.8), r * 0.2, draw_color)


## Flat irregular stain with its own fixed size (independent of parent
## layout) — mockup's <BloodStain>.
class BloodStain:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.1) -> void:
		draw_color = Color(Grunge.BLOOD.r, Grunge.BLOOD.g, Grunge.BLOOD.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(80, 50)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.12, h * 0.16), Vector2(w * 0.32, h * 0.02), Vector2(w * 0.7, h * 0.06),
			Vector2(w * 0.94, h * 0.28), Vector2(w * 0.9, h * 0.66), Vector2(w * 0.58, h * 0.94),
			Vector2(w * 0.22, h * 0.88), Vector2(w * 0.03, h * 0.58)]), draw_color)


## A drip hanging below a bar — mockup's <BloodDrip>. `set_pct()` lets a
## caller reposition it live (e.g. tracking a health bar's current fill).
class BloodDrip:
	extends Control
	var x_pct: float
	var drip_h: float
	var draw_color: Color
	func _init(x_pct_in: float = 0.5, h: float = 18.0, opacity: float = 0.5) -> void:
		x_pct = x_pct_in
		drip_h = h
		draw_color = Color(Grunge.BLOOD.r, Grunge.BLOOD.g, Grunge.BLOOD.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, h)
	func set_pct(p: float) -> void:
		x_pct = p
		queue_redraw()
	func _draw() -> void:
		var x := size.x * x_pct
		draw_rect(Rect2(x - 1.0, 0, 2.0, drip_h * 0.6), draw_color)
		draw_circle(Vector2(x, drip_h * 0.8), 2.5, draw_color)


## Small rotated stenciled badge — mockup's <Stamp text="...">.
class Stamp:
	extends Label
	func _init(stamp_text: String, color: Color = Grunge.BLOOD) -> void:
		text = stamp_text
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		theme_type_variation = "MicroLabel"
		add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.4))
		rotation_degrees = -9.0


## Small bullet-hole decal — mockup's <BulletHole>.
class BulletHole:
	extends Control
	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_circle(Vector2(7, 7), 6.0, Color(0.07, 0.05, 0.02, 0.85))
		draw_circle(Vector2(7, 7), 2.5, Color.BLACK)
		draw_line(Vector2(7, 1), Vector2(4.5, 4), Color(0, 0, 0, 0.7), 0.6)
		draw_line(Vector2(7, 1), Vector2(9.5, 3), Color(0, 0, 0, 0.7), 0.6)
