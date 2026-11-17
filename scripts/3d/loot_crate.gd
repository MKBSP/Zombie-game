extends StaticBody3D
## A closed supply crate. E on it (viewmodel._interact) opens it into 1-3
## Pickup3D items by the 2D loot rules (LootTable + Balance.LOOT weights); the
## crate flagged guarantee_weapon always holds a weapon. Rolls come from its own
## rng, seeded by the spawner, so every peer gets the same loot. Solid: bodies
## and bullets hit it (wood). Checked headless by test/test_loot_3d.gd.

const LootTable := preload("res://scripts/loot_table.gd")
const LootScatter := preload("res://scripts/3d/loot_scatter.gd")
const Pickup3D := preload("res://scripts/3d/pickup_3d.gd")
const Npc := preload("res://scripts/3d/npc_3d.gd")
const SELF := "res://scripts/3d/loot_crate.gd"
const K = Pickup3D.Kind
const SIZE := Vector3(0.8, 0.55, 0.55)

var guarantee_weapon := false
var opened := false
var rng := RandomNumberGenerator.new()
var _lid: MeshInstance3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = SIZE
	cs.shape = sh
	cs.position.y = SIZE.y / 2
	add_child(cs)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.28, 0.15)
	wood.roughness = 0.9
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = SIZE - Vector3(0, 0.06, 0)
	body.mesh = bm
	body.position.y = bm.size.y / 2
	body.material_override = wood
	add_child(body)
	_lid = MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(SIZE.x + 0.04, 0.06, SIZE.z + 0.04)
	_lid.mesh = lm
	_lid.position.y = SIZE.y - 0.03
	_lid.material_override = wood
	add_child(_lid)


## Spread Balance.LOOT_3D.crate_count crates evenly over `rect` (world XZ): on
## walkable ground, against a building wall, clear of the points in `avoid`
## (the shooter's start). One of them always holds a weapon. Same seed, same
## crates and contents on every peer.
static func spawn_all(parent: Node3D, rect: Rect2, seed: int, avoid: Array) -> Array:
	var C: Dictionary = Balance.LOOT_3D
	var map := parent.get_world_3d().navigation_map
	var space := parent.get_world_3d().direct_space_state
	var accept := func(p: Vector2) -> Vector2:  # slid against the nearest wall, walkable and outdoors
		var q := Npc.spot_by_wall(map, space, Vector3(p.x, 0, p.y), C.wall_reach_m)
		if q == Vector3.INF or (not avoid.is_empty() and not Npc.reachable(map, avoid[0], q)):
			return Vector2.INF
		var q2 := Vector2(q.x, q.z)
		if avoid.any(func(a: Vector3) -> bool: return Vector2(a.x, a.z).distance_to(q2) < C.spawn_clear_m):
			return Vector2.INF
		return q2
	var out := []
	for p in LootScatter.scatter(rect, C.crate_count, seed, C.min_sep_m, accept):
		var c: StaticBody3D = load(SELF).new()
		c.rng.seed = hash([seed, out.size()])
		parent.add_child(c)
		var top := NavigationServer3D.map_get_closest_point(map, Vector3(p.x, 0, p.y)) + Vector3.UP
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 3.0, 1))
		c.global_position = hit.position if not hit.is_empty() else top - Vector3.UP
		c.rotation.y = c.rng.randf() * TAU
		out.append(c)
	if not out.is_empty():
		out[hash(seed) % out.size()].guarantee_weapon = true
	return out


## {Pickup3D.Kind: weight} from Balance.LOOT; weapons only for the guaranteed roll.
static func weights(weapons_only: bool) -> Dictionary:
	var l: Dictionary = Balance.LOOT
	var w := {K.MELEE: l.weight_melee, K.SHOTGUN: l.weight_shotgun, K.MACHINEGUN: l.weight_machinegun, K.RIFLE: l.weight_rifle}
	if not weapons_only:
		w.merge({K.AMMO_MAG: l.weight_ammo_mag, K.BANDAGE: l.weight_bandage, K.MEDPACK: l.weight_medipack})
	return w


func open() -> void:
	if opened:
		return
	opened = true
	_lid.position = Vector3(0, 0.03, SIZE.z / 2 + 0.35)  # knocked off onto the ground
	_lid.rotation.x = 0.25
	var l: Dictionary = Balance.LOOT
	var n := LootTable.roll_item_count(rng.randf(), l.chance_two, l.chance_three)
	for i in n:
		var kind := LootTable.roll_kind(rng.randf(), weights(guarantee_weapon and i == 0))
		Pickup3D.drop(get_parent(), _landing(i, n), kind)


## Where item i of n lands: around the crate on walkable, reachable, outdoor
## ground, clear of the crate itself. The crate stands against a wall, so many
## directions point into a building (the hollow shells have navmesh inside):
## try a few, and as a last resort rest it on the open crate.
func _landing(i: int, n: int) -> Vector3:
	var map := get_world_3d().navigation_map
	var space := get_world_3d().direct_space_state
	var base := TAU * float(i) / n
	for k in 8:
		var a := base + rng.randf_range(-0.4, 0.4) + k * TAU / 8.0
		var p := global_position + Vector3(cos(a), 0, sin(a)) * Balance.LOOT_3D.burst_m * rng.randf_range(0.6, 1.0)
		var nav := NavigationServer3D.map_get_closest_point(map, p)
		if nav == Vector3.ZERO:
			break  # no navmesh (tests): nothing to check against
		var flat := Vector2(nav.x - global_position.x, nav.z - global_position.z).length()
		if flat < 0.7 or not Npc.outdoors(space, nav) or not Npc.reachable(map, global_position, nav):
			continue
		var q := PhysicsRayQueryParameters3D.create(nav + Vector3.UP, nav + Vector3.DOWN * 1.5, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		return hit.position if not hit.is_empty() else Vector3(nav.x, global_position.y, nav.z)
	return global_position + Vector3.UP * SIZE.y
