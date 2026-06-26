extends CharacterBody2D

# --- Tunable values (from Balance.SHOOTER, assigned in _ready) ---
var speed: float
var max_hp: int
var contact_damage_per_second: float

# --- State ---
## Setter keeps the HUD updated on clients, where the value arrives via
## the MultiplayerSynchronizer instead of take_damage().
var hp: int:
	set(value):
		hp = value
		hp_changed.emit(hp)
## Set to false when this window's player isn't controlling the shooter.
var controls_enabled: bool = true
var can_shoot: bool = true
var is_dead: bool = false
var _damage_accumulator: float = 0.0

# --- Weapon / ammo state (server-authoritative, synced for the HUD) ---
## Currently drawn weapon: Weapons.PISTOL, or held_special when it's out.
var equipped: int = Weapons.PISTOL
## The heavy slot: Weapons.RIFLE / SHOTGUN / MACHINEGUN, or -1 when empty.
var held_special: int = -1
## The melee slot: Weapons.MELEE when held, or -1 (empty).
var held_melee: int = -1
var _melee_next_swing: float = 0.0
var _melee_hits: Array[float] = []
var _melee_fatigued: bool = false
var pistol_mag: int = 15
var pistol_reserve: int = 15      # one spare mag at start (15 + 15 = 2 mags)
## For the held special: special_mag is chambered, special_total is all rounds
## still on the weapon (chambered + reserve).
var special_mag: int = 0
var special_total: int = 0
var is_reloading: bool = false

# --- Pickup feedback (server sets these; they sync so the controlling client's
# HUD can pop a toast). last_pickup_kind is the Pickup.Kind; pickup_seq bumps on
# every collection so the setter fires even when the same kind repeats. ---
var last_pickup_kind: int = -1
var pickup_seq: int = 0:
	set(value):
		pickup_seq = value
		pickup_collected.emit(last_pickup_kind)

## Bumped server-side on each player headshot; the controlling client's HUD
## reads the change and pops a "HEADSHOT!" toast (mirrors pickup_seq).
var headshot_seq: int = 0:
	set(value):
		headshot_seq = value
		headshot.emit()

# --- Latest input from the controlling player (consumed server-side) ---
var _net_dir: Vector2 = Vector2.ZERO
var _net_aim_target: Vector2 = Vector2.ZERO
var _net_shooting: bool = false
var _net_focus: bool = false

# --- Aim accuracy (server computes; aim_spread_coeff is synced for the cursor) ---
var aim_spread_coeff: float = 0.05
var _recoil: float = 0.0
var _recoil_recover: float = 0.0   # seconds for the current kick to fully decay
var _recoil_elapsed: float = 0.0
var _focus_timer: float = 0.0
# From Balance.SHOOTER (assigned in _ready). Growing the aim circle is instant;
# shrinking eases toward the target over AIM_SHRINK_TAU (~1s settle).
var FOCUS_TIME: float
var AIM_SHRINK_TAU: float
var PISTOL_DMG_REF: float

# --- Node references (filled in _ready) ---
@onready var gun_tip: Marker2D = $GunTip
@onready var shoot_cooldown: Timer = $ShootCooldown
@onready var reload_timer: Timer = $ReloadTimer

# --- Signals ---
signal hp_changed(new_hp: int)
signal player_died
## Fired on the controlling client when a pickup is collected (kind = Pickup.Kind).
signal pickup_collected(kind: int)
## Fired on the controlling client when one of the player's shots lands a headshot.
signal headshot


func _ready() -> void:
	speed = Balance.SHOOTER.speed
	max_hp = Balance.SHOOTER.max_hp
	contact_damage_per_second = Balance.SHOOTER.contact_dps
	FOCUS_TIME = Balance.SHOOTER.focus_time
	AIM_SHRINK_TAU = Balance.SHOOTER.aim_shrink_tau
	PISTOL_DMG_REF = Balance.SHOOTER.pistol_dmg_ref
	hp = max_hp
	# Simulation runs on the server only (true in single player too)
	set_physics_process(multiplayer.is_server())
	shoot_cooldown.timeout.connect(_on_shoot_cooldown_timeout)
	reload_timer.timeout.connect(_on_reload_timeout)


## Input capture — runs on whichever peer controls the shooter and forwards
## the input to the server. With call_local, solo and host-as-human use the
## exact same path.
func _process(_delta: float) -> void:
	if not controls_enabled or is_dead:
		return
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
	var aim_target: Vector2 = get_global_mouse_position()
	var shooting: bool = (
		Input.is_action_pressed("ui_accept")
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	)
	var focus: bool = Input.is_action_pressed("focus_aim")
	_send_input.rpc_id(1, input_dir, aim_target, shooting, focus)

	# Discrete one-shot weapon actions
	if Input.is_action_just_pressed("select_pistol"):
		_action_select.rpc_id(1, 0)
	if Input.is_action_just_pressed("select_heavy"):
		_action_select.rpc_id(1, 1)
	if Input.is_action_just_pressed("select_melee"):
		_action_select.rpc_id(1, 2)
	if Input.is_action_just_pressed("drop_weapon"):
		_action_drop.rpc_id(1)
	if Input.is_action_just_pressed("give_weapon_to_npc"):
		_action_give.rpc_id(1)


@rpc("any_peer", "call_local", "unreliable_ordered")
func _send_input(dir: Vector2, aim_target: Vector2, shooting: bool, focus: bool) -> void:
	if not multiplayer.is_server():
		return
	_net_dir = dir.limit_length(1.0)
	_net_aim_target = aim_target
	_net_shooting = shooting
	_net_focus = focus


@rpc("any_peer", "call_local", "reliable")
func _action_select(slot: int) -> void:
	if multiplayer.is_server():
		_select_slot(slot)


@rpc("any_peer", "call_local", "reliable")
func _action_drop() -> void:
	if multiplayer.is_server():
		_drop_equipped()


@rpc("any_peer", "call_local", "reliable")
func _action_give() -> void:
	if multiplayer.is_server():
		_give_weapon_to_npc()


## Server-side simulation.
func _physics_process(delta: float) -> void:
	if is_dead:
		return

	velocity = _net_dir * speed
	move_and_slide()
	if _net_aim_target != global_position:
		rotation = (_net_aim_target - global_position).angle()

	_update_recoil(delta)
	_update_focus(delta)
	var target_coeff := AimModel.spread_coeff(_active_weapon(), _debuff_total(), _focus_fraction())
	if target_coeff >= aim_spread_coeff:
		aim_spread_coeff = target_coeff                 # grow instantly
	else:
		# Shrink gradually: exponential ease, ~96% closed within 1s.
		aim_spread_coeff = target_coeff + (aim_spread_coeff - target_coeff) * exp(-delta / AIM_SHRINK_TAU)

	if _net_shooting:
		if _active_weapon().is_melee:
			_swing()
		else:
			shoot()


func _debuff_total() -> float:
	var total := 0.0
	if _net_dir.length() > 0.1:
		total += Balance.SHOOTER.debuff_running
	if hp < int(max_hp * Balance.SHOOTER.injured_hp_frac):
		total += Balance.SHOOTER.debuff_hurt
	elif hp < max_hp:
		total += Balance.SHOOTER.debuff_injured
	total += _recoil
	return total

func _focus_fraction() -> float:
	return clampf(_focus_timer / FOCUS_TIME, 0.0, 1.0)

func _update_focus(delta: float) -> void:
	# Focus only builds while holding Ctrl AND standing still.
	if _net_focus and _net_dir.length() <= 0.1:
		_focus_timer = minf(_focus_timer + delta, FOCUS_TIME)
	else:
		_focus_timer = 0.0

func _update_recoil(delta: float) -> void:
	if _recoil <= 0.0:
		return
	_recoil_elapsed += delta
	if _recoil_recover <= 0.0:
		_recoil = 0.0
		return
	_recoil = Balance.SHOOTER.recoil_initial * clampf(1.0 - _recoil_elapsed / _recoil_recover, 0.0, 1.0)


## True while the player is holding fire — armed NPCs only shoot when this is.
func is_firing() -> bool:
	return _net_shooting and not is_dead


func _active_weapon() -> WeaponData:
	return Weapons.get_data(equipped)


func _current_mag() -> int:
	return pistol_mag if equipped == Weapons.PISTOL else special_mag


func shoot() -> void:
	if not can_shoot or is_dead or is_reloading:
		return

	var w := _active_weapon()
	if _current_mag() <= 0:
		_try_reload(w)
		return

	can_shoot = false
	shoot_cooldown.start(maxf(w.cooldown, 0.05))

	if equipped == Weapons.PISTOL:
		pistol_mag -= 1
	else:
		special_mag -= 1
		special_total -= 1

	# Spawn under Entities so the MultiplayerSpawner replicates the bullets.
	var parent: Node = get_tree().current_scene.get_node_or_null("Entities")
	if parent == null:
		parent = get_tree().current_scene
	var cursor := _net_aim_target
	var dist := gun_tip.global_position.distance_to(cursor)
	var radius := aim_spread_coeff * dist
	Weapons.fire(parent, gun_tip.global_position, cursor, radius, w, self)

	# Post-shot recoil: refresh to the initial kick, recover over
	# recoil_recover_factor x damage-units seconds.
	var dmg_units := (w.damage * w.pellets) / PISTOL_DMG_REF
	_recoil = Balance.SHOOTER.recoil_initial
	_recoil_elapsed = 0.0
	_recoil_recover = Balance.SHOOTER.recoil_recover_factor * dmg_units

	# Auto-reload the moment the mag runs dry.
	if _current_mag() <= 0:
		_try_reload(w)


func _try_reload(w: WeaponData) -> void:
	if is_reloading:
		return
	var reserve: int = pistol_reserve if equipped == Weapons.PISTOL else (special_total - special_mag)
	if reserve <= 0:
		return  # nothing left to load
	is_reloading = true
	reload_timer.start(w.reload_time)


func _on_reload_timeout() -> void:
	var w := _active_weapon()
	if equipped == Weapons.PISTOL:
		var load_count: int = min(w.mag_size - pistol_mag, pistol_reserve)
		pistol_mag += load_count
		pistol_reserve -= load_count
	else:
		# special_total already counts the chambered rounds, so the reserve is
		# total minus what's in the mag.
		var reserve: int = special_total - special_mag
		var load_count: int = min(w.mag_size - special_mag, reserve)
		special_mag += load_count
	is_reloading = false


func _on_shoot_cooldown_timeout() -> void:
	can_shoot = true


func _swing() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	# Clear fatigue after a long enough idle (no landed hit for fatigue_recover s).
	if not _melee_hits.is_empty() and now - _melee_hits.back() > Balance.MELEE.fatigue_recover:
		_melee_hits.clear()
		_melee_fatigued = false
	if now < _melee_next_swing:
		return
	_melee_next_swing = now + Balance.MELEE.cooldown
	_swing_fx.rpc()

	var facing := Vector2.from_angle(global_rotation)
	var dmg: float = Balance.MELEE.damage * (Balance.MELEE.fatigue_mult if _melee_fatigued else 1.0)
	var hit := false
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D and is_instance_valid(z) and z.has_method("take_damage"):
			if Melee.forward_strike(global_position, facing, Balance.MELEE.range_px, Balance.MELEE.half_width_px, z.global_position):
				z.take_damage(dmg)
				hit = true
	if hit:
		_melee_hits.append(now)
		while not _melee_hits.is_empty() and now - _melee_hits[0] > Balance.MELEE.fatigue_recover:
			_melee_hits.pop_front()
		if Melee.recent_hit_count(_melee_hits, now, Balance.MELEE.fatigue_window) >= Balance.MELEE.fatigue_hits:
			_melee_fatigued = true


## Brief swing flash on every peer (placeholder until weapon visuals, Phase 5).
@rpc("authority", "call_local", "unreliable")
func _swing_fx() -> void:
	var spr := get_node_or_null("Sprite2D")
	if spr == null:
		return
	spr.modulate = Color(1.5, 1.5, 1.5)
	get_tree().create_timer(0.1).timeout.connect(func():
		if is_instance_valid(spr):
			spr.modulate = Color.WHITE)


func _drop_equipped() -> void:
	if _active_weapon().is_melee:
		if held_melee == -1:
			return
		held_melee = -1
		equipped = Weapons.PISTOL
		_cancel_reload()
	else:
		_drop_special()


# --- Weapon switching / handoff (server-side) ---

## Equip slot 0=pistol, 1=heavy, 2=melee. Empty slots are a no-op.
func _select_slot(slot: int) -> void:
	var target := -1
	match slot:
		0: target = Weapons.PISTOL
		1: target = held_special
		2: target = held_melee
	if target == -1 or target == equipped:
		return
	_cancel_reload()
	equipped = target


func _drop_special() -> void:
	if held_special == -1:
		return
	held_special = -1
	special_mag = 0
	special_total = 0
	equipped = Weapons.PISTOL
	_cancel_reload()


func _give_weapon_to_npc() -> void:
	if held_special == -1:
		return
	var npc := _find_following_npc()
	if npc == null:
		return
	npc.receive_weapon(held_special, special_total)
	_drop_special()


func _cancel_reload() -> void:
	is_reloading = false
	reload_timer.stop()
	can_shoot = true


## Find the NPC currently following the shooter (State.FOLLOWING == 2).
func _find_following_npc() -> Node:
	for n in get_tree().get_nodes_in_group("npcs"):
		if "state" in n and n.state == 2:
			return n
	return null


# --- Pickup effects (called server-side by pickup.gd) ---

func add_pistol_mag() -> void:
	pistol_reserve += Weapons.get_data(Weapons.PISTOL).mag_size
	_notify_pickup(Pickup.Kind.AMMO_MAG)


func give_special(weapon_id: int) -> void:
	var w := Weapons.get_data(weapon_id)
	held_special = weapon_id
	special_total = w.total_ammo
	special_mag = min(w.mag_size, special_total)
	equipped = weapon_id
	_cancel_reload()
	var kind := Pickup.Kind.RIFLE
	if weapon_id == Weapons.SHOTGUN:
		kind = Pickup.Kind.SHOTGUN
	elif weapon_id == Weapons.MACHINEGUN:
		kind = Pickup.Kind.MACHINEGUN
	_notify_pickup(kind)


func heal(amount: int) -> void:
	hp = min(hp + amount, max_hp)  # setter emits hp_changed
	_notify_pickup(Pickup.Kind.MEDPACK)


## Server-side: record the pickup and bump the synced sequence so the
## controlling client's HUD fires pickup_collected.
func _notify_pickup(kind: int) -> void:
	last_pickup_kind = kind
	pickup_seq += 1


## Server-side: record a headshot so the controlling client toasts it.
func register_headshot() -> void:
	headshot_seq += 1


func take_damage(amount: float) -> void:
	if is_dead:
		return
	_damage_accumulator += amount
	var whole_damage := int(_damage_accumulator)
	if whole_damage >= 1:
		_damage_accumulator -= whole_damage
		hp = max(hp - whole_damage, 0)  # setter emits hp_changed
		if hp <= 0:
			die()


func die() -> void:
	is_dead = true
	player_died.emit()
	# Don't queue_free — we want the body to stay so the game over screen shows
