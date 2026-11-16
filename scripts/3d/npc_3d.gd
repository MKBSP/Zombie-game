extends CharacterBody3D
## 3D NPC survivor, ported from scenes/npc/npc_human.gd with the same states and
## Balance.NPC numbers (pixels converted with Zombie3D.m; speed / sight are
## 3D-only, Balance.NPC_3D):
##   HIDDEN      waits 10-20 s at a hiding spot (on the navmesh, next to a building)
##   RELOCATING  meanders via 2-4 jittered waypoints to a new spot within ~22 m
##   FOLLOWING   once a shooter walks into it: walks the shooter's breadcrumb trail
##               single file; with a zombie near the shooter it takes a formation
##               slot behind (armed ones on the flanks) and, if armed, fights once
##               the shooter opens fire (engagement latch), with sloppy NPC aim
##   CONVERTING  bitten: frozen for convert_duration, then a standard zombie takes
##               its place (handed to the commander)
## Bullets can kill it at any time, and that never makes a zombie. The shooter's
## interact key hands a follower the gun in hand, or takes it back (viewmodel.gd).
## Model: one of MODELS, animated by character_anim.gd.

const Z := preload("res://scripts/3d/zombie_3d.gd")
const L := preload("res://scripts/3d/fp_loadout.gd")
const W := preload("res://scripts/weapons.gd")
const Anim := preload("res://scripts/3d/character_anim.gd")
const LAYER := 8                # physics layer 4, as the 2D NPCs
const EYE := Vector3(0, 1.5, 0)
## [model, clip prefix, scale] — Quaternius, CC0 (CREDITS.md)
const MODELS := [
	["res://assets/characters/business_man.glb", "CharacterArmature|", 1.0],
	["res://assets/characters/hoodie.glb", "CharacterArmature|", 1.0],
	["res://assets/characters/man.glb", "HumanArmature|Man_", 0.4],
]
## weapon id -> [model, real length in m]; fitted and laid along -Z on hand-over
const GUNS := {
	W.PISTOL: ["res://assets/weapons/pistol.glb", 0.22],
	W.SHOTGUN: ["res://assets/weapons/shotgun.glb", 0.95],
	W.RIFLE: ["res://assets/weapons/rifle.glb", 1.1],
	W.MACHINEGUN: ["res://assets/weapons/uzi.glb", 0.4],
}

enum State { HIDDEN, RELOCATING, FOLLOWING, CONVERTING }

signal converted(zombie: Node3D)

var model := 0
var state: State = State.HIDDEN
var hp := 50
var max_hp := 50
var is_dead := false
var shooter: Node3D = null
var weapon_id := -1
var weapon_mag := 0
var weapon_total := 0
var convert_progress := -1.0

var _agent: NavigationAgent3D
var _speed := 2.7
var _hide_t := 0.0
var _waypoints: Array[Vector3] = []
var _convert_t := 0.0
var _label: Label3D
var _gun: Node3D
var _flash: OmniLight3D
var _engaged := false
var _shot_cd := 0.0
var _reloading := false
var _recoil := 0.0
var _recoil_el := 0.0
var _recoil_rec := 0.0
var _threat: Node3D = null
var _threat_lock := 0.0
var _form_dir := Vector2.ZERO
var _last_dir := Vector2(0, 1)


static func m(px: float) -> float:
	return Z.m(px)


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("noise_listeners")
	max_hp = Balance.NPC.max_hp
	hp = max_hp
	_speed = Balance.NPC_3D.speed_mps
	collision_layer = LAYER
	collision_mask = 1 | 2  # world + zombies; not other NPCs (avoidance spaces them, as in 2D)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	var cs := CollisionShape3D.new()
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)

	var md: Array = MODELS[model]
	var body: Node3D = load(md[0]).instantiate()
	body.set_script(Anim)
	body.prefix = md[1]
	body.scale = Vector3.ONE * md[2]
	body.rotation.y = PI  # Quaternius models face +Z
	add_child(body)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 2.15
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.8, 0.2)
	_label.visible = false
	add_child(_label)
	_flash = OmniLight3D.new()
	_flash.position = Vector3(0.22, 1.2, -0.6)
	_flash.light_color = Color(1.0, 0.8, 0.5)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	add_child(_flash)

	_agent = NavigationAgent3D.new()
	_agent.radius = 0.4
	_agent.height = 1.75
	_agent.max_speed = 7.0  # room for the catch-up run (avoidance clamps to this)
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = m(Balance.SEPARATION.neighbor_distance)
	_agent.max_neighbors = Balance.SEPARATION.max_neighbors
	_agent.time_horizon_agents = Balance.SEPARATION.time_horizon
	# The navmesh floats ~0.45 m over the ground, so "reached" has to reach past that
	# (as zombie_3d.gd's 0.6) or the agent never leaves its first waypoint.
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)
	_start_hidden(randf_range(1.0, 4.0))  # so they don't all move at once


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 60.0)
	_check_recruit()
	match state:
		State.CONVERTING:
			_converting(delta)
			_stop()
		State.HIDDEN:
			_hide_t -= delta
			if _hide_t <= 0.0:
				_plan_relocation()
			_stop()
		State.RELOCATING:
			if _agent.is_navigation_finished():
				if _waypoints.is_empty():
					_start_hidden(randf_range(Balance.NPC.hide_min, Balance.NPC.hide_max))
				else:
					_agent.target_position = _waypoints.pop_front()
				_stop()
			else:
				_nav_move(_speed)
		State.FOLLOWING:
			_following(delta)
			if weapon_id != -1:
				_shooting(delta)


func _nav_move(spd: float) -> void:
	var v := _agent.get_next_path_position() - global_position
	v.y = 0.0
	_agent.velocity = v.normalized() * spd


func _stop() -> void:
	_agent.velocity = Vector3.ZERO


func _on_velocity_computed(safe: Vector3) -> void:
	velocity.x = safe.x
	velocity.z = safe.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * get_physics_process_delta_time()
	move_and_slide()
	if Vector2(velocity.x, velocity.z).length() > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 0.2)


# --- hiding ---------------------------------------------------------------------

func _start_hidden(duration: float) -> void:
	state = State.HIDDEN
	_hide_t = duration
	_waypoints.clear()


## A hiding spot: on the navmesh, with a building wall within 1.5 m.
func _hiding_spot() -> Vector3:
	var map := get_world_3d().navigation_map
	var r := m(Balance.NPC.hide_radius * 64.0)
	for i in 40:
		var p := NavigationServer3D.map_get_closest_point(map, global_position + Vector3(randf_range(-r, r), 0, randf_range(-r, r)))
		if p != Vector3.ZERO and next_to_building(get_world_3d().direct_space_state, p):
			return p
	return Vector3.INF


static func next_to_building(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP, p + Vector3.UP + d * 1.5, 1))
		if not hit.is_empty() and String(hit.collider.get_parent().name).begins_with("Building"):
			return true
	return false


## A nervous wander to a new hiding spot: 2-4 waypoints jittered off the line.
func _plan_relocation() -> void:
	var spot := _hiding_spot()
	if spot == Vector3.INF:
		_start_hidden(randf_range(1.0, 3.0))
		return
	var map := get_world_3d().navigation_map
	var jitter := m(3 * 64.0)
	var steps := randi_range(2, 4)
	_waypoints.clear()
	for i in range(1, steps):
		var on_line := global_position.lerp(spot, float(i) / steps)
		_waypoints.append(NavigationServer3D.map_get_closest_point(map,
				on_line + Vector3(randf_range(-jitter, jitter), 0, randf_range(-jitter, jitter))))
	_waypoints.append(spot)
	state = State.RELOCATING
	_agent.target_position = _waypoints.pop_front()


# --- following + formation (2D npc_human.gd / NpcFollow) ------------------------

func _check_recruit() -> void:
	if state == State.FOLLOWING or state == State.CONVERTING:
		return
	for s in get_tree().get_nodes_in_group("shooter"):
		if s.get("is_dead") != true and Z._flat(s.global_position, global_position) < Balance.NPC_3D.recruit_m:
			shooter = s
			state = State.FOLLOWING
			return


func _following(delta: float) -> void:
	if not is_instance_valid(shooter) or shooter.get("is_dead") == true:
		shooter = null
		_engaged = false
		_start_hidden(randf_range(1.0, 3.0))
		return
	var sv := Vector2(shooter.velocity.x, shooter.velocity.z) if shooter is CharacterBody3D else Vector2.ZERO
	if sv.length() > 0.15:
		_last_dir = sv.normalized()
	var order := _follower_order()
	var slot := maxi(order.find(self), 0)
	var armed := order.filter(func(n): return n.weapon_id != -1).size()
	var sp := Z._xz(shooter.global_position)
	var follow: Vector2
	var threat := _update_threat(delta)
	var b: Dictionary = Balance.NPC
	if threat:
		var dir := (Z._xz(threat.global_position) - sp).normalized()
		if _form_dir == Vector2.ZERO:
			_form_dir = dir
		else:
			_form_dir = _form_dir.rotated(_form_dir.angle_to(dir) * (1.0 - exp(-delta / b.form_dir_tau))).normalized()
		follow = NpcFollow.formation_slot(sp, _form_dir, slot, armed, m(b.formation_back_px), m(b.formation_side_px))
	else:
		_form_dir = Vector2.ZERO
		var trail = shooter.get("trail")
		follow = NpcFollow.trail_point(trail if trail != null else PackedVector2Array(), m(b.slot_spacing_px) * (slot + 1))
		if follow == Vector2.INF:
			follow = sp - _last_dir * m(b.follow_distance)
	var goal := Vector3(follow.x, global_position.y, follow.y)
	var dist := Z._xz(global_position).distance_to(follow)
	if dist < m(b.follow_deadzone):
		_stop()
		return
	if _agent.target_position.distance_to(goal) > m(b.retarget_px):
		_agent.target_position = goal
	if _agent.is_navigation_finished():
		_stop()
		return
	# Walk like the 2D NPC (10% under the shooter's walk); run to catch up when
	# the shooter sprints off, at 90% of the sprint.
	var spd := _speed
	if dist > Balance.NPC_3D.catchup_m:
		spd = maxf(_speed, (shooter.get("sprint_speed") if shooter.get("sprint_speed") else 6.0) * 0.9)
	_nav_move(spd * clampf(dist / m(b.arrive_slow_px), 0.3, 1.0))


## Followers of my shooter in a stable slot order: armed first, then by name.
func _follower_order() -> Array:
	var out := get_tree().get_nodes_in_group("npcs").filter(func(n):
		return n.state == State.FOLLOWING and n.shooter == shooter and not n.is_dead)
	out.sort_custom(func(a, b):
		if (a.weapon_id != -1) != (b.weapon_id != -1):
			return a.weapon_id != -1
		return String(a.name) < String(b.name))
	return out


## Sticky threat pick with hysteresis (2D anti-jiggle): the nearest zombie near
## the shooter, switched at most once per threat_hold_s, dropped past threat_exit.
func _update_threat(delta: float) -> Node3D:
	var b: Dictionary = Balance.NPC
	_threat_lock = maxf(0.0, _threat_lock - delta)
	if _threat != null and (not is_instance_valid(_threat) or _threat.is_dead \
			or Z._flat(shooter.global_position, _threat.global_position) > m(b.threat_exit_px)):
		_threat = null
	if _threat_lock <= 0.0:
		var best: Node3D = null
		var best_d := m(b.threat_radius_px)
		for z in get_tree().get_nodes_in_group("zombies"):
			var d := Z._flat(shooter.global_position, z.global_position)
			if d < best_d:
				best_d = d
				best = z
		if best != null and best != _threat:
			_threat = best
			_threat_lock = b.threat_hold_s
	return _threat


# --- armed NPCs -------------------------------------------------------------------

## The shooter firing near us is the spark that engages an armed follower.
func hear_gunshot(pos: Vector3) -> void:
	if state == State.FOLLOWING and weapon_id != -1 and is_instance_valid(shooter) \
			and Z._flat(pos, shooter.global_position) < 3.0:
		_engaged = true


func _shooting(delta: float) -> void:
	var b: Dictionary = Balance.NPC
	_shot_cd -= delta
	_recoil_el += delta
	_recoil = NpcAim.recoil_after(b.recoil_initial, _recoil_el, _recoil_rec)
	var w := W.get_data(weapon_id)
	if _reloading and _shot_cd <= 0.0:
		weapon_mag += mini(w.mag_size - weapon_mag, weapon_total - weapon_mag)
		_reloading = false
	var target := _nearest_seen_zombie()
	if target == null:
		_engaged = false
		return
	if not _engaged or _reloading or _shot_cd > 0.0 or weapon_mag <= 0:
		return
	var from := global_position + EYE
	var aim: Vector3 = target.global_position + Vector3.UP * 1.1
	if _blocked_by_friend(from, aim):
		return  # hold fire: the shooter (or another survivor) is in the way
	var moving := Vector2(velocity.x, velocity.z).length() > 0.15
	var coeff := AimModel.spread_coeff(w, NpcAim.aim_debuff(b, moving, hp, max_hp, _recoil), 0.0)
	var radius := coeff * from.distance_to(aim) * Balance.NPC_3D.aim_scale
	var space := get_world_3d().direct_space_state
	for i in w.pellets:
		var p := aim + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized() * radius * pow(randf(), 1.0 / 3.0)
		var dir := (p - from).normalized()
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * Balance.FP.max_range_m)
		q.collision_mask = 0xFFFFFFFF & ~2  # zombie part hitboxes, not their capsules
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider.has_method("take_hit"):
			hit.collider.take_hit(w.damage * L.falloff(w, from.distance_to(hit.position)), hit.position, dir)
	_flash.light_energy = 4.0
	get_tree().call_group("noise_listeners", "hear_gunshot", global_position)
	_recoil_el = 0.0
	_recoil_rec = b.recoil_recover_factor * (w.damage * w.pellets) / b.dmg_ref
	weapon_mag -= 1
	weapon_total -= 1
	if weapon_total <= 0:
		surrender_weapon()  # spent
	elif weapon_mag <= 0:
		_reloading = true
		_shot_cd = w.reload_time
	else:
		_shot_cd = maxf(w.cooldown, b.min_shot_interval)


func _blocked_by_friend(from: Vector3, to: Vector3) -> bool:
	for f in get_tree().get_nodes_in_group("shooter") + get_tree().get_nodes_in_group("npcs"):
		if f == self or f.get("is_dead") == true:
			continue
		var chest: Vector3 = f.global_position + Vector3.UP * 1.2
		if chest.distance_to(Geometry3D.get_closest_point_to_segment(chest, from, to)) < 0.6:
			return true
	return false


func _nearest_seen_zombie() -> Node3D:
	var best: Node3D = null
	var best_d: float = Balance.NPC_3D.vision_m
	var space := get_world_3d().direct_space_state
	for z in get_tree().get_nodes_in_group("zombies"):
		var d := global_position.distance_to(z.global_position)
		if d < best_d and Z.buildings_clear(space, global_position + EYE, z.global_position + Vector3.UP):
			best_d = d
			best = z
	return best


func receive_weapon(id: int, total: int) -> void:
	surrender_weapon()
	weapon_id = id
	weapon_total = total
	weapon_mag = mini(W.get_data(id).mag_size, total)
	_reloading = false
	_shot_cd = 0.0
	if GUNS.has(id):
		_gun = _fit_gun(load(GUNS[id][0]).instantiate(), GUNS[id][1])
		_gun.position = Vector3(0.22, 1.1, -0.32)
		add_child(_gun)


## Wrap a weapon model so its longest axis lies along -Z at `length` metres.
static func _fit_gun(model: Node3D, length: float) -> Node3D:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.transform * mi.get_aabb()  # local to the model root (one level is all these packs use)
		box = b if first else box.merge(b)
		first = false
	var size := box.size
	var longest := size.max_axis_index()
	var holder := Node3D.new()
	holder.add_child(model)
	model.position = -box.get_center()
	if longest == Vector3.AXIS_X:
		holder.rotation.y = PI / 2
	elif longest == Vector3.AXIS_Y:
		holder.rotation.x = PI / 2
	holder.scale = Vector3.ONE * length / maxf(size[longest], 0.001)
	var pivot := Node3D.new()  # keeps the caller's position un-rotated
	pivot.add_child(holder)
	return pivot


## Hand the gun back: {id, total} (id -1 = was unarmed).
func surrender_weapon() -> Dictionary:
	var data := {id = weapon_id, total = weapon_total}
	weapon_id = -1
	weapon_mag = 0
	weapon_total = 0
	_engaged = false
	if _gun:
		_gun.queue_free()
		_gun = null
	return data


# --- conversion + death -------------------------------------------------------------

## A zombie's bite (zombie_3d.gd): the conversion is inevitable from here.
func force_convert() -> void:
	if state == State.CONVERTING or is_dead:
		return
	state = State.CONVERTING
	_convert_t = 0.0
	convert_progress = 0.0
	_engaged = false
	_label.visible = true


func _converting(delta: float) -> void:
	_convert_t += delta
	convert_progress = _convert_t / Balance.NPC.convert_duration
	var n := int(convert_progress * 10.0)
	_label.text = "TURNING  " + "|".repeat(n) + ".".repeat(10 - n)
	if convert_progress < 1.0:
		return
	var z := Z.new()
	z.variant = Z.Variant.STANDARD
	z.position = global_position
	var cmd := get_tree().get_first_node_in_group("commander")
	if cmd:
		cmd.add_zombie(z)
	else:
		get_parent().add_child(z)
	converted.emit(z)
	queue_free()


## Bullets / the bat. Death never makes a zombie: shooting a turning survivor
## before the bar fills is the only way to stop a conversion.
func take_hit(damage: float, _pos: Vector3, _dir: Vector3) -> void:
	take_damage(damage)


func take_damage(amount: float) -> void:
	if is_dead:
		return
	hp -= int(amount)
	if hp > 0:
		return
	is_dead = true
	_label.visible = false
	surrender_weapon()
	remove_from_group("npcs")
	remove_from_group("noise_listeners")
	collision_layer = 0
	_agent.avoidance_enabled = false
	get_tree().create_timer(Balance.NPC_3D.corpse_s).timeout.connect(queue_free)


## Scatter `count` survivors over the map at hiding spots, at least min_dist
## from every point in `avoid` (the shooter, the horde).
static func spawn_all(parent: Node3D, count: int, avoid: Array, min_dist: float) -> Array:
	var map := parent.get_world_3d().navigation_map
	var space := parent.get_world_3d().direct_space_state
	var out := []
	for tries in count * 60:
		if out.size() >= count:
			break
		var p := NavigationServer3D.map_get_random_point(map, 1, true)
		if avoid.any(func(a): return Z._flat(a, p) < min_dist) or out.any(func(n): return Z._flat(n.position, p) < 12.0):
			continue
		if not next_to_building(space, p):
			continue
		var npc = load("res://scripts/3d/npc_3d.gd").new()
		npc.model = out.size() % MODELS.size()
		npc.position = p
		parent.add_child(npc)
		out.append(npc)
	return out
