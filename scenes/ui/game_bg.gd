class_name GameBg
extends Control
## Full-screen ZOMBIE COMMAND screen background: ABYSS ground, 48px acid-green
## grid at low opacity, radial vignette. Instance as the first child of a
## menu/screen root; it fills the parent and ignores the mouse.

const GRID_STEP := 48.0
const GRID_ALPHA := 0.06


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_add_vignette()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UIStyle.ABYSS)
	var line := UIStyle.fade(UIStyle.INFECTION, GRID_ALPHA)
	var x := GRID_STEP
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), line, 1.0)
		x += GRID_STEP
	var y := GRID_STEP
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y += GRID_STEP


func _add_vignette() -> void:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.4, 1.0])
	grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.55)])
	tex.gradient = grad

	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
