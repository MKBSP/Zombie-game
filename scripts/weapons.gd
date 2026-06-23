extends RefCounted
class_name Weapons

## Weapon catalogue + the shared bullet-spawning helper used by both the shooter
## and armed NPCs. Keeping fire() here means the spread/jitter math lives in one
## place. All callers run server-side (bullets replicate via the spawner).

enum { PISTOL, RIFLE, SHOTGUN }

const BULLET_SCENE: PackedScene = preload("res://scenes/bullet/bullet.tscn")

static var _cache: Dictionary = {}


static func get_data(id: int) -> WeaponData:
	if _cache.has(id):
		return _cache[id]
	# All stats live in Balance (single source of truth for tuning).
	var src: Dictionary
	match id:
		RIFLE:   src = Balance.RIFLE
		SHOTGUN: src = Balance.SHOTGUN
		_:       src = Balance.PISTOL
	var w := WeaponData.new()
	w.id = id
	w.display_name = src.display_name
	w.damage = src.damage
	w.cooldown = src.cooldown
	w.mag_size = src.mag_size
	w.reload_time = src.reload_time
	w.pellets = src.pellets
	w.bullet_speed = src.bullet_speed
	w.is_special = src.is_special
	w.total_ammo = src.total_ammo
	w.aim_base = src.aim_base
	w.aim_max = src.aim_max
	w.focus_min_scale = src.focus_min_scale
	w.optimal_range_px = src.optimal_range_px
	w.zero_range_px = src.zero_range_px
	_cache[id] = w
	return w


## Spawn this weapon's pellets from `origin`, each flying straight toward a
## uniform-random point inside the aim circle of radius `radius_px` centred on
## `cursor_pos`. Parented under `parent` (Entities) so the spawner replicates them.
static func fire(parent: Node, origin: Vector2, cursor_pos: Vector2, radius_px: float, w: WeaponData, source: Node = null) -> void:
	for _i in range(w.pellets):
		var aim_point := cursor_pos + AimModel.random_in_disk(radius_px)
		var dir := aim_point - origin
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
		dir = dir.normalized()
		var bullet := BULLET_SCENE.instantiate()
		bullet.global_position = origin
		bullet.rotation = dir.angle()
		bullet.direction = dir
		bullet.damage = w.damage
		bullet.speed = w.bullet_speed
		bullet.origin = origin
		bullet.optimal_range_px = w.optimal_range_px
		bullet.zero_range_px = w.zero_range_px
		bullet.weapon = w
		bullet.shooter_ref = source
		bullet.from_player = source != null
		parent.add_child(bullet, true)
