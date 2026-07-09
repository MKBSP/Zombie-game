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
var _ammo_blocks: AmmoBlocks = null


func _ready() -> void:
	_apply_zc_style()

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
	debug_visible = get_node("/root/Settings").get_value("show_debug_coords")
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
	if not get_node("/root/Settings").get_value("show_pickup_toasts"):
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
	hp_label.text = str(new_hp)
	# HP color rule (>60% green / 30-60% warn / <30% crit) on bar + number.
	var c := UIStyle.hp_color(new_hp / float(hp_bar.max_value))
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(0)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_label.add_theme_color_override("font_color", c)


func _update_ammo() -> void:
	if ammo_label == null:
		return
	var w := Weapons.get_data(shooter.equipped)
	if weapon_icon:
		weapon_icon.texture = WeaponVisuals.texture(shooter.equipped)
	if w.is_melee:
		ammo_label.text = "MELEE"
		if _ammo_blocks:
			_ammo_blocks.set_state(0, 0)
		return
	var mag: int
	var reserve: int
	if shooter.equipped == Weapons.PISTOL:
		mag = shooter.pistol_mag
		reserve = shooter.pistol_reserve
	else:
		mag = shooter.special_mag
		reserve = max(shooter.special_total - shooter.special_mag, 0)
	var txt := "%s  %d / %d" % [w.display_name.to_upper(), mag, reserve]
	if shooter.is_reloading:
		txt += "  [RELOADING]"
	ammo_label.text = txt
	if _ammo_blocks:
		_ammo_blocks.set_state(mag, w.mag_size)


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

	compass_label.text = "MASTER ZOMBIE %s  %dm" % [arrows[index], int(shooter.global_position.distance_to(master_zombie.global_position) / 10)]


# ------------------------------------------------------- ZOMBIE COMMAND styling
# Visual-only (mockup screen 11): the scattered top-left labels become a bottom
# HUD bar — HEALTH (segmented bar + number) | WEAPON (icon, readout, ammo
# blocks) | THREAT (compass). Existing nodes are reparented in place, so all
# @onready refs and update logic above keep working untouched.

func _apply_zc_style() -> void:
	var bar := PanelContainer.new()
	bar.name = "BottomBar"
	var bar_sb := UIStyle.box(UIStyle.fade(UIStyle.BAR_BG, 0.88), Color.TRANSPARENT)
	bar_sb.border_color = UIStyle.BORDER
	bar_sb.border_width_top = 1
	bar.add_theme_stylebox_override("panel", bar_sb)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -68.0

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	bar.add_child(row)

	# — HEALTH —
	var hp_section := _bar_section(row, "HEALTH", 250)
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_theme_constant_override("separation", 10)
	hp_section.add_child(hp_row)
	hp_bar.reparent(hp_row)
	hp_bar.custom_minimum_size = Vector2(150, 12)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_label.reparent(hp_row)
	hp_label.add_theme_font_override("font", UIStyle.mono_spaced())
	hp_label.add_theme_font_size_override("font_size", 22)
	_on_hp_changed(int(hp_bar.value))

	row.add_child(_bar_divider())

	# — WEAPON —
	var wpn_section := _bar_section(row, "WEAPON", 300)
	var wpn_row := HBoxContainer.new()
	wpn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_row.add_theme_constant_override("separation", 10)
	wpn_section.add_child(wpn_row)
	weapon_icon.reparent(wpn_row)
	weapon_icon.custom_minimum_size = Vector2(44, 26)
	weapon_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wpn_col := VBoxContainer.new()
	wpn_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_col.add_theme_constant_override("separation", 3)
	wpn_row.add_child(wpn_col)
	ammo_label.reparent(wpn_col)
	ammo_label.add_theme_font_override("font", UIStyle.mono_spaced())
	ammo_label.add_theme_font_size_override("font_size", 13)
	ammo_label.add_theme_color_override("font_color", UIStyle.INFECTION)
	_ammo_blocks = AmmoBlocks.new()
	_ammo_blocks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wpn_col.add_child(_ammo_blocks)

	row.add_child(_bar_divider())

	# — THREAT (master-zombie compass) —
	var threat_section := _bar_section(row, "THREAT", 240)
	compass_label.reparent(threat_section)
	compass_label.custom_minimum_size = Vector2(0, 0)
	compass_label.add_theme_font_override("font", UIStyle.mono_spaced())
	compass_label.add_theme_font_size_override("font_size", 13)
	compass_label.add_theme_color_override("font_color", UIStyle.ASH)

	# Toast + debug coords restyle (stay where they are).
	toast_label.add_theme_font_override("font", UIStyle.mono_spaced())
	toast_label.offset_top = -170.0
	toast_label.offset_bottom = -140.0
	debug_coords.theme_type_variation = "MicroLabel"


## A titled section (micro header + content VBox) inside the bottom bar.
func _bar_section(row: HBoxContainer, title: String, min_width: float) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.custom_minimum_size = Vector2(min_width, 0)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	row.add_child(margin)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	var head := Label.new()
	head.text = title
	head.theme_type_variation = "MicroLabel"
	v.add_child(head)
	return v


func _bar_divider() -> Control:
	var line := ColorRect.new()
	line.color = UIStyle.BORDER
	line.custom_minimum_size = Vector2(1, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Mag visualized as a row of blocks (mockup's signature ammo readout).
class AmmoBlocks:
	extends Control

	const BLOCK_W := 7.0
	const BLOCK_H := 12.0
	const GAP := 2.0

	var _ammo := 0
	var _max := 0

	func set_state(ammo: int, max_ammo: int) -> void:
		if ammo == _ammo and max_ammo == _max:
			return
		_ammo = ammo
		_max = max_ammo
		custom_minimum_size = Vector2(_max * (BLOCK_W + GAP), BLOCK_H)
		queue_redraw()

	func _draw() -> void:
		for i in _max:
			var r := Rect2(Vector2(i * (BLOCK_W + GAP), 0), Vector2(BLOCK_W, BLOCK_H))
			if i < _ammo:
				draw_rect(r, UIStyle.fade(UIStyle.INFECTION, 0.85))
			else:
				draw_rect(r, UIStyle.BUNKER)
				draw_rect(r, UIStyle.BORDER_DIM, false, 1.0)
