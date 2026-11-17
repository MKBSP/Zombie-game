extends SceneTree

## Headless check for 3D loot (scripts/3d/loot_crate.gd + pickup_3d.gd): a crate
## opens once into 1-3 pickups (a weapon guaranteed on the flagged crate), and a
## pickup routes to the shooter by kind, dropping the weapon that made way. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_3d.gd

var _failures := 0
var Crate = load("res://scripts/3d/loot_crate.gd")
var Pick = load("res://scripts/3d/pickup_3d.gd")
var W = load("res://scripts/weapons.gd")


## Stands in for viewmodel.gd: records what a pickup asked of it.
class FakeVm extends Node:
	var mags := 0
	var gave := -1
	var drop_on_give := -1
	var _player := FakePlayer.new()

	func add_pistol_mag() -> void:
		mags += 1

	func give(id: int, _ammo := {}) -> int:
		gave = id
		return drop_on_give


class FakePlayer extends RefCounted:
	var healed := 0

	func heal(n: int) -> void:
		healed += n


func _initialize() -> void:
	await process_frame
	# --- crates ---
	for seed in 20:
		var c = Crate.new()
		c.guarantee_weapon = true
		c.rng.seed = seed
		root.add_child(c)
		c.open()
		var items := _pickups()
		_check("seed %d: 1-3 items (got %d)" % [seed, items.size()], items.size() >= 1 and items.size() <= 3)
		_check("seed %d: weapon guaranteed" % seed, items.any(func(p): return Pick.KIND_TO_WEAPON.has(p.kind)))
		c.open()
		_check("seed %d: opens once" % seed, _pickups().size() == items.size() and c.opened)
		for p in items:
			p.free()
		c.free()
	var plain = Crate.new()
	plain.rng.seed = 3
	root.add_child(plain)
	_check("crate is solid world (bullets, bodies)", plain.collision_layer == 1)
	_check("3D kinds match the 2D Pickup.Kind order", Pick.Kind.AMMO_MAG == 0 and Pick.Kind.RIFLE == 1 and Pick.Kind.BANDAGE == 6)
	plain.free()

	# --- pickups ---
	var vm := FakeVm.new()
	root.add_child(vm)
	Pick.drop(root, Vector3.ZERO, Pick.Kind.AMMO_MAG).collect(vm)
	_check("ammo mag -> one pistol mag", vm.mags == 1)
	Pick.drop(root, Vector3.ZERO, Pick.Kind.BANDAGE).collect(vm)
	_check("bandage heals heal_bandage", vm._player.healed == Balance.LOOT.heal_bandage)
	Pick.drop(root, Vector3.ZERO, Pick.Kind.MEDPACK).collect(vm)
	_check("medpack heals heal_medipack", vm._player.healed == Balance.LOOT.heal_bandage + Balance.LOOT.heal_medipack)
	await process_frame
	_check("taken pickups are gone", _pickups().is_empty())
	vm.drop_on_give = W.RIFLE
	var sg = Pick.drop(root, Vector3(2, 0, 3), Pick.Kind.SHOTGUN)
	_check("pickups are interact-only (layer 64, no mask)", sg.collision_layer == 64 and sg.collision_mask == 0)
	sg.collect(vm)
	await process_frame
	_check("shotgun pickup gives the shotgun", vm.gave == W.SHOTGUN)
	var left := _pickups()
	_check("the rifle that made way lies there", left.size() == 1 and left[0].kind == Pick.Kind.RIFLE and left[0].global_position.is_equal_approx(Vector3(2, 0, 3)))

	# --- shots fly through loot: pickups are for the interact ray only ---
	var F = load("res://scripts/3d/impact_fx.gd")
	_check("shot mask: world, debris, part hitboxes", F.SHOT_MASK & 1 and F.SHOT_MASK & 16 and F.SHOT_MASK & 32)
	_check("shot mask: not zombie capsules, not pickups", not (F.SHOT_MASK & 2) and not (F.SHOT_MASK & 64))
	var loot = Pick.drop(root, Vector3(50, 0, 50), Pick.Kind.RIFLE)
	await physics_frame
	await physics_frame
	var q := PhysicsRayQueryParameters3D.create(Vector3(50, 0.15, 45), Vector3(50, 0.15, 55), F.SHOT_MASK)
	_check("a shot at a crawler's height passes over loot", root.get_world_3d().direct_space_state.intersect_ray(q).is_empty())
	loot.free()

	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _pickups() -> Array:
	return root.get_children().filter(func(n): return n.get_script() == Pick and not n.is_queued_for_deletion())


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
