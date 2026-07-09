extends Control
## Boot screen (mockup screen 01): logo lockup, progress bar, init checklist,
## then hands off to the main menu. Purely time-driven — a threaded
## world.tscn preload was tried here and stalled mid-load, so don't re-add it
## without verifying load_threaded_get_status actually completes.
## Dedicated-server and local-testing launches (--server/--host/--join/…)
## skip straight to the menu.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const MIN_TIME := 1.6  # seconds of brand moment

const STEPS := [
	"RENDERING ENGINE",
	"MAP DATA",
	"UNIT AI MODULES",
	"MULTIPLAYER SERVICES",
	"AUDIO SYSTEMS",
]

var _elapsed := 0.0
var _done := false
var _bar: ProgressBar
var _pct_label: Label
var _step_rows: Array = []  # [{square: ColorRect, label: Label, ok: Label}]


func _ready() -> void:
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for a: String in args:
		if a == "--server" or a == "--host" or a == "--autojoin" \
				or a.begins_with("--join=") or a.begins_with("--role="):
			set_process(false)
			get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
			return

	_build_ui()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var p := clampf(_elapsed / MIN_TIME, 0.0, 1.0)

	_bar.value = p * 100.0
	_pct_label.text = "%d%%" % int(p * 100.0)
	for i in _step_rows.size():
		var step_done: bool = p >= float(i + 1) / float(_step_rows.size()) - 0.001
		var row: Dictionary = _step_rows[i]
		row.square.color = UIStyle.INFECTION if step_done else UIStyle.BUNKER
		row.label.add_theme_color_override("font_color",
			UIStyle.MOSS if step_done else UIStyle.DIM)
		row.ok.visible = step_done

	if p >= 1.0:
		_done = true
		get_tree().change_scene_to_file(MENU_SCENE)


func _build_ui() -> void:
	add_child(GameBg.new())

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	center.add_child(v)

	var logo := LogoLockup.new()
	logo.lockup_size = "lg"
	v.add_child(logo)
	v.add_child(MenuWidgets.spacer(30.0))

	var bar_box := VBoxContainer.new()
	bar_box.custom_minimum_size = Vector2(340, 0)
	bar_box.add_theme_constant_override("separation", 6)
	v.add_child(bar_box)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 7)
	bar_box.add_child(_bar)

	var info := HBoxContainer.new()
	bar_box.add_child(info)
	var loading_l := Label.new()
	loading_l.text = "LOADING ASSETS..."
	loading_l.theme_type_variation = "MicroLabel"
	loading_l.add_theme_color_override("font_color", UIStyle.MOSS)
	loading_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(loading_l)
	_pct_label = Label.new()
	_pct_label.text = "0%"
	_pct_label.theme_type_variation = "MicroLabel"
	_pct_label.add_theme_color_override("font_color", UIStyle.INFECTION)
	info.add_child(_pct_label)

	v.add_child(MenuWidgets.spacer(18.0))

	var steps_box := VBoxContainer.new()
	steps_box.custom_minimum_size = Vector2(340, 0)
	steps_box.add_theme_constant_override("separation", 4)
	v.add_child(steps_box)
	for step: String in STEPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var square := ColorRect.new()
		square.custom_minimum_size = Vector2(7, 7)
		square.color = UIStyle.BUNKER
		square.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(square)
		var l := Label.new()
		l.text = step
		l.theme_type_variation = "MicroLabel"
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var ok := Label.new()
		ok.text = "OK"
		ok.theme_type_variation = "MicroLabel"
		ok.add_theme_color_override("font_color", UIStyle.INFECTION)
		ok.visible = false
		row.add_child(ok)
		steps_box.add_child(row)
		_step_rows.append({"square": square, "label": l, "ok": ok})

	v.add_child(MenuWidgets.spacer(26.0))
	var version := Label.new()
	version.text = "V1.0.0  ·  BUILD 2026.07"
	version.theme_type_variation = "MicroLabel"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(version)
