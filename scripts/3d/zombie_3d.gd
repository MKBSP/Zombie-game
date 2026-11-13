extends CharacterBody3D
## 3D zombie unit (Phase 10 slice for the commander): a placeholder capsule per
## variant, run by the 2D stance machine ported from scenes/zombie/zombie.gd —
## same Balance numbers, pixels converted at Balance.FP.px_per_m. Orders come
## from scripts/3d/commander.gd. First-person weapon hits land in take_hit()
## (one HP pool for now; per-part HP is S5). Commander-only markers (selection
## ring, stance dot, rim silhouette through walls) sit on render layer
## COMMANDER_LAYER, which the first-person camera never draws.

const B := preload("res://scripts/balance.gd")

enum Variant { STANDARD, FAST, FAT, MASTER }
enum Combat { AGGRESSIVE, HOLD }
enum Movement { FREE, FLEE, PATROL }
enum FleeTrigger { ON_SIGHT, ON_DAMAGE, IDLE }

const COMMANDER_LAYER := 4  # render layer 3
const STATS := [B.ZOMBIE, B.FAST, B.FAT, B.MASTER]
## Placeholder capsule [radius, height] + colour per variant, until the models land.
const BODY := [[0.3, 1.75], [0.27, 1.65], [0.5, 1.9], [0.42, 2.2]]
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
var _agent: NavigationAgent3D
var _body: MeshInstance3D
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
	speed = m(s.speed)
	max_hp = s.max_hp
	hp = max_hp
	vision_m = m(s.vision * 64.0)  # 2D vision is in 64 px tiles
	reach_m = m(s.contact_px)
	damage_per_hit = s.damage_per_hit
	attack_interval = s.attack_interval
	collision_layer = 2       # zombies
	collision_mask = 1 | 2    # world + other zombies (no walking through each other)
	var r: float = BODY[variant][0]
	var h: float = BODY[variant][1]
	var shape := CapsuleShape3D.new()
	shape.radius = r
	shape.height = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = h / 2
	add_child(cs)

	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = h
	_body = _mesh(cap, Vector3(0, h / 2, 0), _mat("body%d" % variant, TINT[variant]))
	_mesh(_box(Vector3(r * 0.9, 0.12, 0.12)), Vector3(0, h * 0.82, -r * 0.9), _mat("face", Color(0.08, 0.06, 0.05)))
	var xr := _mesh(cap, Vector3(0, h / 2, 0), _xray(TINT[variant]))
	xr.layers = COMMANDER_LAYER
	xr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	_damaged_timer -= delta
	_alert_timer -= delta
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
			_agent.target_position = attack_target.global_position
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


func _on_velocity_computed(safe: Vector3) -> void:
	velocity.x = safe.x
	velocity.z = safe.z
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
			_agent.target_position = e.global_position
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
			_agent.target_position = e.global_position
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
			_agent.target_position = e.global_position
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


## Nearest live shooter / NPC within radius (default: vision), or null.
func _acquire_enemy(radius := -1.0) -> Node3D:
	var nodes: Array = []
	var cands: Array = []
	for grp in ["shooter", "npcs"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node3D:
				nodes.append(n)
				cands.append({pos = _xz(n.global_position), eligible = n.get("is_dead") != true})
	var i := Targeting.nearest_index(_xz(global_position), cands, vision_m if radius < 0.0 else radius)
	return nodes[i] if i >= 0 else null


func _seen_by_horde(pos: Vector3) -> bool:
	var watchers: Array = []
	for z in get_tree().get_nodes_in_group("zombies"):
		watchers.append({pos = _xz(z.global_position), vision_px = z.vision_m})
	return Targeting.visible_to_any(_xz(pos), watchers)


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
		var tw := create_tween()  # lunge
		tw.tween_property(_body, "position:z", -0.25, 0.06)
		tw.tween_property(_body, "position:z", 0.0, 0.1)


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
		_body.scale = Vector3.ONE


## Lock-in pulse, 0..1.
func set_merge_progress(p: float) -> void:
	var s := 1.0 + 0.12 * absf(sin(p * 30.0))
	_body.scale = Vector3(s, 1.0, s)


## Sound aggro: an Aggressive zombie within earshot heads for a gunshot.
func hear_gunshot(pos: Vector3) -> void:
	if combat_stance == Combat.AGGRESSIVE and _flat(pos, global_position) <= m(B.AGGRO.alert_radius_px):
		_alert_point = pos
		_alert_timer = B.AGGRO.alert_seconds


func set_selected(on: bool) -> void:
	is_selected = on
	_ring.visible = on
	_dot.visible = on


## First-person weapon hit (scripts/3d/viewmodel.gd).
func take_hit(damage: float, _pos: Vector3, _dir: Vector3) -> void:
	take_damage(roundi(damage))


func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp -= amount
	_damaged_timer = B.STANCE.damage_flee_window
	if hp <= 0:
		is_dead = true
		died.emit(self)
		queue_free()


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
