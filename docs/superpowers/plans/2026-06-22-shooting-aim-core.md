# Shooting Phase 1 — Player Aiming Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the player's perfect aim with a skill-based system — a visible cone cursor whose size reflects accuracy, weapon-specific spread, debuffs (running/injured/recoil), a hold-Ctrl focus buff, and range→damage falloff.

**Architecture:** A pure-math module (`AimModel`) is the single source of truth for spread and damage falloff, used by the server (firing + damage) and the client (cursor). The server computes a single synced float `aim_spread_coeff`; the client draws the cursor from it. Firing randomisation and damage falloff are server-authoritative; the cursor is a local readout for the human player only.

**Tech Stack:** Godot 4 / GDScript, WebSocket multiplayer (dedicated server + clients), MultiplayerSynchronizer/Spawner.

**Spec:** `docs/superpowers/specs/2026-06-21-shooting-aim-core-design.md`

**Conventions for this plan:**
- Godot binary: `"/Applications/Godot 2.app/Contents/MacOS/Godot"` (call it `$GODOT`).
- **Compile-check command** (used as the "test" for scene/gameplay tasks — expects NO matching lines):
  ```bash
  "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
    | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
  ```
- **Commits are LOCAL ONLY. Never `git push`.** The user pushes to GitHub themselves.
- After adding any new `class_name` script, run the compile-check once before headless `--script` runs so the global class cache registers it (see Task 2).

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `scripts/aim_model.gd` | Pure spread + damage-falloff math (`AimModel`) | Create |
| `test/test_aim_model.gd` | Headless unit test for `AimModel` | Create |
| `scripts/weapon_data.gd` | Add aiming/range fields | Modify |
| `scripts/weapons.gd` | Per-weapon numbers; `fire()` → disk model | Modify |
| `scenes/bullet/bullet.gd` | Origin + range→damage falloff, max-range despawn | Modify |
| `scenes/shooter/shooter.gd` | Input (cursor pos + Ctrl), server aim state, synced coeff, disk firing | Modify |
| `scenes/shooter/shooter.tscn` | Sync `aim_spread_coeff` | Modify |
| `scenes/ui/aim_cursor.gd` + `.tscn` | Client cursor drawing | Create |
| `scenes/world/world.tscn` | Add `AimCursor` under `HUDLayer` | Modify |
| `scenes/world/world.gd` | Wire cursor for the human role | Modify |
| `scenes/ui/pause_menu.gd`, `scenes/ui/game_over.gd` | Restore OS cursor in menus | Modify |
| `project.godot` | `focus_aim` input action | Modify |

---

## Task 1: Weapon data fields + per-weapon numbers

**Files:**
- Modify: `scripts/weapon_data.gd`
- Modify: `scripts/weapons.gd`

- [ ] **Step 1: Add aiming fields to WeaponData**

In `scripts/weapon_data.gd`, after the existing `@export var total_ammo` line, add:

```gdscript
	# --- Aiming (Phase 1) ---
	## Circle radius as a fraction of the gun->cursor distance at 0% debuff / no focus.
@export var aim_base: float = 0.10
	## Circle radius fraction at 100% debuff.
@export var aim_max: float = 0.30
	## Full focus shrinks the circle to aim_base * focus_min_scale. 1.0 = no focus (shotgun).
@export var focus_min_scale: float = 1.0
	## Damage is full within optimal_range_px and falls linearly to 0 at zero_range_px.
@export var optimal_range_px: float = 640.0
@export var zero_range_px: float = 800.0
```
(Match the file's existing indentation — these are class-level `@export`s at column 0.)

- [ ] **Step 2: Set per-weapon numbers in Weapons.get_data**

In `scripts/weapons.gd`, inside `get_data()`'s `match` block, add the fields to each branch:

RIFLE branch (after `w.total_ammo = 10`):
```gdscript
			w.aim_base = 0.03
			w.aim_max = 0.25
			w.focus_min_scale = 0.50
			w.optimal_range_px = 1024.0   # 16 tiles
			w.zero_range_px = 1184.0      # +2.5 tiles
```
SHOTGUN branch (after `w.total_ammo = 8`):
```gdscript
			w.aim_base = 0.22
			w.aim_max = 0.45
			w.focus_min_scale = 1.0       # no focus benefit
			w.optimal_range_px = 320.0    # 5 tiles
			w.zero_range_px = 480.0       # +2.5 tiles
```
PISTOL branch (after `w.total_ammo = 0`):
```gdscript
			w.aim_base = 0.10
			w.aim_max = 0.30
			w.focus_min_scale = 0.75
			w.optimal_range_px = 640.0    # 10 tiles
			w.zero_range_px = 800.0       # +2.5 tiles
```

- [ ] **Step 3: Compile-check**

Run the compile-check command. Expected: no output (clean).

- [ ] **Step 4: Commit (local only)**

```bash
git add scripts/weapon_data.gd scripts/weapons.gd
git commit -m "feat(aim): weapon aiming + range fields and per-weapon values"
```

---

## Task 2: AimModel pure-math module + headless unit test

**Files:**
- Create: `scripts/aim_model.gd`
- Create: `test/test_aim_model.gd`

- [ ] **Step 1: Write the failing test**

Create `test/test_aim_model.gd`:

```gdscript
extends SceneTree

## Headless unit test for AimModel. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd

var _failures := 0


func _init() -> void:
	var pistol := Weapons.get_data(Weapons.PISTOL)
	_eq("base", AimModel.spread_coeff(pistol, 0.0, 0.0), pistol.aim_base)
	_eq("max", AimModel.spread_coeff(pistol, 1.0, 0.0), pistol.aim_max)
	_eq("half", AimModel.spread_coeff(pistol, 0.5, 0.0),
		pistol.aim_base + 0.5 * (pistol.aim_max - pistol.aim_base))
	_eq("debuff clamps at 1.0", AimModel.spread_coeff(pistol, 2.0, 0.0), pistol.aim_max)
	_eq("focus floor", AimModel.spread_coeff(pistol, 0.0, 1.0),
		pistol.aim_base * pistol.focus_min_scale)
	_eq("within optimal", AimModel.damage_mult(pistol, pistol.optimal_range_px - 1.0), 1.0)
	_eq("at zero range", AimModel.damage_mult(pistol, pistol.zero_range_px), 0.0)
	_eq("range midpoint", AimModel.damage_mult(pistol,
		(pistol.optimal_range_px + pistol.zero_range_px) / 2.0), 0.5)
	var ok := true
	for _i in range(1000):
		if AimModel.random_in_disk(50.0).length() > 50.0001:
			ok = false
			break
	_check("random_in_disk within radius", ok)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _eq(label: String, got: float, want: float) -> void:
	if absf(got - want) > 0.0001:
		_failures += 1
		print("FAIL %s: got %f want %f" % [label, got, want])
	else:
		print("PASS %s" % label)


func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -20
```
Expected: FAIL — `AimModel` not found / parser error (the class doesn't exist yet).

- [ ] **Step 3: Write the AimModel implementation**

Create `scripts/aim_model.gd`:

```gdscript
extends RefCounted
class_name AimModel

## Pure aiming math — the single source of truth for spread and damage falloff.
## Stateless; called by the server (firing + damage) and the client (cursor).

const TILE := 64.0


## Circle radius as a fraction of the gun->cursor distance.
## debuff_total: additive running + injured + recoil (>= 0). focus_fraction: 0..1.
static func spread_coeff(w: WeaponData, debuff_total: float, focus_fraction: float) -> float:
	var d := clampf(debuff_total, 0.0, 1.0)
	var coeff := w.aim_base + d * (w.aim_max - w.aim_base)
	coeff *= lerpf(1.0, w.focus_min_scale, clampf(focus_fraction, 0.0, 1.0))
	return coeff


## Damage multiplier: 1.0 within optimal_range_px, linear down to 0 at zero_range_px.
static func damage_mult(w: WeaponData, dist_px: float) -> float:
	if dist_px <= w.optimal_range_px:
		return 1.0
	var span := w.zero_range_px - w.optimal_range_px
	if span <= 0.0:
		return 0.0
	return clampf(1.0 - (dist_px - w.optimal_range_px) / span, 0.0, 1.0)


## Uniform random point within a disk of the given radius (px).
static func random_in_disk(radius: float) -> Vector2:
	var r := radius * sqrt(randf())
	var a := randf() * TAU
	return Vector2(cos(a), sin(a)) * r
```

- [ ] **Step 4: Register the new class_name, then run the test**

New `class_name` scripts aren't in the global cache until the project reimports. Run the compile-check once (it imports), then run the test:

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . >/dev/null 2>&1
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -20
```
Expected: every line `PASS ...`, final line `ALL TESTS PASSED`, exit code 0.

- [ ] **Step 5: Commit (local only)**

```bash
git add scripts/aim_model.gd test/test_aim_model.gd
git commit -m "feat(aim): AimModel spread/falloff math + headless unit test"
```

---

## Task 3: `focus_aim` input action

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Add the action**

Easiest in-editor: Project → Project Settings → Input Map → add action **`focus_aim`**, bind the **Ctrl** key.

Or hand-edit `project.godot`: under the `[input]` section add:

```
focus_aim={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194326,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```
(`4194326` = `KEY_CTRL`.)

- [ ] **Step 2: Compile-check**

Run the compile-check command. Expected: no output.

- [ ] **Step 3: Commit (local only)**

```bash
git add project.godot
git commit -m "feat(aim): add focus_aim (Ctrl) input action"
```

---

## Task 4: Bullet range → damage falloff (backward-compatible)

**Files:**
- Modify: `scenes/bullet/bullet.gd`

Defaults keep existing callers unaffected: with `weapon == null` the bullet does full `damage` and never max-range-despawns.

- [ ] **Step 1: Add fields and falloff to bullet.gd**

Replace the top of `scenes/bullet/bullet.gd` (the vars + `_ready` + `_physics_process`) with:

```gdscript
extends Area2D

@export var speed: float = 600.0
@export var damage: float = 35.0
@export var lifetime: float = 1.8

var direction: Vector2 = Vector2.ZERO
## Range falloff, set by Weapons.fire(). origin = muzzle position.
var origin: Vector2 = Vector2.ZERO
var optimal_range_px: float = 0.0
var zero_range_px: float = 0.0
## Weapon backing the falloff curve. null = no falloff (full damage).
var weapon: WeaponData = null

func _ready() -> void:
	# Simulation (movement, collisions, despawn) is server-only; clients just
	# render the synced position. Server queue_free despawns replicas too.
	set_physics_process(multiplayer.is_server())
	if origin == Vector2.ZERO:
		origin = global_position
	if multiplayer.is_server():
		var timer := get_tree().create_timer(lifetime)
		timer.timeout.connect(queue_free)
		body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	# Despawn at max range so out-of-range shots don't keep flying.
	if zero_range_px > 0.0 and origin.distance_to(global_position) >= zero_range_px:
		queue_free()

## Damage to apply on hit, scaled by range falloff when a weapon is set.
func _damage_for_hit() -> float:
	if weapon == null:
		return damage
	return damage * AimModel.damage_mult(weapon, origin.distance_to(global_position))
```

- [ ] **Step 2: Use scaled damage on hit**

In `_on_body_entered`, replace BOTH `take_damage(damage)` calls (the zombie branch and the npc branch) with:

```gdscript
			body.take_damage(_damage_for_hit())
```
(Keep the surrounding `if body.has_method("take_damage"):` and `queue_free()` lines unchanged.)

- [ ] **Step 3: Compile-check**

Run the compile-check command. Expected: no output.

- [ ] **Step 4: Commit (local only)**

```bash
git add scenes/bullet/bullet.gd
git commit -m "feat(aim): bullet range->damage falloff + max-range despawn"
```

---

## Task 5: Shooter input — cursor position + Ctrl (no behavior change yet)

**Files:**
- Modify: `scenes/shooter/shooter.gd`

Switches the input from a bare aim angle to the cursor world-position, and adds the focus flag. Firing still uses the current path, so behavior is identical this task.

- [ ] **Step 1: Replace the aim state vars**

In `scenes/shooter/shooter.gd`, replace:
```gdscript
var _net_aim: float = 0.0
var _net_shooting: bool = false
```
with:
```gdscript
var _net_aim_target: Vector2 = Vector2.ZERO
var _net_shooting: bool = false
var _net_focus: bool = false
```

- [ ] **Step 2: Send cursor position + focus in `_process`**

Replace the block that computes `aim`/`shooting` and calls `_send_input` with:
```gdscript
		var aim_target: Vector2 = get_global_mouse_position()
		var shooting: bool = (
			Input.is_action_pressed("ui_accept")
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		)
		var focus: bool = Input.is_action_pressed("focus_aim")
		_send_input.rpc_id(1, input_dir, aim_target, shooting, focus)
```

- [ ] **Step 3: Update the `_send_input` RPC**

Replace the whole `_send_input` function with:
```gdscript
@rpc("any_peer", "call_local", "unreliable_ordered")
func _send_input(dir: Vector2, aim_target: Vector2, shooting: bool, focus: bool) -> void:
	if not multiplayer.is_server():
		return
	_net_dir = dir.limit_length(1.0)
	_net_aim_target = aim_target
	_net_shooting = shooting
	_net_focus = focus
```

- [ ] **Step 4: Derive rotation from the cursor in `_physics_process`**

Replace `rotation = _net_aim` with:
```gdscript
	if _net_aim_target != global_position:
		rotation = (_net_aim_target - global_position).angle()
```

- [ ] **Step 5: Compile-check + manual sanity**

Run the compile-check (expect no output). Then in the editor, play single-player: movement, aiming (player faces the mouse), and shooting all work exactly as before.

- [ ] **Step 6: Commit (local only)**

```bash
git add scenes/shooter/shooter.gd
git commit -m "refactor(aim): shooter input carries cursor position + focus flag"
```

---

## Task 6: Disk-model firing (spread + falloff active)

**Files:**
- Modify: `scripts/weapons.gd`
- Modify: `scenes/shooter/shooter.gd`
- Modify: `scenes/npc/npc_human.gd`

All three call sites change together so the build stays green. After this task, shots scatter by `aim_base` (no debuffs yet) and damage falls off with range.

- [ ] **Step 1: Rework `Weapons.fire()` to the disk model**

In `scripts/weapons.gd`, replace the entire `fire()` function with:
```gdscript
## Spawn this weapon's pellets from `origin`, each flying straight toward a
## uniform-random point inside the aim circle of radius `radius_px` centred on
## `cursor_pos`. Parented under `parent` (Entities) so the spawner replicates them.
static func fire(parent: Node, origin: Vector2, cursor_pos: Vector2, radius_px: float, w: WeaponData) -> void:
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
		parent.add_child(bullet, true)
```

- [ ] **Step 2: Update the shooter's `shoot()` call**

In `scenes/shooter/shooter.gd` `shoot()`, replace:
```gdscript
	Weapons.fire(parent, gun_tip.global_position, global_rotation, w, 0.0)
```
with:
```gdscript
	var cursor := _net_aim_target
	var dist := gun_tip.global_position.distance_to(cursor)
	var radius := w.aim_base * dist   # debuffs/focus added in Task 7
	Weapons.fire(parent, gun_tip.global_position, cursor, radius, w)
```

- [ ] **Step 3: Update the NPC's fire call**

In `scenes/npc/npc_human.gd` `_process_shooting()`, replace:
```gdscript
	Weapons.fire(get_parent(), origin, base_angle, w, NPC_AIM_JITTER)
```
with:
```gdscript
	var cursor: Vector2 = target.global_position
	var radius: float = NPC_AIM_JITTER * origin.distance_to(cursor)
	Weapons.fire(get_parent(), origin, cursor, radius, w)
```
(`base_angle` is still used just above for the muzzle offset — leave that line.)

- [ ] **Step 4: Compile-check + manual**

Run the compile-check (expect no output). Play single-player: pistol shots now scatter slightly even standing still; walk far from a zombie and confirm damage drops to nothing past ~12 tiles (pistol). Shotgun still spreads its pellets.

- [ ] **Step 5: Commit (local only)**

```bash
git add scripts/weapons.gd scenes/shooter/shooter.gd scenes/npc/npc_human.gd
git commit -m "feat(aim): disk-model firing with per-weapon spread + range falloff"
```

---

## Task 7: Shooter aim state — debuffs, recoil, focus, synced coeff

**Files:**
- Modify: `scenes/shooter/shooter.gd`
- Modify: `scenes/shooter/shooter.tscn`

- [ ] **Step 1: Add aim-state vars**

In `scenes/shooter/shooter.gd`, add near the other state vars:
```gdscript
# --- Aim accuracy (server computes; aim_spread_coeff is synced for the cursor) ---
var aim_spread_coeff: float = 0.10
var _recoil: float = 0.0
var _recoil_recover: float = 0.0   # seconds for the current kick to fully decay
var _recoil_elapsed: float = 0.0
var _focus_timer: float = 0.0
const FOCUS_TIME := 5.0
const PISTOL_DMG_REF := 35.0
```

- [ ] **Step 2: Update timers + coeff every server frame**

In `_physics_process`, immediately after `rotation = ...` (the block from Task 5, Step 4) and BEFORE `if _net_shooting: shoot()`, add:
```gdscript
	_update_recoil(_delta)
	_update_focus(_delta)
	aim_spread_coeff = AimModel.spread_coeff(_active_weapon(), _debuff_total(), _focus_fraction())
```
(Change the signature `func _physics_process(_delta: float)` to `func _physics_process(delta: float)` and use `delta` in those three calls, OR keep `_delta` and pass `_delta` — just be consistent. The code below assumes `delta`.)

- [ ] **Step 3: Add the helper functions**

Add these functions to `scenes/shooter/shooter.gd`:
```gdscript
func _debuff_total() -> float:
	var total := 0.0
	if _net_dir.length() > 0.1:
		total += 0.20                       # running
	if hp < int(max_hp * 0.5):
		total += 0.40                       # badly hurt
	elif hp < max_hp:
		total += 0.20                       # injured
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
	_recoil = 0.5 * clampf(1.0 - _recoil_elapsed / _recoil_recover, 0.0, 1.0)
```

- [ ] **Step 4: Apply recoil on each shot and use the live coeff**

In `shoot()`, change the firing block (from Task 6, Step 2) to use the synced coeff, and add the recoil kick right after firing:
```gdscript
	var cursor := _net_aim_target
	var dist := gun_tip.global_position.distance_to(cursor)
	var radius := aim_spread_coeff * dist
	Weapons.fire(parent, gun_tip.global_position, cursor, radius, w)

	# Post-shot recoil: refresh to 50%, recover over 2 x damage-units seconds.
	var dmg_units := (w.damage * w.pellets) / PISTOL_DMG_REF
	_recoil = 0.5
	_recoil_elapsed = 0.0
	_recoil_recover = 2.0 * dmg_units
```

- [ ] **Step 5: Sync `aim_spread_coeff`**

In `scenes/shooter/shooter.tscn`, in the `[sub_resource type="SceneReplicationConfig" id="SceneReplicationConfig_sync"]` block, append a new property (use the next index after the existing `properties/11`):
```
properties/12/path = NodePath(".:aim_spread_coeff")
properties/12/spawn = true
properties/12/replication_mode = 1
```
(`replication_mode = 1` = replicate every frame, like position — the cursor needs it live.)

- [ ] **Step 6: Compile-check + manual**

Run the compile-check (expect no output). Play single-player and confirm by watching where bullets land (cursor comes in Task 8, so judge by impact spread for now):
- Standing still → tight; running → noticeably wider.
- Spamming pistol → stays wide; pausing ~2s → tightens again.
- Take damage below 50% hp → wider.
- Hold Ctrl while still ~5s → tightens below the standing-still baseline (pistol/rifle); shotgun unchanged.

- [ ] **Step 7: Commit (local only)**

```bash
git add scenes/shooter/shooter.gd scenes/shooter/shooter.tscn
git commit -m "feat(aim): server aim state - running/injured/recoil debuffs + focus, synced coeff"
```

---

## Task 8: The aim cursor (client visual)

**Files:**
- Create: `scenes/ui/aim_cursor.gd`
- Create: `scenes/ui/aim_cursor.tscn`
- Modify: `scenes/world/world.tscn`
- Modify: `scenes/world/world.gd`
- Modify: `scenes/ui/pause_menu.gd`
- Modify: `scenes/ui/game_over.gd`

- [ ] **Step 1: Create the cursor script**

Create `scenes/ui/aim_cursor.gd`:
```gdscript
extends Control

## Client-side aim cursor for the human player. Draws a circle at the mouse whose
## radius = shooter.aim_spread_coeff * (gun->cursor distance), with opacity from
## the equipped weapon's range falloff. Green while the focus buff is shrinking it.
## Hides the OS cursor while active.

var _shooter: Node2D = null


func setup(shooter: Node2D) -> void:
	_shooter = shooter
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	set_process(true)


func teardown() -> void:
	_shooter = null
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(false)


func is_active() -> bool:
	return _shooter != null and is_instance_valid(_shooter)


func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _process(_delta: float) -> void:
	if is_active():
		queue_redraw()


func _draw() -> void:
	if not is_active():
		return
	var gun: Vector2 = _shooter.global_position
	var tip := _shooter.get_node_or_null("GunTip")
	if tip:
		gun = tip.global_position
	var mouse := get_global_mouse_position()
	var dist := gun.distance_to(mouse)
	var coeff: float = _shooter.aim_spread_coeff
	var radius: float = maxf(coeff * dist, 2.0)

	var w := Weapons.get_data(_shooter.equipped)
	var opacity: float = clampf(AimModel.damage_mult(w, dist), 0.15, 1.0)

	# White normally; green when focus has shrunk the circle below aim_base.
	var col := Color(1, 1, 1, opacity)
	if coeff < w.aim_base - 0.0001:
		col = Color(0.3, 1.0, 0.3, opacity)

	var center := get_local_mouse_position()
	draw_arc(center, radius, 0.0, TAU, 48, col, 2.0)
	draw_circle(center, 2.0, col)
```

- [ ] **Step 2: Create the cursor scene**

Create `scenes/ui/aim_cursor.tscn`:
```
[gd_scene load_steps=2 format=3 uid="uid://caimcursor0001"]

[ext_resource type="Script" path="res://scenes/ui/aim_cursor.gd" id="1_ac"]

[node name="AimCursor" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("1_ac")
```
(`mouse_filter = 2` = ignore, so it never eats clicks. Godot will reassign the `uid` on first import — see Step 4.)

- [ ] **Step 3: Add the node + wire it in world**

In `scenes/world/world.tscn`, add an ext_resource near the others (pick an unused id):
```
[ext_resource type="PackedScene" uid="uid://caimcursor0001" path="res://scenes/ui/aim_cursor.tscn" id="21_aimcursor"]
```
and add the node under `HUDLayer` (after the `PauseMenu` node block):
```
[node name="AimCursor" parent="HUDLayer" instance=ExtResource("21_aimcursor")]
visible = false
```

In `scenes/world/world.gd`, add the reference near the other `@onready` HUD refs:
```gdscript
@onready var aim_cursor: Control = $HUDLayer/AimCursor
```
and in `_apply_role()`, set the cursor for each role:
```gdscript
	if GameState.role == GameState.Role.HUMAN:
		...existing human setup...
		aim_cursor.setup(shooter)
	else:
		...existing zombie setup...
		aim_cursor.teardown()
```

- [ ] **Step 4: Reconcile the scene uid**

Run the compile-check once so Godot imports `aim_cursor.tscn` and assigns its real uid:
```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . >/dev/null 2>&1
head -1 scenes/ui/aim_cursor.tscn
grep -n "aim_cursor" scenes/world/world.tscn
```
If the `uid://` printed by `head` differs from the one referenced in `world.tscn`, update the `world.tscn` ext_resource line to the real uid (path fallback usually works, but keep them consistent).

- [ ] **Step 5: Restore the OS cursor in menus**

In `scenes/ui/pause_menu.gd`, in `_open()` add as the first line of the body:
```gdscript
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
```
and in `_close()` add, after setting `visible = false`:
```gdscript
	var ac := get_parent().get_node_or_null("AimCursor")
	if ac and ac.has_method("is_active") and ac.is_active():
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
```

In `scenes/ui/game_over.gd`, in `show_message()` add (the match is over, so just reveal the OS cursor):
```gdscript
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
```

- [ ] **Step 6: Compile-check + manual**

Run the compile-check (expect no output). Play single-player:
- A circle is drawn at the mouse; the OS pointer is hidden.
- Moving the mouse further from the player grows the circle (cone); closer shrinks it.
- Running / shooting grows it; it settles when you stop.
- Holding Ctrl while still shrinks it and turns it green (pistol/rifle).
- Aiming past optimal range fades the circle.
- Open the Esc menu → OS pointer returns and you can click Resume/Quit; resume re-hides it. Game over → OS pointer returns.

- [ ] **Step 7: Commit (local only)**

```bash
git add scenes/ui/aim_cursor.gd scenes/ui/aim_cursor.tscn scenes/world/world.tscn scenes/world/world.gd scenes/ui/pause_menu.gd scenes/ui/game_over.gd
git commit -m "feat(aim): client aim cursor with cone radius, range fade, focus tint"
```

---

## Task 9: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Unit test + compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -3
```
Expected: no grep output; `ALL TESTS PASSED`.

- [ ] **Step 2: Single-player feel pass**

Play and confirm against the spec: running +debuff, injured tiers, recoil refresh+recovery, focus floors (pistol 0.75 / rifle 0.50 / shotgun none), range fade + damage drop, shotgun spread.

- [ ] **Step 3: Multiplayer pass**

Run `./run_local_mp.command` (host + join). As the human, confirm the cursor draws and shots land within the circle; verify on the other window that bullets/positions replicate and damage drops with range. Confirm the **zombie role has no cursor** and the OS pointer is normal.

- [ ] **Step 4: Regression pass**

Reload/ammo/swap/drop/give-to-NPC still work; NPCs still fire-at-will when you fire; pause + game-over flows from the previous feature still work and the OS cursor is correct in each.

- [ ] **Step 5: Final commit (local only, if any tweaks were made)**

```bash
git add -A
git commit -m "test(aim): Phase 1 verification tweaks"
```

---

## Self-Review notes (author)

- **Spec coverage:** cone spread (T6), debuffs running/injured/recoil (T7), focus buff + per-weapon floors (T7), range→damage falloff (T4/T6), cursor radius+opacity+green tint (T8), synced coeff + server-authoritative firing (T6/T7), input action (T3), weapon numbers (T1), AimModel single source of truth (T2). All covered.
- **Non-breakage:** `Weapons.fire()` signature changes in T6 with all three call sites updated in the same task; bullet falloff (T4) is backward-compatible until callers set `weapon`.
- **Type consistency:** `aim_spread_coeff` (shooter var + synced), `spread_coeff()/damage_mult()/random_in_disk()` (AimModel), `fire(parent, origin, cursor_pos, radius_px, w)` used identically in shooter and NPC.
- **Deferred:** NPC keeps approximate disk radius from `NPC_AIM_JITTER` (full integration = Phase 3); cursor assumes camera zoom 1.0.
