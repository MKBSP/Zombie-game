extends Node
## Autoload "Settings" — user preferences persisted to user://settings.cfg.
## UI toggles are read by the HUD scripts; `changed` fires on every write so
## live screens can react without re-reading the file.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "ui"

## Every known setting and its default. get_value falls back to these.
const DEFAULTS := {
	"fullscreen": false,
	"show_minimap": true,
	"show_interact_prompts": true,
	"show_pickup_toasts": true,
	"show_debug_coords": false,
}

var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(PATH)  # missing file is fine — defaults apply
	# Browsers only allow entering fullscreen from a user gesture (F11 or the
	# Settings toggle), so the saved mode is restored at boot on desktop only.
	if not OS.has_feature("web") and get_value("fullscreen"):
		_apply_fullscreen(true)


## Global hotkey: F11 toggles fullscreen anywhere (menus and in game).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_F11:
		set_value("fullscreen", not get_value("fullscreen"))


func get_value(key: String) -> Variant:
	return _cfg.get_value(SECTION, key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	_cfg.set_value(SECTION, key, value)
	_cfg.save(PATH)
	if key == "fullscreen":
		_apply_fullscreen(value)
	changed.emit(key, value)


func _apply_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on
		else DisplayServer.WINDOW_MODE_WINDOWED)
