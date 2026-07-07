extends RefCounted
class_name FxPresets

## Maps a preset id to its Balance.FX.presets sub-dict. Single lookup point so
## bullets, zombies, and the shooter all describe bursts the same way.

enum { RED_BLOOD, GREEN_BLOOD, SPARKS }

const _KEYS := {
	RED_BLOOD: "red_blood",
	GREEN_BLOOD: "green_blood",
	SPARKS: "sparks",
}

static func config(preset: int) -> Dictionary:
	return Balance.FX.presets[_KEYS[preset]]
