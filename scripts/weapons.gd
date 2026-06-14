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
	var w := WeaponData.new()
	w.id = id
	match id:
		RIFLE:
			w.display_name = "Rifle"
			w.damage = 87.5          # 2.5x pistol
			w.cooldown = 0.0         # one-shot mag, gated by the 3s reload
			w.mag_size = 1
			w.reload_time = 3.0
			w.pellets = 1
			w.bullet_speed = 750.0
			w.is_special = true
			w.total_ammo = 10
		SHOTGUN:
			w.display_name = "Shotgun"
			w.damage = 28.0          # 0.8x pistol, per pellet
			w.cooldown = 0.0
			w.mag_size = 2
			w.reload_time = 3.0
			w.pellets = 5
			w.spread_rad = 0.5       # ~28 degree fan
			w.bullet_speed = 600.0
			w.is_special = true
			w.total_ammo = 8
		_:  # PISTOL
			w.display_name = "Pistol"
			w.damage = 35.0
			w.cooldown = 0.28
			w.mag_size = 15
			w.reload_time = 3.0
			w.pellets = 1
			w.bullet_speed = 600.0
			w.is_special = false
			w.total_ammo = 0
	_cache[id] = w
	return w


## Spawn this weapon's pellets from `origin` aimed at `base_angle`, parented under
## `parent` (the Entities node) so the MultiplayerSpawner replicates them.
## `jitter` adds a random per-pellet angle offset (NPC aim debuff; pass 0 for the
## player's crisp aim).
static func fire(parent: Node, origin: Vector2, base_angle: float, w: WeaponData, jitter: float) -> void:
	for i in range(w.pellets):
		var angle := base_angle
		if w.pellets > 1:
			# Fan evenly across spread_rad, centered on base_angle.
			var t := float(i) / float(w.pellets - 1) - 0.5
			angle += t * w.spread_rad
		if jitter > 0.0:
			angle += randf_range(-jitter, jitter)
		var bullet := BULLET_SCENE.instantiate()
		bullet.global_position = origin
		bullet.rotation = angle
		bullet.direction = Vector2.from_angle(angle)
		bullet.damage = w.damage
		bullet.speed = w.bullet_speed
		parent.add_child(bullet, true)
