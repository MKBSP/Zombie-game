extends Node2D
class_name StaticLightSource

## Attach as a child of a lightpost/dumpster prop, at local position (0,0) so its
## global_position matches the prop's. Builds a Light2D (steady, or flickering if
## `flicker` is set) and registers with the "static_lights" group so
## zombie_controller.gd's _update_fog() can feed it into FogZombieController as a
## permanent full-visibility pseudo-vision source (see design spec §2/§3) —
## the same treatment a zombie's own vision light already gets, no new fog-side
## code needed. Tunables in Balance.AMBIENT_LIFE.static_light.

@export var flicker: bool = false

var radius_px: float
var _light: PointLight2D
var _flicker_rng := RandomNumberGenerator.new()
var _base_energy: float


func _ready() -> void:
	var b: Dictionary = Balance.AMBIENT_LIFE.static_light
	radius_px = b.radius_tiles * 64.0
	_base_energy = b.flicker_energy if flicker else b.steady_energy

	_light = PointLight2D.new()
	_light.texture = ShooterLighting.make_radial_texture(b.light_tex_size)
	_light.texture_scale = radius_px / (float(b.light_tex_size) / 2.0)
	_light.energy = _base_energy
	_light.color = b.flicker_color if flicker else b.steady_color
	_light.shadow_enabled = true
	add_child(_light)

	add_to_group("static_lights")


func _process(_delta: float) -> void:
	if not flicker:
		return
	var b: Dictionary = Balance.AMBIENT_LIFE.static_light
	_light.energy = _base_energy + _flicker_rng.randf_range(-b.flicker_jitter, b.flicker_jitter)
