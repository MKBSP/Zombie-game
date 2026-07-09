extends Node
## Autoload "Settings" — user preferences persisted to user://settings.cfg.
## UI toggles are read by the HUD scripts; `changed` fires on every write so
## live screens can react without re-reading the file.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "ui"

## Every known setting and its default. get_value falls back to these.
const DEFAULTS := {
	"show_minimap": true,
	"show_interact_prompts": true,
	"show_pickup_toasts": true,
	"show_debug_coords": false,
}

var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(PATH)  # missing file is fine — defaults apply


func get_value(key: String) -> Variant:
	return _cfg.get_value(SECTION, key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	_cfg.set_value(SECTION, key, value)
	_cfg.save(PATH)
	changed.emit(key, value)
