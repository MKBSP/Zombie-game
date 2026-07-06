# Combat Juice Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add blood spurts, a permanent player bleed trail, wall/prop sparks, and per-shot muzzle flash with light to make combat feel impactful.

**Architecture:** All effects are server-authored and shown on every peer via `call_local` RPCs, mirroring the existing `world.rpc_noise_event` / `shooter._swing_fx` cosmetic patterns. One reusable `CPUParticles2D` burst scene covers red blood, green blood, and sparks; a baked world-sized `Image`→`ImageTexture` canvas holds the permanent bleed trail (same technique as `fog_zombie_controller.gd`). Every tunable number lives in a new `Balance.FX` dictionary.

**Tech Stack:** Godot 4.6.3, GL Compatibility renderer, GDScript. `CPUParticles2D` (not GPUParticles — Compatibility-renderer safety).

## Global Constraints

- **All game-file edits go through the godot-ai MCP** (`script_create`, `script_patch`, `node_create`, `scene_manage`, `filesystem_manage`) so the live editor stays in sync. Check `editor_state` first.
- **Never run headless `Godot --import` or `--script` while the editor is open** — run `test/` scripts only with the editor closed (see CLAUDE.md gotchas). Test files reference helpers via `load("res://...")`, not bare `class_name`.
- **Renderer is GL Compatibility** — use `CPUParticles2D`, never `GPUParticles2D`.
- **`scripts/balance.gd` is the single source of truth** for every tuning number. No magic numbers in scenes/scripts.
- **No commits, no `git push`** — Mads commits and pushes. End each task with verification + a CHANGELOG.md line only.
- **Verify** each task by owner playtest and/or `logs_read source=all` (zero `SCRIPT ERROR` = clean boot); pure-logic helpers run via their `test/` script with the editor closed.
- New effect scenes/scripts live under `scenes/fx/` and `scripts/`.

---

### Task 1: `Balance.FX` config + `FxPresets` particle-config helper

**Files:**
- Modify: `scripts/balance.gd` (append the `FX` const)
- Create: `scripts/fx_presets.gd`
- Test: `test/test_fx_presets.gd`

**Interfaces:**
- Produces: `Balance.FX` dict (see below); `FxPresets` with `enum {RED_BLOOD, GREEN_BLOOD, SPARKS}` and `static func config(preset: int) -> Dictionary` returning that preset's sub-dict from `Balance.FX.presets`.

- [ ] **Step 1: Add `Balance.FX` to `scripts/balance.gd`** (via MCP `script_patch`)

```gdscript
# --- Combat juice / effects (all cosmetic; no gameplay impact) --------------
const FX := {
	# One-shot hit bursts (CPUParticles2D). Colors are Color(r,g,b).
	presets = {
		"red_blood":   { color = Color(0.65, 0.02, 0.02), amount = 14, lifetime = 0.42, spread_deg = 55.0, vel_min = 60.0, vel_max = 180.0, scale_min = 2.0, scale_max = 4.0, gravity = 220.0 },
		"green_blood": { color = Color(0.20, 0.75, 0.10), amount = 14, lifetime = 0.42, spread_deg = 55.0, vel_min = 60.0, vel_max = 180.0, scale_min = 2.0, scale_max = 4.0, gravity = 220.0 },
		"sparks":      { color = Color(1.0, 0.85, 0.35),  amount = 10, lifetime = 0.20, spread_deg = 40.0, vel_min = 140.0, vel_max = 320.0, scale_min = 1.0, scale_max = 2.0, gravity = 40.0 },
	},
	# Muzzle flash: brief additive sprite + PointLight2D pulse at the gun tip.
	muzzle_flash_time = 0.06,        # seconds the flash + light stay up
	muzzle_light_energy = 1.6,       # player light pulse energy
	muzzle_light_range_px = 130.0,   # player light radius
	muzzle_npc_light_energy = 0.8,   # NPCs get a smaller pulse
	muzzle_flash_scale = 0.6,
	# Player bleed trail (baked, permanent).
	bleed_seconds = 6.0,             # bleeding window, refreshed on each hit
	bleed_drip_px = 26.0,            # emit one drop per this much travel
	bleed_drop_radius_px = 3.0,      # stamp radius on the canvas, world px
	bleed_color = Color(0.45, 0.02, 0.02, 0.85),
	canvas_downscale = 1,            # 1 = world-res canvas (crisp); raise to save memory
}
```

- [ ] **Step 2: Write the failing test** `test/test_fx_presets.gd`

```gdscript
extends SceneTree
# Run: Godot --headless --path . --script test/test_fx_presets.gd  (editor CLOSED)

func _init() -> void:
	var FxPresets = load("res://scripts/fx_presets.gd")
	var red: Dictionary = FxPresets.config(FxPresets.RED_BLOOD)
	assert(red.color == Color(0.65, 0.02, 0.02), "red_blood color mismatch")
	assert(red.amount == 14, "red_blood amount mismatch")
	var sparks: Dictionary = FxPresets.config(FxPresets.SPARKS)
	assert(sparks.lifetime == 0.20, "sparks lifetime mismatch")
	assert(sparks.vel_max == 320.0, "sparks vel_max mismatch")
	print("test_fx_presets OK")
	quit(0)
```

- [ ] **Step 3: Run the test to verify it fails**

Close the editor first. Run: `Godot --headless --path . --script test/test_fx_presets.gd`
Expected: FAIL — `res://scripts/fx_presets.gd` does not exist yet (load returns null / parse error).

- [ ] **Step 4: Create `scripts/fx_presets.gd`** (via MCP `script_create`)

```gdscript
extends RefCounted
class_name FxPresets

## Maps a preset id to its Balance.FX.presets sub-dict. Single lookup point so
## bullets, zombies, and the shooter all describe bursts the same way.

enum { RED_BLOOD, GREEN_BLOOD, SPARKS }

const _KEYS := {
	RED_BLOOD: "red_blood",
	GREEN_BLOOD: "green_blood",
	SPARKS: "sparks",
}

static func config(preset: int) -> Dictionary:
	return Balance.FX.presets[_KEYS[preset]]
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `Godot --headless --path . --script test/test_fx_presets.gd`
Expected: `test_fx_presets OK`, exit 0.

- [ ] **Step 6: Checkpoint (no commit)** — reopen the editor, confirm clean boot via `logs_read`. Add to CHANGELOG.md: `- Added Balance.FX tuning block + FxPresets helper for combat effects.`

---

### Task 2: `decal_math` — world→canvas coordinate mapping

**Files:**
- Create: `scripts/decal_math.gd`
- Test: `test/test_decal_math.gd`

**Interfaces:**
- Produces: `DecalMath.world_to_image(world_pos: Vector2, world_origin: Vector2, world_size_px: Vector2, img_size: Vector2i) -> Vector2i` — maps a world point to an integer pixel in a canvas image, clamped to image bounds.

- [ ] **Step 1: Write the failing test** `test/test_decal_math.gd`

```gdscript
extends SceneTree
# Run: Godot --headless --path . --script test/test_decal_math.gd  (editor CLOSED)

func _init() -> void:
	var DM = load("res://scripts/decal_math.gd")
	var origin := Vector2(0, 0)
	var world := Vector2(3008, 3008)
	var img := Vector2i(3008, 3008)
	assert(DM.world_to_image(Vector2(0, 0), origin, world, img) == Vector2i(0, 0), "top-left")
	assert(DM.world_to_image(Vector2(1504, 1504), origin, world, img) == Vector2i(1504, 1504), "center")
	# Off-map points clamp into bounds (never out of range).
	assert(DM.world_to_image(Vector2(9999, -50), origin, world, img) == Vector2i(3007, 0), "clamp")
	# Non-zero origin + half-res canvas.
	var half := Vector2i(1504, 1504)
	assert(DM.world_to_image(Vector2(1504, 0), Vector2(1504, 0), world, half) == Vector2i(0, 0), "origin offset")
	print("test_decal_math OK")
	quit(0)
```

- [ ] **Step 2: Run the test to verify it fails**

Run (editor closed): `Godot --headless --path . --script test/test_decal_math.gd`
Expected: FAIL — `scripts/decal_math.gd` missing.

- [ ] **Step 3: Create `scripts/decal_math.gd`** (via MCP `script_create`)

```gdscript
extends RefCounted
class_name DecalMath

## Pure mapping from world space to a canvas Image pixel. Kept separate from the
## canvas node so it can be unit-tested without a live tree.
static func world_to_image(world_pos: Vector2, world_origin: Vector2, world_size_px: Vector2, img_size: Vector2i) -> Vector2i:
	var fx := (world_pos.x - world_origin.x) / world_size_px.x
	var fy := (world_pos.y - world_origin.y) / world_size_px.y
	var px := int(fx * img_size.x)
	var py := int(fy * img_size.y)
	px = clampi(px, 0, img_size.x - 1)
	py = clampi(py, 0, img_size.y - 1)
	return Vector2i(px, py)
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot --headless --path . --script test/test_decal_math.gd`
Expected: `test_decal_math OK`, exit 0.

- [ ] **Step 5: Checkpoint (no commit)** — reopen editor, confirm clean boot. CHANGELOG.md: `- Added DecalMath world→canvas pixel mapping helper.`

---

### Task 3: Reusable hit-burst scene

**Files:**
- Create: `scenes/fx/hit_burst.gd`
- Create: `scenes/fx/hit_burst.tscn` (root `CPUParticles2D` named `HitBurst`, script attached)

**Interfaces:**
- Consumes: `FxPresets.config(preset)` (Task 1).
- Produces: `HitBurst` scene with `func play(preset: int, dir: Vector2) -> void` that configures the particles from the preset, aims them along `dir`, emits one burst, and frees itself when finished.

- [ ] **Step 1: Create `scenes/fx/hit_burst.gd`** (via MCP `script_create`)

```gdscript
extends CPUParticles2D

## One-shot particle burst reused for red blood, green blood, and sparks. The
## caller sets position, then calls play(preset, dir). Self-frees when done.

func _ready() -> void:
	emitting = false
	one_shot = true
	explosiveness = 1.0
	finished.connect(queue_free)

func play(preset: int, dir: Vector2) -> void:
	var c: Dictionary = FxPresets.config(preset)
	amount = c.amount
	lifetime = c.lifetime
	color = c.color
	spread = c.spread_deg
	initial_velocity_min = c.vel_min
	initial_velocity_max = c.vel_max
	scale_amount_min = c.scale_min
	scale_amount_max = c.scale_max
	gravity = Vector2(0, c.gravity)
	direction = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	restart()
	emitting = true
```

- [ ] **Step 2: Build `scenes/fx/hit_burst.tscn`** (via MCP `scene_manage` create + `node_create` + `script_attach`)

- Root node: `CPUParticles2D` named `HitBurst`.
- Attach `res://scenes/fx/hit_burst.gd`.
- Leave properties default (the script sets everything in `play`). Ensure `local_coords = false` so particles stay in world space as the burst node sits still.
- Save the scene.

- [ ] **Step 3: Verify it loads** — with the editor open, run `logs_read source=all` after opening `scenes/fx/hit_burst.tscn`; expect zero `SCRIPT ERROR`. Optionally instance it once at runtime via a scratch call and confirm particles appear.

- [ ] **Step 4: Checkpoint (no commit)** — CHANGELOG.md: `- Added reusable hit_burst CPUParticles2D scene (blood/sparks).`

---

### Task 4: World FX service — `Effects` node + spawn RPC

**Files:**
- Modify: `scenes/world/world.tscn` (add child `Effects` `Node2D` under `World`)
- Modify: `scenes/world/world.gd` (preload burst scene, add `spawn_hit_fx` + `rpc_spawn_hit_fx`, expose `FxPresets` enum passthrough)

**Interfaces:**
- Consumes: `HitBurst` scene (Task 3), `FxPresets` enum (Task 1).
- Produces: `world.spawn_hit_fx(preset: int, pos: Vector2, dir: Vector2) -> void` (server-only guard, RPCs to all peers). Callable from any server-side code via `get_tree().current_scene`.

- [ ] **Step 1: Add the `Effects` node** (via MCP `node_create`)

- Under `World` (`scenes/world/world.tscn`), add a `Node2D` named `Effects`. This holds ephemeral, per-peer, non-replicated bursts. Save the scene.

- [ ] **Step 2: Add the FX service to `world.gd`** (via MCP `script_patch`)

At the top with the other preloads:

```gdscript
const HIT_BURST_SCENE: PackedScene = preload("res://scenes/fx/hit_burst.tscn")
@onready var _effects: Node2D = $Effects
```

Near `emit_noise` / `rpc_noise_event`, add:

```gdscript
## Server entry point for a cosmetic hit burst; replicates to every peer.
func spawn_hit_fx(preset: int, pos: Vector2, dir: Vector2) -> void:
	if not multiplayer.is_server():
		return
	rpc_spawn_hit_fx.rpc(preset, pos, dir)

@rpc("authority", "call_local", "unreliable")
func rpc_spawn_hit_fx(preset: int, pos: Vector2, dir: Vector2) -> void:
	var burst := HIT_BURST_SCENE.instantiate()
	_effects.add_child(burst)
	burst.global_position = pos
	burst.play(preset, dir)
```

- [ ] **Step 3: Manual smoke test** — temporarily call `spawn_hit_fx(FxPresets.SPARKS, get_node("Entities").get_child(0).global_position, Vector2.UP)` once from `_ready()` on the server (or trigger via a debug key), run the game, confirm a spark burst appears on both host and client, then remove the temporary call.

- [ ] **Step 4: Verify** — `logs_read source=all`: zero `SCRIPT ERROR`; burst visible on both peers in a 2-window local MP run (`run_local_mp.command`).

- [ ] **Step 5: Checkpoint (no commit)** — CHANGELOG.md: `- Added world-level spawn_hit_fx service + Effects node (networked cosmetic bursts).`

---

### Task 5: Wire blood & spark triggers (bullet, zombie bite, shooter melee)

**Files:**
- Modify: `scenes/bullet/bullet.gd:_on_body_entered`
- Modify: `scenes/zombie/zombie.gd:_check_contact_damage`
- Modify: `scenes/shooter/shooter.gd:_swing`

**Interfaces:**
- Consumes: `world.spawn_hit_fx` (Task 4), `FxPresets` enum (Task 1).

All three run server-side already, so each is a single call into the current scene's FX service. Add this small helper reference pattern in each: `var w := get_tree().current_scene` then guard `if w.has_method("spawn_hit_fx")`.

- [ ] **Step 1: Green blood + sparks in `bullet.gd`** (via MCP `script_patch`)

In `_on_body_entered`, update the branches:

```gdscript
	var w := get_tree().current_scene
	if body.is_in_group("zombies"):
		var dmg := _damage_for_hit()
		if AimModel.is_headshot(origin, direction, body.global_position, Balance.HEADSHOT.radius_px):
			dmg *= Balance.HEADSHOT.mult
			if from_player and is_instance_valid(shooter_ref):
				shooter_ref.register_headshot()
		if body.has_method("take_damage"):
			body.take_damage(dmg)
		if w.has_method("spawn_hit_fx"):
			w.spawn_hit_fx(FxPresets.GREEN_BLOOD, global_position, direction)
		queue_free()
	elif body.is_in_group("npcs"):
		if body.has_method("take_damage"):
			body.take_damage(_damage_for_hit())
		if w.has_method("spawn_hit_fx"):
			w.spawn_hit_fx(FxPresets.RED_BLOOD, global_position, direction)
		queue_free()
	elif body is TileMapLayer:
		if w.has_method("spawn_hit_fx"):
			w.spawn_hit_fx(FxPresets.SPARKS, global_position, -direction)
		queue_free()
	elif body is StaticBody2D:
		if w.has_method("spawn_hit_fx"):
			w.spawn_hit_fx(FxPresets.SPARKS, global_position, -direction)
		queue_free()
```

(Note: NPCs shot by bullets bleed red — consistent with "humans bleed red". Zombies bleed green.)

- [ ] **Step 2: Red blood on a landed zombie bite in `zombie.gd`** (via MCP `script_patch`)

In `_check_contact_damage`, inside the `can_attack` branch, after `target.take_damage(...)`:

```gdscript
	if CombatMath.can_attack(distance, _attack_range(), _attack_cooldown):
		if target.has_method("take_damage"):
			target.take_damage(damage_per_hit)
			var w := get_tree().current_scene
			if w.has_method("spawn_hit_fx"):
				var dir := (target.global_position - global_position).normalized()
				w.spawn_hit_fx(FxPresets.RED_BLOOD, target.global_position, dir)
		_attack_cooldown = attack_interval
		_lunge_toward(target.global_position)
```

- [ ] **Step 3: Green blood on a landed melee swing in `shooter.gd`** (via MCP `script_patch`)

In `_swing`, inside the zombie-hit loop, after `z.take_damage(dmg)`:

```gdscript
			if Melee.forward_strike(global_position, facing, Balance.MELEE.range_px, Balance.MELEE.half_width_px, z.global_position):
				z.take_damage(dmg)
				hit = true
				var w := get_tree().current_scene
				if w.has_method("spawn_hit_fx"):
					w.spawn_hit_fx(FxPresets.GREEN_BLOOD, z.global_position, facing)
```

- [ ] **Step 4: Verify** — 2-window local MP playtest: shoot a zombie → green spray; shoot a wall/car → sparks; let a zombie bite the player and an NPC → red spray; melee a zombie → green spray. Effects appear on both windows. `logs_read`: zero `SCRIPT ERROR`.

- [ ] **Step 5: Checkpoint (no commit)** — CHANGELOG.md: `- Wired green blood (zombie hits), red blood (human bites/shots), and wall/prop sparks.`

---

### Task 6: Permanent player bleed trail (baked canvas)

**Files:**
- Create: `scripts/blood_canvas.gd`
- Modify: `scenes/world/world.tscn` (add `BloodCanvas` `Sprite2D` under `World`, z between ground and entities)
- Modify: `scenes/world/world.gd` (build canvas on ready; add `rpc_bleed_drop`)
- Modify: `scenes/shooter/shooter.gd` (bleeding state + server-side drip driver)

**Interfaces:**
- Consumes: `DecalMath.world_to_image` (Task 2), `Balance.FX` (Task 1).
- Produces: `world.rpc_bleed_drop(world_pos: Vector2)` (`@rpc authority call_local`); `BloodCanvas.stamp(world_pos: Vector2)`; shooter method `_maybe_drip()` called each server physics step.

- [ ] **Step 1: Create `scripts/blood_canvas.gd`** (via MCP `script_create`)

```gdscript
extends Sprite2D
class_name BloodCanvas

## One world-sized Image/ImageTexture that accumulates permanent blood drops.
## Same baked-texture technique as fog_zombie_controller. One draw call total.

var _image: Image
var _tex: ImageTexture
var _world_origin: Vector2
var _world_size_px: Vector2
var _img_size: Vector2i

## world_origin/world_size_px describe the ground bounds in world space.
func setup(world_origin: Vector2, world_size_px: Vector2) -> void:
	_world_origin = world_origin
	_world_size_px = world_size_px
	var ds: int = max(1, int(Balance.FX.canvas_downscale))
	_img_size = Vector2i(int(world_size_px.x) / ds, int(world_size_px.y) / ds)
	_image = Image.create(_img_size.x, _img_size.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_image)
	texture = _tex
	centered = false
	global_position = _world_origin
	# Stretch the (possibly downscaled) texture back over the full world.
	scale = Vector2(_world_size_px.x / _img_size.x, _world_size_px.y / _img_size.y)

func stamp(world_pos: Vector2) -> void:
	if _image == null:
		return
	var center := DecalMath.world_to_image(world_pos, _world_origin, _world_size_px, _img_size)
	var r := max(1, int(Balance.FX.bleed_drop_radius_px / max(1, int(Balance.FX.canvas_downscale))))
	var col: Color = Balance.FX.bleed_color
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var px := center.x + dx
			var py := center.y + dy
			if px < 0 or py < 0 or px >= _img_size.x or py >= _img_size.y:
				continue
			_image.set_pixel(px, py, col)
	_tex.update(_image)
```

- [ ] **Step 2: Add the `BloodCanvas` node** (via MCP `node_create` + `script_attach`)

- Under `World`, add a `Sprite2D` named `BloodCanvas`, attach `res://scripts/blood_canvas.gd`.
- Set `z_index` so it draws above `GroundLayer`/`BuildingLayer` but below `Entities` (e.g. `z_index = 0` on the canvas with entities at a higher z, or place `BloodCanvas` in the tree just after `BuildingLayer` and before `Entities` and leave default z). Confirm visually in Step 5. Save the scene.

- [ ] **Step 3: Initialize the canvas + add the drop RPC in `world.gd`** (via MCP `script_patch`)

Add `@onready var _blood_canvas: BloodCanvas = $BloodCanvas`. In `_ready()`, after the ground layer exists, compute bounds from `GroundLayer` and call setup:

```gdscript
	var gl: TileMapLayer = $GroundLayer
	var used: Rect2i = gl.get_used_rect()
	var ts: Vector2i = gl.tile_set.tile_size
	var origin: Vector2 = gl.to_global(gl.map_to_local(used.position)) - Vector2(ts) * 0.5
	var size_px := Vector2(used.size.x * ts.x, used.size.y * ts.y)
	_blood_canvas.setup(origin, size_px)
```

Add the RPC near the other cosmetic RPCs:

```gdscript
@rpc("authority", "call_local", "unreliable")
func rpc_bleed_drop(world_pos: Vector2) -> void:
	_blood_canvas.stamp(world_pos)
```

- [ ] **Step 4: Drive drips from the shooter (server) in `shooter.gd`** (via MCP `script_patch`)

Add state vars near the other `_` vars:

```gdscript
var _bleeding_until: float = 0.0
var _last_drip_pos: Vector2 = Vector2.ZERO
var _drip_inited: bool = false
```

In `take_damage`, after `hp = max(...)` (i.e. once a hit registers), start/refresh bleeding:

```gdscript
		_bleeding_until = (Time.get_ticks_msec() / 1000.0) + Balance.FX.bleed_seconds
```

Add the drip driver and call it from the server-authoritative movement in `_physics_process` (guard `if multiplayer.is_server(): _maybe_drip()` after the position/velocity update):

```gdscript
func _maybe_drip() -> void:
	if is_dead:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now >= _bleeding_until:
		return
	if not _drip_inited:
		_last_drip_pos = global_position
		_drip_inited = true
		return
	if global_position.distance_to(_last_drip_pos) >= Balance.FX.bleed_drip_px:
		_last_drip_pos = global_position
		var w := get_tree().current_scene
		if w.has_method("rpc_bleed_drop"):
			w.rpc_bleed_drop.rpc(global_position)
```

- [ ] **Step 5: Verify** — 2-window local MP: undamaged player leaves no trail; after a zombie bite, the player drips a red trail while running that persists (walk in a loop, confirm the old trail stays); trail is identical on both windows; stops dripping ~6 s after the last hit. `logs_read`: zero `SCRIPT ERROR`. Confirm the canvas draws under entities but over the ground.

- [ ] **Step 6: Checkpoint (no commit)** — CHANGELOG.md: `- Added permanent baked blood-trail canvas; wounded player drips a lasting trail.`

---

### Task 7: Muzzle flash + light on every shot

**Files:**
- Create: `scenes/fx/muzzle_flash.gd`
- Create: `scenes/fx/muzzle_flash.tscn` (root `Node2D` `MuzzleFlash` → `Sprite2D` flash + `PointLight2D`)
- Modify: `scenes/shooter/shooter.gd` (add `_muzzle_fx` RPC, call it in `shoot()`)
- Modify: `scenes/npc/npc_human.gd` (fire the same flash on NPC shots, smaller light)

**Interfaces:**
- Consumes: `Balance.FX` muzzle values (Task 1).
- Produces: `MuzzleFlash` scene with `func play(light_energy: float) -> void`; `shooter._muzzle_fx()` (`@rpc authority call_local`).

- [ ] **Step 1: Create `scenes/fx/muzzle_flash.gd`** (via MCP `script_create`)

```gdscript
extends Node2D

## Brief additive flash sprite + a short PointLight2D pulse at the gun tip.
## Instanced as a child of the gun tip; frees itself after muzzle_flash_time.

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _light: PointLight2D = $PointLight2D

func play(light_energy: float) -> void:
	_light.energy = light_energy
	_light.texture_scale = Balance.FX.muzzle_light_range_px / 128.0
	_sprite.scale = Vector2.ONE * Balance.FX.muzzle_flash_scale
	var t: float = Balance.FX.muzzle_flash_time
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_sprite, "modulate:a", 0.0, t)
	tw.tween_property(_light, "energy", 0.0, t)
	tw.chain().tween_callback(queue_free)
```

- [ ] **Step 2: Build `scenes/fx/muzzle_flash.tscn`** (via MCP `scene_manage` / `node_create` / `material_manage`)

- Root `Node2D` named `MuzzleFlash`, attach `res://scenes/fx/muzzle_flash.gd`.
- Child `Sprite2D`: use an existing small bright sprite (e.g. reuse a soft radial — generate a small white radial via `ShooterLighting.make_radial_texture`-style, or assign any small flash PNG under `sprites/`). Set a `CanvasItemMaterial` with `blend_mode = BLEND_MODE_ADD`, tint `modulate = Color(1, 0.9, 0.5)`. Offset slightly forward (+X).
- Child `PointLight2D`: assign a soft radial texture (reuse the radial-texture approach from `shooter_lighting.gd`), `color = Color(1, 0.85, 0.5)`, `energy = 0` initially (set in `play`).
- Save the scene.

- [ ] **Step 3: Add `_muzzle_fx` to `shooter.gd` and call it in `shoot()`** (via MCP `script_patch`)

Add the preload near the top: `const MUZZLE_FLASH_SCENE: PackedScene = preload("res://scenes/fx/muzzle_flash.tscn")`

In `shoot()`, after `Weapons.fire(...)`:

```gdscript
	_muzzle_fx.rpc()
```

Add the RPC (modeled on `_swing_fx`):

```gdscript
@rpc("authority", "call_local", "unreliable")
func _muzzle_fx() -> void:
	var flash := MUZZLE_FLASH_SCENE.instantiate()
	gun_tip.add_child(flash)
	flash.play(Balance.FX.muzzle_light_energy)
```

- [ ] **Step 4: Add the same flash to NPC shots in `npc_human.gd`** (via MCP `script_patch`)

Find the NPC fire path (near the recoil kick around `npc_human.gd:320`, where `Weapons.fire` is called). Add a preload `const MUZZLE_FLASH_SCENE := preload("res://scenes/fx/muzzle_flash.tscn")` and, right after the NPC fires, an `@rpc("authority","call_local","unreliable")` `_muzzle_fx()` that instances the flash at the NPC's gun/weapon-sprite muzzle with `Balance.FX.muzzle_npc_light_energy`, then call `_muzzle_fx.rpc()`. Mirror the shooter code exactly, substituting the NPC's muzzle marker (use `$WeaponSprite` position if no dedicated tip exists).

- [ ] **Step 5: Verify** — 2-window local MP: every player shot pops a muzzle flash + a brief light halo around the shooter (visible in the dark fog); NPC shots flash too (smaller light); flashes appear on both windows; no lingering lights (each frees). `logs_read`: zero `SCRIPT ERROR`.

- [ ] **Step 6: Checkpoint (no commit)** — CHANGELOG.md: `- Added per-shot muzzle flash + light pulse for the player and armed NPCs.`

---

## Self-Review

**Spec coverage:**
- Red blood on zombie bite (player + NPC) → Task 5 Step 2 (bite) + Task 5 Step 1 (NPC shot). ✓
- Permanent player bleed trail → Task 6. ✓
- Green blood when shooter hits zombie (bullet + melee) → Task 5 Steps 1 & 3. ✓
- Sparks on wall/prop bullet hits → Task 5 Step 1. ✓
- Muzzle flash + light around shooter → Task 7. ✓
- Balance-driven tuning, networked via call_local, CPUParticles, tests for pure logic → Tasks 1–2, 4. ✓

**Placeholder scan:** Task 7 Steps 2 & 4 describe scene-node/asset wiring in prose rather than a code block — acceptable because they are editor/scene construction steps (no algorithmic code), and the exact texture source (`shooter_lighting.gd` radial approach) and material settings are named. All script steps carry full code.

**Type consistency:** `spawn_hit_fx(preset, pos, dir)`, `rpc_spawn_hit_fx`, `FxPresets.config`/`FxPresets.RED_BLOOD|GREEN_BLOOD|SPARKS`, `DecalMath.world_to_image`, `BloodCanvas.setup`/`stamp`, `rpc_bleed_drop`, `MuzzleFlash.play`, `_muzzle_fx` — names are consistent across all tasks that produce and consume them.

**Networking note:** all triggers run server-side (bullet sim, zombie/shooter physics, `shoot`) and replicate via `call_local` RPCs — no new synced state, matching the existing `rpc_noise_event` pattern.
