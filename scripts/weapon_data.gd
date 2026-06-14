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
## Total angular spread (radians) the pellets are fanned across.
@export var spread_rad: float = 0.0
@export var bullet_speed: float = 600.0
@export var is_special: bool = false
## Finite rounds the weapon carries when picked up. 0 = pistol (draws from the
## shooter's separate reserve pool instead).
@export var total_ammo: int = 0
