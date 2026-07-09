class_name LogoLockup
extends VBoxContainer
## ☣ ZOMBIE COMMAND brand lockup (mark in a ticked frame + stacked wordmark).
## Set `lockup_size` before adding to the tree: "sm" | "md" | "lg".
## "lg" adds the TACTICAL INFECTION SIMULATOR sub-line.

@export_enum("sm", "md", "lg") var lockup_size: String = "lg"

const SCALES := {
	"sm": {"icon": 44, "mark": 30, "title": 20, "sub": 0},
	"md": {"icon": 60, "mark": 42, "title": 28, "sub": 0},
	"lg": {"icon": 88, "mark": 62, "title": 42, "sub": 11},
}


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 6)
	var s: Dictionary = SCALES[lockup_size]

	var mark := BiohazardMark.new()
	mark.mark_font_size = s["mark"]
	mark.custom_minimum_size = Vector2(s["icon"], s["icon"])
	var mark_wrap := CenterContainer.new()
	mark_wrap.add_child(mark)
	add_child(mark_wrap)

	add_child(_word("ZOMBIE", s["title"], UIStyle.INFECTION))
	add_child(_word("COMMAND", s["title"], UIStyle.ASH))
	if s["sub"] > 0:
		var sub := _word("TACTICAL INFECTION SIMULATOR", s["sub"], UIStyle.MOSS)
		add_child(sub)


func _word(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UIStyle.mono_spaced())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## The bordered biohazard mark with corner ticks, fully drawn in code
## (no font glyph — the ☣ codepoint falls back to a color emoji on macOS,
## which can't be tinted acid green).
class BiohazardMark:
	extends Control

	var mark_font_size := 44  # kept for API symmetry; drives trefoil scale
	const TICK := 8.0

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var g := UIStyle.INFECTION
		# Soft glow behind the frame.
		draw_rect(r.grow(2.0), UIStyle.fade(g, 0.05))
		draw_rect(r, UIStyle.fade(g, 0.04))
		draw_rect(r, g, false, 2.0)
		# Corner ticks just outside the frame.
		for corner: Array in [
			[Vector2(-3, -3), Vector2(1, 0), Vector2(0, 1)],
			[Vector2(size.x + 3, -3), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(-3, size.y + 3), Vector2(1, 0), Vector2(0, -1)],
			[Vector2(size.x + 3, size.y + 3), Vector2(-1, 0), Vector2(0, -1)],
		]:
			var origin: Vector2 = corner[0]
			draw_line(origin, origin + corner[1] * TICK, g, 2.0)
			draw_line(origin, origin + corner[2] * TICK, g, 2.0)
		_draw_trefoil(size * 0.5, size.x * 0.30, g)

	## Stylized biohazard trefoil: three broken rings at 120° + a hub ring.
	func _draw_trefoil(center: Vector2, radius: float, color: Color) -> void:
		var petal_r := radius * 0.52
		var w := maxf(2.0, radius * 0.14)
		for i in 3:
			var ang := -PI / 2.0 + TAU * i / 3.0
			var c := center + Vector2.from_angle(ang) * radius * 0.52
			# Ring with a gap facing the hub.
			var gap := 0.9
			draw_arc(c, petal_r, ang + PI + gap * 0.5, ang + PI + TAU - gap * 0.5,
				24, color, w, true)
		draw_arc(center, radius * 0.22, 0.0, TAU, 20, color, w * 0.8, true)
		draw_circle(center, radius * 0.07, color)
