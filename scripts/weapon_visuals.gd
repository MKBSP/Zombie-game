extends RefCounted
class_name WeaponVisuals

## Single source of truth mapping a Weapons.* id to its sprite, so the equipped
## weapon renders the same on the player, NPCs, pickups, and the HUD.
static func texture(weapon_id: int) -> Texture2D:
	match weapon_id:
		Weapons.PISTOL:     return preload("res://sprites/Gun.png")
		Weapons.SHOTGUN:    return preload("res://sprites/Shotgun.png")
		Weapons.RIFLE:      return preload("res://sprites/Rifle.png")
		Weapons.MACHINEGUN: return preload("res://sprites/Machinegun.png")
		Weapons.MELEE:      return preload("res://sprites/Club.png")
	return null
