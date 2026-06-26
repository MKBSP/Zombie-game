extends Area2D
class_name Pickup

## A world item the shooter walks over. One scene covers all kinds; `kind`
## (replicated on spawn) drives both the tint and the effect. Effects run
## server-side and mutate the shooter directly.

enum Kind { AMMO_MAG, RIFLE, SHOTGUN, MEDPACK, MACHINEGUN, MELEE }

const COLORS := {
	Kind.AMMO_MAG: Color(0.95, 0.85, 0.2),
	Kind.RIFLE: Color(0.4, 0.6, 1.0),
	Kind.SHOTGUN: Color(1.0, 0.5, 0.2),
	Kind.MEDPACK: Color(0.9, 0.2, 0.3),
	Kind.MACHINEGUN: Color(0.6, 0.6, 0.65),
	Kind.MELEE: Color(0.7, 0.7, 0.75),
}

const PICKUP_SCENE := preload("res://scenes/pickup/pickup.tscn")

## Maps a Weapons.* id to the matching Pickup.Kind, so a swapped-out weapon can
## be re-dropped as the right pickup.
const WEAPON_TO_KIND := {
	Weapons.RIFLE: Kind.RIFLE,
	Weapons.SHOTGUN: Kind.SHOTGUN,
	Weapons.MACHINEGUN: Kind.MACHINEGUN,
	Weapons.MELEE: Kind.MELEE,
}

## Inverse of WEAPON_TO_KIND, for showing the weapon PNG on the floor.
const KIND_TO_WEAPON := {
	Kind.RIFLE: Weapons.RIFLE,
	Kind.SHOTGUN: Weapons.SHOTGUN,
	Kind.MACHINEGUN: Weapons.MACHINEGUN,
	Kind.MELEE: Weapons.MELEE,
}

@export var kind: int = Kind.AMMO_MAG:
	set(value):
		kind = value
		_refresh_color()


func _ready() -> void:
	_refresh_color()
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _refresh_color() -> void:
	var s := get_node_or_null("Sprite2D")
	if s == null:
		return
	if KIND_TO_WEAPON.has(kind):
		s.texture = WeaponVisuals.texture(KIND_TO_WEAPON[kind])
		s.modulate = Color.WHITE
	else:
		s.modulate = COLORS.get(kind, Color.WHITE)


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("shooter"):
		return
	match kind:
		Kind.AMMO_MAG:
			body.add_pistol_mag()
		Kind.RIFLE:
			_take_special(body, Weapons.RIFLE)
		Kind.SHOTGUN:
			_take_special(body, Weapons.SHOTGUN)
		Kind.MACHINEGUN:
			_take_special(body, Weapons.MACHINEGUN)
		Kind.MELEE:
			_take_melee(body, Weapons.MELEE)
		Kind.MEDPACK:
			body.heal(50)
	queue_free()


## Hand `weapon_id` to the shooter. If they're already holding a *different*
## special, drop that old one on the ground first so it isn't lost.
func _take_special(body: Node2D, weapon_id: int) -> void:
	var old: int = body.held_special
	if old != -1 and old != weapon_id:
		_drop_weapon_pickup(old, body)
	body.give_special(weapon_id)


## Hand a melee to the shooter, dropping any different melee they hold.
func _take_melee(body: Node2D, weapon_id: int) -> void:
	var old: int = body.held_melee
	if old != -1 and old != weapon_id:
		_drop_weapon_pickup(old, body)
	body.give_melee(weapon_id)


## Spawn the swapped-out weapon as a world pickup, offset behind the shooter so
## it doesn't get instantly re-collected.
func _drop_weapon_pickup(weapon_id: int, body: Node2D) -> void:
	if not WEAPON_TO_KIND.has(weapon_id):
		return
	var entities := get_tree().current_scene.get_node_or_null("Entities")
	if entities == null:
		return
	var p: Node2D = PICKUP_SCENE.instantiate()
	p.kind = WEAPON_TO_KIND[weapon_id]
	p.global_position = body.global_position - Vector2.from_angle(body.global_rotation) * 72.0
	entities.add_child(p, true)
