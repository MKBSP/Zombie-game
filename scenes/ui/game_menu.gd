extends CanvasLayer
## In-game ESC menu for the 3D game (scenes/game/rig.tscn). Pauses the tree.
## Resume · play as shooter / zombie commander · cheats · settings · restart ·
## quit to menu. As the commander, ESC first clears a pending order or the
## selection; only a second ESC opens this menu.
## Must sit in group "keep_visible" (set in rig.tscn) so the commander's role
## switch doesn't hide it with the shooter's HUD layers.

@export var commander_path: NodePath = ^"../Commander"
@export var viewmodel_path: NodePath = ^"../CameraRig/Camera3D/Viewmodel"

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

var _root: Control
var _modal: PanelContainer
var _role_btn: Button
var _cheat_btn: Button
var _settings_open := false
var _goto: VBoxContainer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _settings_open:
		return  # the settings overlay owns ESC while it's up
	get_viewport().set_input_as_handled()
	if _root.visible:
		_close()
		return
	var cmd := get_node_or_null(commander_path)
	if cmd and cmd.active and cmd.escape():
		return  # cleared an order or the selection instead
	_open()


func _open() -> void:
	_refresh()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true


func _close() -> void:
	_root.visible = false
	get_tree().paused = false
	var cmd := get_node_or_null(commander_path)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if cmd and cmd.active else Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	var scene := get_tree().current_scene
	if _goto.get_child_count() == 0 and scene and scene.has_method("areas"):
		var head := Label.new()
		head.text = "GO TO"
		head.theme_type_variation = "MicroLabel"
		_goto.add_child(head)
		for a: String in scene.areas():
			_button(_goto, a, func() -> void:
				_close()
				scene.go(a))
	var cmd := get_node_or_null(commander_path)
	_role_btn.visible = cmd != null
	if cmd:
		_role_btn.text = "PLAY AS SHOOTER" if cmd.active else "PLAY AS ZOMBIE COMMANDER"
	var vm := get_node_or_null(viewmodel_path)
	_cheat_btn.visible = vm != null
	if vm:
		_cheat_btn.text = "CHEATS: %s" % ("ON" if vm.cheat else "OFF")


func _on_role() -> void:
	var cmd := get_node_or_null(commander_path)
	_close()
	cmd.set_active(not cmd.active)


func _on_cheat() -> void:
	var vm := get_node_or_null(viewmodel_path)
	vm.set_cheat(not vm.cheat)
	_refresh()


func _on_settings() -> void:
	var s := SettingsMenu.new()
	s.overlay_mode = true
	_root.add_child(s)
	_settings_open = true
	_modal.visible = false
	s.closed.connect(func() -> void:
		s.queue_free()
		_settings_open = false
		_modal.visible = true)


func _on_restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_quit() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)


# ------------------------------------------------------------------- layout
# Same modal as the 2D pause menu (scenes/ui/pause_menu.gd), built in code.

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Controls under a CanvasLayer don't inherit the window's theme (UITheme).
	_root.theme = get_window().theme
	add_child(_root)

	var scrim := ColorRect.new()
	scrim.color = UIStyle.fade(UIStyle.ABYSS, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_modal = PanelContainer.new()
	_modal.theme_type_variation = "ModalPanel"
	_modal.custom_minimum_size = Vector2(320, 0)
	center.add_child(_modal)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_modal.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var title := Label.new()
	title.text = "PAUSED"
	title.theme_type_variation = "MonoLabel"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIStyle.INFECTION)
	v.add_child(title)
	v.add_child(MenuWidgets._hairline())
	v.add_child(MenuWidgets.spacer(6.0))

	var resume := _button(v, "RESUME", _close)
	MenuWidgets.primary_button(resume)
	resume.custom_minimum_size = Vector2(280, 44)
	_role_btn = _button(v, "", _on_role)
	_cheat_btn = _button(v, "", _on_cheat)
	_button(v, "SETTINGS", _on_settings)
	_goto = VBoxContainer.new()
	_goto.add_theme_constant_override("separation", 8)
	v.add_child(_goto)
	_button(v, "RESTART", _on_restart)
	_button(v, "QUIT TO MENU", _on_quit).theme_type_variation = "DangerButton"


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 44)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
