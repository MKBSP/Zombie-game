extends Control

@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_label: Label = $HPLabel
@onready var compass_label: Label = $CompassLabel
@onready var debug_coords: Label = $DebugCoords
@onready var ammo_label: Label = $AmmoLabel
@onready var weapon_icon: TextureRect = $WeaponIcon
@onready var toast_label: Label = $ToastLabel

var shooter: Node2D = null
var master_zombie: Node2D = null
var debug_visible: bool = true
var _toast_tween: Tween = null

## Short messages shown when a pickup is collected, keyed by Pickup.Kind.
const PICKUP_MESSAGES := {
	Pickup.Kind.AMMO_MAG: "+ PISTOL MAG",
	Pickup.Kind.RIFLE: "PICKED UP RIFLE",
	Pickup.Kind.SHOTGUN: "PICKED UP SHOTGUN",
	Pickup.Kind.MEDPACK: "+50 HP",
	Pickup.Kind.BANDAGE: "+10 HP",
}
const PICKUP_COLORS := {
	Pickup.Kind.AMMO_MAG: Color(0.95, 0.85, 0.2),
	Pickup.Kind.RIFLE: Color(0.4, 0.6, 1.0),
	Pickup.Kind.SHOTGUN: Color(1.0, 0.5, 0.2),
	Pickup.Kind.MEDPACK: Color(0.9, 0.3, 0.4),
	Pickup.Kind.BANDAGE: Color(0.95, 0.95, 0.9),
}


func setup(p_shooter: Node2D, p_master_zombie: Node2D) -> void:
	shooter = p_shooter
	master_zombie = p_master_zombie
	# Connect to the shooter's hp_changed signal
	if shooter.has_signal("hp_changed"):
		shooter.hp_changed.connect(_on_hp_changed)
	if shooter.has_signal("pickup_collected"):
		shooter.pickup_collected.connect(_on_pickup_collected)
	if shooter.has_signal("headshot"):
		shooter.headshot.connect(_on_headshot)


func _process(_delta: float) -> void:
	if shooter == null:
		return

	# Update compass
	_update_compass()

	# Update ammo / weapon readout
	_update_ammo()

	# Update debug coordinates
	if debug_visible:
		debug_coords.text = "X: %d  Y: %d" % [int(shooter.global_position.x), int(shooter.global_position.y)]
	else:
		debug_coords.text = ""


func _unhandled_input(event: InputEvent) -> void:
	# Toggle debug info with F1
	if event.is_action_pressed("toggle_debug"):
		debug_visible = not debug_visible


## Pop a fading toast when the shooter collects a pickup.
func _on_pickup_collected(kind: int) -> void:
	if not PICKUP_MESSAGES.has(kind):
		return
	_pop_toast(PICKUP_MESSAGES[kind], PICKUP_COLORS.get(kind, Color.WHITE))


## Pop the crit toast for the player's own headshots.
func _on_headshot() -> void:
	_pop_toast("HEADSHOT!", Color(1.0, 0.85, 0.2))


## Show `text` on the toast label and fade it out.
func _pop_toast(text: String, color: Color) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.modulate = color
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	# Snap to fully visible, hold, then fade out.
	_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.1)
	_toast_tween.tween_interval(1.0)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


func _on_hp_changed(new_hp: int) -> void:
	hp_bar.value = new_hp
	hp_label.text = "HP %d" % new_hp


func _update_ammo() -> void:
	if ammo_label == null:
		return
	var w := Weapons.get_data(shooter.equipped)
	if weapon_icon:
		weapon_icon.texture = WeaponVisuals.texture(shooter.equipped)
	if w.is_melee:
		ammo_label.text = "Melee"
		return
	var mag: int
	var reserve: int
	if shooter.equipped == Weapons.PISTOL:
		mag = shooter.pistol_mag
		reserve = shooter.pistol_reserve
	else:
		mag = shooter.special_mag
		reserve = max(shooter.special_total - shooter.special_mag, 0)
	var txt := "%s  %d / %d" % [w.display_name, mag, reserve]
	if shooter.is_reloading:
		txt += "  (RELOADING)"
	ammo_label.text = txt


func _update_compass() -> void:
	if master_zombie == null or not is_instance_valid(master_zombie):
		compass_label.text = "Master Zombie: DEAD"
		return

	var dir := (master_zombie.global_position - shooter.global_position).normalized()
	var angle := dir.angle()

	# Convert angle to a compass arrow
	# 8 directions
	var arrows := ["→", "↘", "↓", "↙", "←", "↖", "↑", "↗"]
	# angle is in radians: 0 = right, PI/2 = down, etc.
	# Shift by half a segment (PI/8) so boundaries line up
	var index := int(round(angle / (PI / 4.0))) % 8
	if index < 0:
		index += 8

	compass_label.text = "Master Zombie: %s  (%dm)" % [arrows[index], int(shooter.global_position.distance_to(master_zombie.global_position) / 10)]
