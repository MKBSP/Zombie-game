extends Area2D
class_name Pickup

## A world item the shooter walks over. One scene covers all kinds; `kind`
## (replicated on spawn) drives both the tint and the effect. Effects run
## server-side and mutate the shooter directly.

enum Kind { AMMO_MAG, RIFLE, SHOTGUN, MEDPACK }

const COLORS := {
	Kind.AMMO_MAG: Color(0.95, 0.85, 0.2),
	Kind.RIFLE: Color(0.4, 0.6, 1.0),
	Kind.SHOTGUN: Color(1.0, 0.5, 0.2),
	Kind.MEDPACK: Color(0.9, 0.2, 0.3),
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
	if s:
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
			body.give_special(Weapons.RIFLE)
		Kind.SHOTGUN:
			body.give_special(Weapons.SHOTGUN)
		Kind.MEDPACK:
			body.heal(50)
	queue_free()
