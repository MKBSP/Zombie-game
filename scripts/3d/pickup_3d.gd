extends StaticBody3D
## A loot item lying in the 3D world: out of a crate (loot_crate.gd), or a weapon
## the shooter let go of. E on it (viewmodel._interact) applies it: a spare
## pistol mag, a bandage or medpack, or a weapon under the carry rules (the
## weapon it replaces drops here). Only the interact ray sees it
## (INTERACT_LAYER); nothing collides with it. Checked by test/test_loot_3d.gd.

const W := preload("res://scripts/weapons.gd")
const L := preload("res://scripts/3d/fp_loadout.gd")
const Npc := preload("res://scripts/3d/npc_3d.gd")
const SELF := "res://scripts/3d/pickup_3d.gd"
const INTERACT_LAYER := 64  # physics layer 7, as viewmodel.INTERACT_LAYER
## Same order as the 2D Pickup.Kind, so the Balance.LOOT weights mean the same.
## (Not the 2D script itself: it preloads a scene that loads it back, which
## breaks headless loading.)
enum Kind { AMMO_MAG, RIFLE, SHOTGUN, MEDPACK, MACHINEGUN, MELEE, BANDAGE }
const KIND_TO_WEAPON := {Kind.RIFLE: W.RIFLE, Kind.SHOTGUN: W.SHOTGUN, Kind.MACHINEGUN: W.MACHINEGUN, Kind.MELEE: W.MELEE}
## Weapon -> [model, length in metres] when lying on the ground.
const MESH := {
	W.SHOTGUN: ["res://assets/weapons/shotgun.glb", 0.95],
	W.RIFLE: ["res://assets/weapons/rifle.glb", 1.1],
	W.MACHINEGUN: ["res://assets/weapons/uzi.glb", 0.4],
	W.MELEE: ["res://assets/weapons/bat.glb", 0.85],
}
## Everything else is a small coloured box (2D Pickup colours) with a name.
const LOOK := {
	Kind.AMMO_MAG: [Color(0.95, 0.85, 0.2), "pistol ammo"],
	Kind.MEDPACK: [Color(0.9, 0.2, 0.3), "medpack"],
	Kind.BANDAGE: [Color(0.95, 0.95, 0.9), "bandage"],
}

var kind: int = Kind.AMMO_MAG


static func drop(root: Node, pos: Vector3, kind_: int) -> StaticBody3D:
	var p: StaticBody3D = load(SELF).new()
	p.kind = kind_
	root.add_child(p)
	p.global_position = pos
	return p


static func weapon_kind(id: int) -> int:
	return KIND_TO_WEAPON.find_key(id)


func _ready() -> void:
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.35
	cs.shape = sh
	cs.position.y = 0.15
	add_child(cs)
	rotation.y = randf() * TAU
	if KIND_TO_WEAPON.has(kind):
		var m: Array = MESH[KIND_TO_WEAPON[kind]]
		var gun := Npc._fit_gun(load(m[0]).instantiate(), m[1])
		gun.position.y = 0.06
		add_child(gun)
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.1, 0.16)
	mi.mesh = box
	mi.position.y = 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = LOOK[kind][0]
	mat.emission_enabled = true  # a faint glow so it reads in the dark
	mat.emission = LOOK[kind][0]
	mat.emission_energy_multiplier = 0.25
	mi.material_override = mat
	add_child(mi)


func label() -> String:
	return L.NAMES[L.WEAPON.find(KIND_TO_WEAPON[kind])] if KIND_TO_WEAPON.has(kind) else LOOK[kind][1]


## Apply to the shooter's viewmodel (viewmodel.gd) and vanish.
func collect(vm) -> void:
	match kind:
		Kind.AMMO_MAG:
			vm.add_pistol_mag()
		Kind.BANDAGE:
			vm._player.heal(Balance.LOOT.heal_bandage)
		Kind.MEDPACK:
			vm._player.heal(Balance.LOOT.heal_medipack)
		_:
			var dropped: int = vm.give(KIND_TO_WEAPON[kind])
			if dropped != -1:
				drop(get_parent(), global_position, weapon_kind(dropped))
	queue_free()
