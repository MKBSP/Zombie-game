extends CharacterBody3D
## 3D zombie unit (Phase 10 slice for the commander): the zombie model
## (scripts/3d/zombie_body.gd) on a capsule collider per variant, run by the 2D
## stance machine ported from scenes/zombie/zombie.gd —
## same Balance numbers, pixels converted at Balance.FP.px_per_m, except speed,
## sight and hearing, which are 3D-only (Balance.ZOMBIE_3D). Sight needs a clear
## line past the buildings (can_see). Orders come
## from scripts/3d/commander.gd. First-person weapon hits land on the body's
## bone hitboxes -> take_part_hit(): six HP pools (spec §6, Balance.ZOMBIE_PARTS),
## death on head or body, a lost leg hobbles, two crawl, lost arms slow the
## attack. The movement capsule is on physics layer 2, which weapon rays skip,
## so a shot always lands on a part. Commander-only markers (selection
## ring, stance dot, rim silhouette through walls) sit on render layer
## COMMANDER_LAYER, which the first-person camera never draws.

const B := preload("res://scripts/balance.gd")
const Body := preload("res://scripts/3d/zombie_body.gd")
const LIMBS := ["arm_l", "arm_r", "leg_l", "leg_r"]

enum Variant { STANDARD, FAST, FAT, MASTER }
enum Combat { AGGRESSIVE, HOLD }
enum Movement { FREE, FLEE, PATROL }
enum FleeTrigger { ON_SIGHT, ON_DAMAGE, IDLE }

const COMMANDER_LAYER := 4  # render layer 3
const EYE := Vector3(0, 1.6, 0)
const FALLBACK_SPRINT := 6.0  # test_player.sprint_speed, if no shooter is around
const STATS := [B.ZOMBIE, B.FAST, B.FAT, B.MASTER]
## Movement capsule [radius, height] per variant; rim colour for the commander.
const BODY := [[0.3, 1.75], [0.3, 1.0], [0.45, 2.1], [0.4, 2.0]]
const TINT := [Color(0.33, 0.45, 0.3), Color(0.75, 0.68, 0.2), Color(0.5, 0.36, 0.24), Color(0.55, 0.15, 0.5)]
const NAMES := ["standard", "fast", "fat", "master"]

signal died(zombie: Node3D)
signal bit(zombie: Node3D, target: Node3D, damage: int)

var variant: int = Variant.STANDARD
var speed := 1.0
var max_hp := 150
var hp := 150
var vision_m := 3.7
var reach_m := 1.1
var damage_per_hit := 15
var attack_interval := 1.0
var is_dead := false
var is_selected := false
var merging := false
var combat_stance: int = Combat.AGGRESSIVE
var movement_mode: int = Movement.FREE
var flee_trigger: int = FleeTrigger.ON_SIGHT
var flee_point := Vector3.ZERO
var patrol_a := Vector3.ZERO
var patrol_b := Vector3.ZERO
var command_mode := false
var command_target := Vector3.ZERO
## Explicit attack order (right-click on an enemy): chased while any zombie sees it.
var attack_target: Node3D = null
var target: Node3D = null

var _merge_target := Vector3.ZERO
var _fled := false
var _patrol_leg := 0
var _damaged_timer := 0.0
var _alert_timer := 0.0
var _alert_point := Vector3.ZERO
var _cooldown := 0.0
var accel := 5.0
var _dt := 0.0
var _chasing: Node3D = null    # the enemy being chased, as registered (see _chase)
var _chased := false
var _react_t := 0.0
var _seen_pos := Vector3.ZERO
var _seen_valid := false
var _search_t := 0.0           # after losing sight: keep going to where it was last seen
var _agent: NavigationAgent3D
var _body: Body
var _shape: CapsuleShape3D
var parts := {}                # part -> hp left (head, body, arm_l/r, leg_l/r)
var _base_speed := 1.0
var _base_interval := 1.0
var _ring: MeshInstance3D
var _dot: MeshInstance3D

static var _xray_shader: Shader
static var _mats := {}


static func m(px: float) -> float:
	return px / B.FP.px_per_m


func _ready() -> void:
	add_to_group("zombies")
	add_to_group("noise_listeners")
	var s: Dictionary = STATS[variant]
	var sh := get_tree().get_first_node_in_group("shooter")
	speed = speed_for(variant, sh.get("sprint_speed") if sh and sh.get("sprint_speed") else FALLBACK_SPRINT)
	_base_speed = speed
	max_hp = s.max_hp
	hp = max_hp
	var pt: Dictionary = B.ZOMBIE_PARTS[NAMES[variant]]
	parts = {head = pt.head, body = max_hp, arm_l = pt.arm, arm_r = pt.arm, leg_l = pt.leg, leg_r = pt.leg}
	vision_m = B.ZOMBIE_3D.vision_m[NAMES[variant]]
	accel = B.ZOMBIE_3D.accel_mps2[NAMES[variant]]
	reach_m = m(s.contact_px)
	damage_per_hit = s.damage_per_hit
	attack_interval = s.attack_interval
	_base_interval = attack_interval
	collision_layer = 2       # zombies
	collision_mask = 1 | 2 | 8  # world + other zombies + NPCs (solid vs both, as in 2D)
	var r: float = BODY[variant][0]
	var h: float = BODY[variant][1]
	_shape = CapsuleShape3D.new()
	_shape.radius = r
	_shape.height = h
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	cs.position.y = h / 2
	add_child(cs)

	_body = Body.new()
	add_child(_body)
	_body.setup(self, variant)
	_body.overlay(_xray(TINT[variant]), COMMANDER_LAYER)
	var ring := TorusMesh.new()
	ring.inner_radius = r + 0.12
	ring.outer_radius = r + 0.24
	_ring = _mesh(ring, Vector3(0, 0.06, 0), _mat("ring", Color(0.3, 1.0, 0.35), true))
	_ring.scale = Vector3(1, 0.2, 1)
	_ring.layers = COMMANDER_LAYER
	_ring.visible = false
	var dot := SphereMesh.new()
	dot.radius = 0.13
	dot.height = 0.26
	_dot = _mesh(dot, Vector3(0, h + 0.35, 0), null)
	_dot.layers = COMMANDER_LAYER
	_dot.visible = false
	_set_dot()

	var sep: Dictionary = B.SEPARATION
	_agent = NavigationAgent3D.new()
	_agent.radius = r + 0.15
	_agent.height = h
	_agent.max_speed = speed
	_agent.avoidance_enabled = true
	_agent.neighbor_distance = m(sep.neighbor_distance)
	_agent.max_neighbors = sep.max_neighbors
	_agent.time_horizon_agents = sep.time_horizon
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.5
	_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(_agent)
	_agent.target_position = global_position


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_dt = delta
	if not _chased:
		_chasing = null
	_chased = false
	_damaged_timer -= delta
	_alert_timer -= delta
	_search_t -= delta
	_bite(delta)

	# Merging overrides everything: walk to the merge point, no avoidance.
	if merging:
		_agent.target_position = _merge_target
		_move()
		return

	if attack_target != null and (not is_instance_valid(attack_target) or attack_target.get("is_dead") == true):
		attack_target = null
	if attack_target != null:
		if _seen_by_horde(attack_target.global_position):
			target = attack_target
			_chase(attack_target)
			_move()
			return
		set_command(attack_target.global_position)  # lost sight: go to the last-seen spot

	if command_mode:
		_agent.target_position = command_target
		if _agent.is_navigation_finished():
			command_mode = false
		_move()
		return

	if movement_mode == Movement.FLEE and not _fled and _flee_should_trigger():
		_fled = true
	if _fled:
		_parked(flee_point)
	elif movement_mode == Movement.PATROL:
		_patrol()
	else:
		_free()
	_move()


func _process(delta: float) -> void:
	if not is_dead:
		_body.animate(delta, Vector2(velocity.x, velocity.z).length())


func _move() -> void:
	var v := Vector3.ZERO
	if not _agent.is_navigation_finished():
		v = _agent.get_next_path_position() - global_position
		v.y = 0.0
		v = v.normalized() * speed
	if _agent.avoidance_enabled:
		_agent.velocity = v
	else:
		_on_velocity_computed(v)


## Head for where this zombie last registered the enemy: a beat to notice a new
## one, then a fresh read every ~reaction_s. Until the first read it carries on
## with whatever it was doing.
func _chase(e: Node3D) -> void:
	_chased = true
	if e != _chasing:
		_chasing = e
		_seen_valid = false
		_react_t = B.ZOMBIE_3D.notice_s
	_react_t -= _dt
	if _react_t <= 0.0:
		_seen_pos = e.global_position
		_seen_valid = true
		_search_t = B.ZOMBIE_3D.search_s
		_react_t = B.ZOMBIE_3D.reaction_s * randf_range(0.7, 1.3)
	if _seen_valid:
		_agent.target_position = _seen_pos


func _on_velocity_computed(safe: Vector3) -> void:
	# momentum: speed changes at most accel m/s^2, so it can't turn on a dime
	var v := Vector2(velocity.x, velocity.z).move_toward(Vector2(safe.x, safe.z), accel * get_physics_process_delta_time())
	velocity.x = v.x
	velocity.z = v.y
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * get_physics_process_delta_time()
	move_and_slide()
	if Vector2(velocity.x, velocity.z).length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), 0.25)


# --- stance machine (2D zombie.gd, in metres) ------------------------------------

func _free() -> void:
	if combat_stance == Combat.AGGRESSIVE:
		var e := _acquire_enemy()
		if e:
			target = e
			_chase(e)
		elif _search_t > 0.0:  # lost sight round a corner: run to where it was last seen
			target = null
			_agent.target_position = _seen_pos
			if _flat(global_position, _seen_pos) < 1.0:
				_search_t = 0.0  # got there, nothing in sight: give up
		elif _alert_timer > 0.0:
			target = null
			_agent.target_position = _alert_point
		else:
			target = _acquire_enemy(_attack_range())
			_agent.target_position = global_position
	else:  # HOLD: rooted, bites only within ~1 tile
		target = _acquire_enemy(m(B.STANCE.hold_attack_px))
		_agent.target_position = global_position


func _patrol() -> void:
	if combat_stance == Combat.AGGRESSIVE:
		var e := _acquire_enemy()
		if e:
			target = e
			_chase(e)
			return
		target = null
	else:
		target = _acquire_enemy(m(B.STANCE.hold_attack_px))
	var dest := patrol_a if _patrol_leg == 0 else patrol_b
	_agent.target_position = dest
	if StanceLogic.arrived(_flat(global_position, dest), 0.6):
		_patrol_leg = StanceLogic.flip_leg(_patrol_leg)


## Parked at a flee point: Aggressive engages enemies within the leash of the
## point, Hold only bites within 1 tile.
func _parked(point: Vector3) -> void:
	if combat_stance == Combat.AGGRESSIVE:
		var e := _acquire_enemy()
		if e and _flat(point, e.global_position) <= m(B.STANCE.leash_px):
			target = e
			_chase(e)
			return
		target = _acquire_enemy(_attack_range())
	else:
		target = _acquire_enemy(m(B.STANCE.hold_attack_px))
	_agent.target_position = point


func _flee_should_trigger() -> bool:
	match flee_trigger:
		FleeTrigger.ON_SIGHT:
			return _acquire_enemy() != null
		FleeTrigger.ON_DAMAGE:
			return _damaged_timer > 0.0
		FleeTrigger.IDLE:
			return _acquire_enemy() == null
	return false


func _attack_range() -> float:
	return m(B.STANCE.hold_attack_px) if combat_stance == Combat.HOLD else reach_m


## Nearest live shooter / NPC within radius (default: vision) that this zombie
## can see (bite range needs no sight line), or null.
func _acquire_enemy(radius := -1.0) -> Node3D:
	if radius < 0.0:
		radius = vision_m
	var nodes: Array = []
	var cands: Array = []
	for grp in ["shooter", "npcs"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D:
				var d := _flat(global_position, n.global_position)
				nodes.append(n)
				cands.append({pos = _xz(n.global_position), eligible = n.get("is_dead") != true \
						and d <= radius and (d <= 2.0 or can_see(n.global_position))})
	var i := Targeting.nearest_index(_xz(global_position), cands, radius)
	return nodes[i] if i >= 0 else null


func _seen_by_horde(pos: Vector3) -> bool:
	return seen_by_horde(get_tree(), pos)


## Sight: within vision_m and no building in the way (people, props and lamps
## don't block it). The commander's fog uses the same test to show enemies.
func can_see(pos: Vector3) -> bool:
	return _flat(global_position, pos) <= vision_m \
			and buildings_clear(get_world_3d().direct_space_state, global_position + EYE, pos + Vector3.UP)


static func seen_by_horde(tree: SceneTree, pos: Vector3) -> bool:
	for z in tree.get_nodes_in_group("zombies"):
		if not z.is_dead and z.visible and z.can_see(pos):
			return true
	return false


static func buildings_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var ex: Array[RID] = []
	for k in 4:
		var q := PhysicsRayQueryParameters3D.create(from, to, 1)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var p: Node = hit.collider.get_parent()
		if p and String(p.name).begins_with("Building"):
			return false
		ex.append(hit.rid)
	return true


## m/s: fast = the shooter's sprint + 1%, the rest from Balance.ZOMBIE_3D.
static func speed_for(v: int, sprint: float) -> float:
	if v == Variant.FAST:
		return sprint * B.ZOMBIE_3D.fast_vs_sprint
	return B.ZOMBIE_3D.speed_mps[NAMES[v]]


func _bite(delta: float) -> void:
	_cooldown -= delta
	if target == null or not is_instance_valid(target):
		return
	if CombatMath.can_attack(_flat(global_position, target.global_position), _attack_range(), _cooldown):
		if target.is_in_group("npcs") and target.has_method("force_convert"):
			target.force_convert()  # NPCs are never bitten to death, they turn
		elif target.has_method("take_damage"):
			target.take_damage(damage_per_hit)
		bit.emit(self, target, damage_per_hit)
		_cooldown = attack_interval
		_body.attack()


# --- orders -----------------------------------------------------------------------

func set_command(destination: Vector3) -> void:
	attack_target = null
	command_mode = true
	command_target = destination
	movement_mode = Movement.FREE  # a manual move cancels patrol / flee
	_fled = false


func set_attack_target(t: Node3D) -> void:
	attack_target = t
	command_mode = false


func set_combat(c: int) -> void:
	attack_target = null
	combat_stance = c
	command_mode = false
	_set_dot()


func set_movement(mode: int, trigger: int, p1: Vector3, p2: Vector3) -> void:
	attack_target = null
	movement_mode = mode
	command_mode = false
	_fled = false
	flee_trigger = trigger
	if mode == Movement.FLEE:
		flee_point = p1
	elif mode == Movement.PATROL:
		patrol_a = p1
		patrol_b = p2
		_patrol_leg = 0


## While merging: no stance, no avoidance, no zombie-vs-zombie collision, so
## the group can walk into each other and touch.
func set_merging(on: bool, dest := Vector3.ZERO) -> void:
	attack_target = null
	command_mode = false
	merging = on
	_merge_target = dest
	_agent.avoidance_enabled = not on
	set_collision_mask_value(2, not on)
	_agent.target_position = dest if on else global_position
	if not on:
		_body.pulse(-1.0)


## Lock-in pulse, 0..1.
func set_merge_progress(p: float) -> void:
	_body.pulse(p)


## Merge members hidden inside another can't be shot.
func set_hittable(on: bool) -> void:
	_body.set_hittable(on)


## Sound aggro: an Aggressive zombie within earshot heads for a gunshot.
func hear_gunshot(pos: Vector3) -> void:
	if combat_stance == Combat.AGGRESSIVE and _flat(pos, global_position) <= B.ZOMBIE_3D.hearing_m:
		_alert_point = pos
		_alert_timer = B.AGGRO.alert_seconds


func set_selected(on: bool) -> void:
	is_selected = on
	_ring.visible = on
	_dot.visible = on


## A weapon hit on one part (zombie_body.gd's hitboxes). No bleed: a limb hit
## never touches the body pool (spec D6).
func take_part_hit(part: String, damage: float) -> void:
	if is_dead or parts.get(part, 0.0) <= 0.0:
		return
	_damaged_timer = B.STANCE.damage_flee_window
	parts[part] -= damage
	hp = maxi(roundi(parts.body), 0)
	if parts[part] > 0.0:
		return
	_body.destroy(part)
	if part == "head" or part == "body":
		_die()
		return
	var lost := LIMBS.filter(func(l): return parts[l] <= 0.0)
	var fx := limb_effects(lost.count("leg_l") + lost.count("leg_r"), lost.count("arm_l") + lost.count("arm_r"))
	speed = _base_speed * fx.x
	_agent.max_speed = speed
	attack_interval = _base_interval * fx.y
	if lost.count("leg_l") + lost.count("leg_r") == 2 and not _body.crawling:
		_body.crawling = true  # both legs gone: down on the ground, hitbox with it
		_shape.height = 0.7
		for c in get_children():
			if c is CollisionShape3D:
				c.position.y = 0.35


## (speed multiplier, attack-interval multiplier) for lost legs / arms (spec D7, D8).
static func limb_effects(legs_lost: int, arms_lost: int) -> Vector2:
	var P: Dictionary = B.ZOMBIE_PARTS
	var sp: float = [1.0, P.hobble_speed, P.crawl_speed][clampi(legs_lost, 0, 2)]
	var iv: float = [1.0, P.one_arm_interval, P.no_arm_interval][clampi(arms_lost, 0, 2)]
	return Vector2(sp, iv)


## Untargeted damage (no part): the body pool.
func take_damage(amount: int) -> void:
	take_part_hit("body", amount)


func _die() -> void:
	is_dead = true
	hp = 0
	set_selected(false)
	remove_from_group("zombies")
	remove_from_group("noise_listeners")
	collision_layer = 0
	_agent.avoidance_enabled = false
	velocity = Vector3.ZERO
	_body.die()
	died.emit(self)
	get_tree().create_timer(B.ZOMBIE_PARTS.corpse_s).timeout.connect(queue_free)


# --- helpers ----------------------------------------------------------------------

func _set_dot() -> void:
	if _dot:
		_dot.material_override = _mat("dot%d" % combat_stance,
				Color(0.9, 0.15, 0.1) if combat_stance == Combat.AGGRESSIVE else Color(0.6, 0.6, 0.65), true)


func _mesh(mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _mat(key: String, c: Color, unshaded := false) -> StandardMaterial3D:
	if not _mats.has(key):
		var s := StandardMaterial3D.new()
		s.albedo_color = c
		s.roughness = 0.9
		if unshaded:
			s.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			s.no_depth_test = true
		_mats[key] = s
	return _mats[key]


## Rim glow drawn through walls (commander only), so a hidden zombie still reads.
static func _xray(c: Color) -> ShaderMaterial:
	var key := "xray" + c.to_html()
	if not _mats.has(key):
		if _xray_shader == null:
			_xray_shader = Shader.new()
			_xray_shader.code = """shader_type spatial;
render_mode unshaded, depth_test_disabled, shadows_disabled, cull_back;
uniform vec4 color : source_color;
void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a * pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
}"""
		var sm := ShaderMaterial.new()
		sm.shader = _xray_shader
		sm.set_shader_parameter("color", Color(c.lightened(0.5), 0.8))
		_mats[key] = sm
	return _mats[key]


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func _flat(a: Vector3, b: Vector3) -> float:
	return _xz(a).distance_to(_xz(b))
