extends Node2D
class_name LootBox

## A closed crate. Pressing interact next to it (server-side) rolls 1-3 items
## and bursts them onto the floor as Pickup nodes. Replicated: clients see the
## sprite swap to opened and the items arrive via the MultiplayerSpawner.

const PICKUP_SCENE := preload("res://scenes/pickup/pickup.tscn")
const TEX_CLOSED := preload("res://sprites/Crate_closed.png")
const TEX_OPENED := preload("res://sprites/Crate_opened.png")

@export var opened: bool = false:
	set(value):
		opened = value
		_refresh_sprite()


func _ready() -> void:
	add_to_group("loot_boxes")
	_refresh_sprite()


func _refresh_sprite() -> void:
	var s := get_node_or_null("Sprite2D")
	if s:
		s.texture = TEX_OPENED if opened else TEX_CLOSED


## Assemble the {Pickup.Kind: weight} table from Balance.LOOT. Lives here (not
## in LootTable) because LootTable must stay free of the Pickup type to remain
## headless-parseable; here Pickup resolves at runtime.
func _kind_weights() -> Dictionary:
	var l: Dictionary = Balance.LOOT
	return {
		Pickup.Kind.AMMO_MAG: l.weight_ammo_mag,
		Pickup.Kind.BANDAGE: l.weight_bandage,
		Pickup.Kind.MEDPACK: l.weight_medipack,
		Pickup.Kind.MELEE: l.weight_melee,
		Pickup.Kind.SHOTGUN: l.weight_shotgun,
		Pickup.Kind.MACHINEGUN: l.weight_machinegun,
		Pickup.Kind.RIFLE: l.weight_rifle,
	}


## Server-only: roll and spawn loot, then mark opened (replicates the swap).
func open() -> void:
	if opened or not multiplayer.is_server():
		return
	opened = true
	var world := get_tree().current_scene
	var count := LootTable.roll_item_count(randf(), Balance.LOOT.chance_two, Balance.LOOT.chance_three)
	var weights := _kind_weights()
	var placed: Array[Vector2] = []
	for _i in range(count):
		var k := LootTable.roll_kind(randf(), weights)
		var target: Vector2 = world.loot_landing_spot(global_position, placed)
		placed.append(target)
		var p: Pickup = PICKUP_SCENE.instantiate()
		p.kind = k
		p.spawn_origin = global_position
		p.position = target
		world.entities.add_child(p, true)
