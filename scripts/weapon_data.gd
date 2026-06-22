extends Resource
class_name WeaponData

## Immutable definition of a weapon. Built by Weapons.get_data() and read by the
## shooter, the NPC, and the HUD. Ammo *state* lives on the wielder, not here.

@export var id: int = 0
@export var display_name: String = ""
@export var damage: float = 35.0
## Minimum seconds between shots within a mag (0 means "as fast as the engine
## allows"; callers clamp to a small floor).
@export var cooldown: float = 0.28
@export var mag_size: int = 15
@export var reload_time: float = 3.0
@export var pellets: int = 1
@export var bullet_speed: float = 600.0
@export var is_special: bool = false
## Finite rounds the weapon carries when picked up. 0 = pistol (draws from the
## shooter's separate reserve pool instead).
@export var total_ammo: int = 0

## --- Aiming (Phase 1) ---
## Circle radius as a fraction of the gun->cursor distance at 0% debuff / no focus.
@export var aim_base: float = 0.10
## Circle radius fraction at 100% debuff.
@export var aim_max: float = 0.30
## Full focus shrinks the circle to aim_base * focus_min_scale. 1.0 = no focus (shotgun).
@export var focus_min_scale: float = 1.0
## Damage is full within optimal_range_px and falls linearly to 0 at zero_range_px.
@export var optimal_range_px: float = 640.0
@export var zero_range_px: float = 800.0
