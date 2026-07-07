extends Node2D

## Brief additive flash sprite + a short PointLight2D pulse at the gun tip.
## Instanced as a child of the gun tip; frees itself after muzzle_flash_time.
## The radial texture is generated at runtime (reuses ShooterLighting), so the
## scene needs no image asset.

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _light: PointLight2D = $PointLight2D

func _ready() -> void:
	var tex := ShooterLighting.make_radial_texture(256)
	_sprite.texture = tex
	_light.texture = tex

func play(light_energy: float) -> void:
	_light.energy = light_energy
	_light.texture_scale = Balance.FX.muzzle_light_range_px / 128.0
	_sprite.scale = Vector2.ONE * Balance.FX.muzzle_flash_scale
	var t: float = Balance.FX.muzzle_flash_time
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "modulate:a", 0.0, t)
	tw.tween_property(_light, "energy", 0.0, t)
	tw.chain().tween_callback(queue_free)
