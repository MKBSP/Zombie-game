# Ambient Lighting & Life Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking. Spec this implements:
> `docs/superpowers/specs/2026-07-29-ambient-lighting-and-life-design.md`.

**Goal:** Lightposts, a burning dumpster, three critter types, and grass that
interacts with light and characters — plus one new mechanic: the zombie-commander
player can sense the shooter's flashlight through their own fog, with a risk/reward
tradeoff for the shooter (a whole-cone full reveal if a zombie is caught in the beam).

**Architecture:** Everything is additive on top of three existing systems:
`ShooterLighting`/`ZombieLighting` (`Light2D`-based fog visuals, built per-client
based on `GameState.role`, never both on one client), `FogZombieController` (the
zombie role's persistent tile-grid exploration memory, `scripts/fog_zombie_controller.gd`),
and `world.gd`'s noise system (`emit_noise`/`noise_event`). Lightposts and the burning
dumpster reuse the *existing* per-zombie-vision reveal path (`_reveal_diamond`) as
permanent pseudo-vision sources — zero new engine code needed for that part. The
flashlight-glow feature needs one genuinely new piece: a cone-shaped reveal
(`_reveal_cone`), kept transient (never written to persistent `tile_states`), plus a
real local `Light2D` on the zombie's client whose energy switches between a dim
"ambient glow" and a full "risk" brightness based on a simple distance+angle+LOS check.

**Tech Stack:** GDScript, Godot `Light2D`/`PointLight2D`/`LightOccluder2D`, existing
`shader/fog_zc.gdshader` (unchanged), no new external dependencies, no new binary
image assets (everything ships as placeholder shapes).

## Global Constraints
- All game-file edits go through the godot-ai MCP tools (`script_patch`, `script_create`,
  `node_create`, `scene_manage`, etc.) — never raw filesystem writes to tracked game files.
- All new tunable numbers live in `scripts/balance.gd`, in a new `Balance.AMBIENT_LIFE`
  dict (Task 1), following the project's existing per-system-dict convention.
- Verify each task in the **live editor** (`project_run` + `logs_read`) — never a
  headless `Godot --import`/`--script` run while the editor is open (risks corrupting
  `.godot/`). Pure-logic pieces get `test/` scripts, run only with the editor closed,
  following the exact pattern in `test/test_fog_los.gd` (`extends SceneTree`,
  `load("res://...")`, manual `push_error`/`quit(0|1)`).
- Don't commit unless asked; update `CHANGELOG.md` at the end (Task 13) per CLAUDE.md.

---

### Task 1: Balance constants for ambient life

**Files:**
- Modify: `scripts/balance.gd` (insert a new section after `const FOG_ZC := { ... }`,
  which ends around line 270)

**Interfaces:**
- Produces: `Balance.AMBIENT_LIFE` dict, consumed by every later task in this plan.

- [ ] **Step 1: Add the new Balance dict**

Insert after the `FOG_ZC` block (`scripts/balance.gd`, right after its closing `}`
around line 270):

```gdscript
# --- Ambient life: lightposts, burning dumpster, critters, grass -----------
const AMBIENT_LIFE := {
	lightpost_count = 3,
	static_light = {
		radius_tiles = 4.0,          # ~ a Fat/Master zombie's vision range
		light_tex_size = 256,
		steady_energy = 1.1,         # lightpost
		steady_color = Color(1.0, 0.92, 0.75, 1.0),
		flicker_energy = 1.0,        # dumpster base, jittered around this each frame
		flicker_jitter = 0.25,
		flicker_color = Color(1.0, 0.55, 0.2, 1.0),
	},
	dumpster_noise_mask = {
		radius_px = 220.0,           # gunshots inside this radius of a dumpster are muffled
		alert_radius_mult = 0.8,     # 20% less far
	},
	flashlight_glow = {
		dim_energy = 0.35,           # ambient "there's light over there" glow, zombie side
		full_energy = 1.4,           # promoted brightness when a zombie is caught in the beam
		cone_tex_size = 512,
	},
	critters = {
		rat_count = 20,
		bug_count = 20,
		firefly_count = 30,
		rat_speed = 90.0,
		bug_speed = 55.0,
		firefly_speed = 24.0,
		flee_trigger_px = 160.0,         # distance from flashlight/noise that triggers fleeing
		nudge_trigger_px = 28.0,         # fireflies only: distance to nudge away from a character
		bug_dumpster_radius_px = 160.0,  # spawn radius around a scattered dumpster
		wander_change_seconds = 2.5,     # how often idle wander picks a new direction
	},
	grass_dapple = {
		coverage_frac = 0.3,      # fraction of grass tiles that get a mini light-occluder
		occluder_size_px = 14.0,
	},
	grass_character_alpha = 0.72,
}
```

- [ ] **Step 2: Verify it parses**

Use MCP `script_patch` to apply the change, then `project_run` + `logs_read(source="editor")`.
Expected: no `SCRIPT ERROR` lines (a bad dict literal fails to parse immediately on
project boot, so a clean boot is sufficient confirmation here — nothing yet reads
this dict).

---

### Task 2: Cross-role group tags — ALREADY SATISFIED, no action taken

**Correction made during execution:** this task originally planned to add a new
`"shooters"` group via `add_to_group()` in `scenes/shooter/shooter.gd`'s `_ready()`.
While implementing Task 5, inspection of `zombie_controller.gd`'s existing
`_get_enemy_at_position()` turned up `for grp in ["shooter", "npcs"]` — a singular
`"shooter"` group already referenced there. Checked `scenes/shooter/shooter.tscn`
directly: the root node is declaratively tagged `groups=["shooter"]` in the scene
file itself (not via script), so every shooter instance is already in this group on
every peer, no script change needed at all. The originally-planned
`add_to_group("shooters")` line was added then reverted (confirmed no diagnostics
either way).

**Net effect:** every later task in this plan uses the existing `"shooter"` group
(singular) — `get_tree().get_nodes_in_group("shooter")` — instead of a new one.
`scenes/shooter/shooter.gd` is unmodified by this plan.

---

### Task 3: Lightpost prop + placement rule

**Files:**
- Create: `scenes/props/prop_lightpost.tscn`
- Create: `scripts/props/static_light_source.gd`
- Modify: `scripts/prop_scatter.gd`

**Interfaces:**
- Produces: `StaticLightSource` (`extends Node2D`, `class_name StaticLightSource`) —
  reusable by both this task and Task 4 (dumpster). Exports `flicker: bool`. On
  `_ready()`, adds itself to group `"static_lights"` and builds a child `PointLight2D`
  sized from `Balance.AMBIENT_LIFE.static_light`. Consumed by Task 5.
- Consumes: `ShooterLighting.make_radial_texture()` (existing static helper,
  `scripts/shooter_lighting.gd`).

- [ ] **Step 1: Create `StaticLightSource`**

```gdscript
extends Node2D
class_name StaticLightSource

## Attach as a child of a lightpost/dumpster prop, at local position (0,0) so its
## global_position matches the prop's. Builds a Light2D (steady, or flickering if
## `flicker` is set) and registers with the "static_lights" group so
## zombie_controller.gd's _update_fog() can feed it into FogZombieController as a
## permanent full-visibility pseudo-vision source (see design spec §2/§3) —
## the same treatment a zombie's own vision light already gets, no new fog-side
## code needed. Tunables in Balance.AMBIENT_LIFE.static_light.

@export var flicker: bool = false

var radius_px: float
var _light: PointLight2D
var _flicker_rng := RandomNumberGenerator.new()
var _base_energy: float


func _ready() -> void:
	var b: Dictionary = Balance.AMBIENT_LIFE.static_light
	radius_px = b.radius_tiles * 64.0
	_base_energy = b.flicker_energy if flicker else b.steady_energy

	_light = PointLight2D.new()
	_light.texture = ShooterLighting.make_radial_texture(b.light_tex_size)
	_light.texture_scale = radius_px / (float(b.light_tex_size) / 2.0)
	_light.energy = _base_energy
	_light.color = b.flicker_color if flicker else b.steady_color
	_light.shadow_enabled = true
	add_child(_light)

	add_to_group("static_lights")


func _process(_delta: float) -> void:
	if not flicker:
		return
	var b: Dictionary = Balance.AMBIENT_LIFE.static_light
	_light.energy = _base_energy + _flicker_rng.randf_range(-b.flicker_jitter, b.flicker_jitter)
```

Create via MCP `script_create` at `res://scripts/props/static_light_source.gd`.

- [ ] **Step 2: Build the lightpost scene**

Via MCP `scene_manage`/`node_create`, create `scenes/props/prop_lightpost.tscn`:
- Root: `StaticBody2D`, script = `scenes/props/prop_occluder.gd` (the existing shared
  prop-occluder script — reuses its default rectangular-occluder-from-`ColorRect` path
  since the node name won't contain `"Fence"`).
- Child `ColorRect` named `ColorRect` (required by `prop_occluder.gd:12`, which looks
  it up by that exact name) — a thin vertical rect (~6×48px) for the post, offset so
  its base sits at the node origin (e.g. `offset_top = -48, offset_bottom = 0,
  offset_left = -3, offset_right = 3`), dark grey color.
- Child `ColorRect` named `LampHead` — a small rect (~14×10px) at the top of the post
  (`offset_top = -56, offset_bottom = -46`), warm-white color — this is what visually
  "leans toward the street" (Task 3, Step 4 rotates the whole prop, so no separate
  rotation logic needed on this node).
- Child `CollisionShape2D` with a small `RectangleShape2D` matching the post's footprint.
- Child node named `LightSource`, script = `static_light_source.gd`, `flicker = false`
  (default).

- [ ] **Step 3: Add placement-rule helpers to `prop_scatter.gd`**

Add these methods (near the existing `_get_tiles_of_type`/`_filter_to_type` helpers):

```gdscript
## True if any orthogonal neighbor of `coords` is a building tile (checked on
## building_layer) or, when `ground_type` is non-empty, a `ground_type` tile on
## ground_layer.
func _adjacent_to(coords: Vector2i, ground_type: String = "", check_building: bool = false) -> bool:
	var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for n in neighbors:
		var npos: Vector2i = coords + n
		if check_building and building_layer and building_layer.get_cell_tile_data(npos) != null:
			return true
		if ground_type != "":
			var td: TileData = ground_layer.get_cell_tile_data(npos)
			if td != null and td.get_custom_data("tile_type") == ground_type:
				return true
	return false


## Sidewalk tiles next to the street — valid lightpost spots.
func _get_lightpost_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords in _get_tiles_of_type(["sidewalk"]):
		if _adjacent_to(coords, "road", false):
			result.append(coords)
	return result


## Direction (unit vector, tile-grid axis) from a lightpost tile toward its
## adjacent road tile, so the lamp head can face the street. Vector2.ZERO if
## none found (shouldn't happen for tiles _get_lightpost_tiles returned).
func _road_facing(coords: Vector2i) -> Vector2:
	var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for n in neighbors:
		var td: TileData = ground_layer.get_cell_tile_data(coords + n)
		if td != null and td.get_custom_data("tile_type") == "road":
			return Vector2(n)
	return Vector2.ZERO
```

- [ ] **Step 4: Scatter lightposts**

Add exports near the top of `prop_scatter.gd` (alongside `dumpster_scene`/`dumpster_count`):

```gdscript
@export var lightpost_scene: PackedScene
```

(count comes from `Balance.AMBIENT_LIFE.lightpost_count`, not a new export — one fewer
place to keep in sync.)

Add a scatter function:

```gdscript
## Scatters lightposts on sidewalk tiles that border the street, facing the road.
func _scatter_lightposts() -> void:
	if lightpost_scene == null:
		return
	var tiles := _get_lightpost_tiles()
	tiles.shuffle()
	var count: int = Balance.AMBIENT_LIFE.lightpost_count
	var placed := 0
	for coords in tiles:
		if placed >= count:
			break
		var world_pos: Vector2 = ground_layer.map_to_local(coords)
		if _is_too_close(world_pos, 200.0):
			continue
		var prop: Node2D = lightpost_scene.instantiate()
		prop.global_position = world_pos
		var dir := _road_facing(coords)
		if dir != Vector2.ZERO:
			prop.rotation = dir.angle()
		get_parent().add_child(prop)
		_placed_positions.append(world_pos)
		placed += 1
```

Call it from `scatter()`, after the existing dumpster step:

```gdscript
	# 4.5. Scatter lightposts on sidewalks bordering the street
	_scatter_lightposts()
```

- [ ] **Step 5: Wire the scene reference and verify**

In `scenes/world/world.tscn` (or wherever `PropScatter`'s exports are assigned in the
editor — check the `PropScatter` node's Inspector), set `Lightpost Scene` to
`res://scenes/props/prop_lightpost.tscn`, matching how `dumpster_scene` etc. are
already wired. `project_run`, `logs_read(source="all")` for a clean boot, then an
`editor_screenshot` or owner playtest to confirm 3 lightposts appear on sidewalks
facing the street and light up.

---

### Task 4: Burning dumpster — flicker light + placement refinement

**Files:**
- Modify: `scenes/props/prop_dumpster.tscn` (add a child `LightSource` node)
- Modify: `scripts/prop_scatter.gd` (`scatter()`, dumpster step)

**Interfaces:**
- Consumes: `StaticLightSource` from Task 3.

- [ ] **Step 1: Add the flicker light to the dumpster scene**

Via MCP `node_create`, add a child node to `scenes/props/prop_dumpster.tscn`'s root:
named `LightSource`, script = `res://scripts/props/static_light_source.gd`,
`flicker = true`.

- [ ] **Step 2: Tighten dumpster placement**

Add the placement-rule helper (dumpster is "sidewalk against a building, or any
road tile" — different rule shape than lightpost's, so its own function):

```gdscript
## Sidewalk tiles against a building wall, or any road tile — valid dumpster spots.
func _get_dumpster_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coords in _get_tiles_of_type(["sidewalk"]):
		if _adjacent_to(coords, "", true):
			result.append(coords)
	result.append_array(_get_tiles_of_type(["road"]))
	return result
```

Replace the existing dumpster step in `scatter()`:

```gdscript
	# 4. Scatter dumpsters against buildings or on the street
	var dumpster_tiles := _get_dumpster_tiles()
	_scatter_props(dumpster_scene, dumpster_tiles, dumpster_count, 96.0)
```

(`dumpster_count` stays the existing export, already defaulted to `3` — matches the
spec's "3 per item" exactly, no change needed to the count itself.)

- [ ] **Step 3: Tag dumpsters for the noise-mask (Task 6)**

Via MCP `node_manage op=add_to_group`, add the `prop_dumpster.tscn` root node to a new
group `"dumpsters"` (declarative scene-level group, no script change — this is a
different group than `"static_lights"`, which the `LightSource` child already joins
for the fog-reveal purpose; `"dumpsters"` is specifically for the noise-mask lookup in
Task 6, keyed off the *prop's* position, not its light child's).

- [ ] **Step 4: Verify**

`project_run`, `logs_read`, playtest: 3 dumpsters visible, flickering, on sidewalks
against buildings or in the street.

---

### Task 5: Static light sources feed the zombie fog (lightpost/dumpster full reveal)

**Files:**
- Modify: `scripts/zombie_controller.gd` (`_update_fog()`, around line 535)

**Interfaces:**
- Consumes: `"static_lights"` group (Tasks 3 & 4), `Balance.AMBIENT_LIFE.static_light.radius_tiles`.

**No `FogZombieController` changes needed for this task** — `_reveal_diamond()`
already does exactly what a static light needs (permanent, LOS-honest, full
visibility); this task just feeds it more entries.

- [ ] **Step 1: Extend `zombies_data` with static light sources**

In `_update_fog()`, right after the existing zombie-gathering loop, before the
`fog_zc.update_visibility(...)` call:

```gdscript
	# Lightposts + burning dumpsters: permanent, full-visibility pseudo-vision
	# sources for the zombie role — same treatment as a zombie's own vision.
	var light_radius_tiles: int = int(Balance.AMBIENT_LIFE.static_light.radius_tiles)
	for light in get_tree().get_nodes_in_group("static_lights"):
		if light is Node2D:
			var ltile: Vector2i = ground_layer.local_to_map(
				ground_layer.to_local(light.global_position)
			)
			zombies_data.append({"tile": ltile, "vision": light_radius_tiles})
```

(Placed before the existing `fog_zc.update_visibility(zombies_data, _fog_blocked)`
call — that call itself doesn't change in this task; Task 8 is what adds a third
argument to it.)

- [ ] **Step 2: Verify**

Playtest as zombie commander: walk zombies away from a lit lightpost/dumpster, confirm
that area stays fully visible (not dimmed) on the zombie's screen and minimap, the way
a zombie's own vision area does — because it's now feeding the same permanent
`tile_states` promotion.

---

### Task 6: Dumpster noise-mask

**Files:**
- Modify: `scenes/world/world.gd` (`emit_noise()`, `world.gd:431`)

**Interfaces:**
- Consumes: `"dumpsters"` group (Task 4), `Balance.AMBIENT_LIFE.dumpster_noise_mask`.

- [ ] **Step 1: Add the masking check**

Replace `emit_noise()`:

```gdscript
## Server-side: broadcast a noise (e.g. a gunshot) to every peer. A burning
## dumpster within its masking radius muffles the sound, cutting the
## effective alert radius (not attracting zombies itself — see design spec §3).
func emit_noise(world_pos: Vector2, strength: float) -> void:
	if not multiplayer.is_server():
		return
	var alert_radius: float = Balance.AGGRO.alert_radius_px
	var mask: Dictionary = Balance.AMBIENT_LIFE.dumpster_noise_mask
	for d in get_tree().get_nodes_in_group("dumpsters"):
		if d is Node2D and d.global_position.distance_to(world_pos) <= mask.radius_px:
			alert_radius *= mask.alert_radius_mult
			break
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D and z.has_method("alert_to") \
			and z.global_position.distance_to(world_pos) <= alert_radius:
			z.alert_to(world_pos)
	rpc_noise_event.rpc(world_pos, strength)
```

- [ ] **Step 2: Verify**

Playtest: fire a shot near a dumpster vs. away from one, confirm zombies noticeably
farther away react to the away-from-dumpster shot than the near-dumpster one (rough
sanity check — exact radius tuning happens later via `Balance.AMBIENT_LIFE`).

---

### Task 7: `FogZombieController` cone-reveal (pure logic, transient)

**Files:**
- Modify: `scripts/fog_zombie_controller.gd`
- Create: `test/test_reveal_cone.gd`

**Interfaces:**
- Produces: `_reveal_cone(origin, dir, half_angle_rad, range_tiles, blocked, out)`
  (new instance method) and an extended `update_visibility()` signature:
  `update_visibility(zombies_data, blocked, transient_cone: Variant = null)`.
- Consumed by: Task 8 (`zombie_controller.gd`).

- [ ] **Step 1: Add `_reveal_cone()`**

```gdscript
## Fills `out[Vector2i] = true` for every tile within `range_tiles` of `origin`
## that's inside the cone (angle from `dir` <= half_angle_rad) with clear LOS.
## Mirrors _reveal_diamond's LOS-honesty (same tile_line_clear check) but keyed
## by angle+distance instead of Manhattan radius, and writes to a caller-owned
## dict instead of tile_states — the caller decides whether that's transient
## (see update_visibility below) or permanent.
func _reveal_cone(
	origin: Vector2i, dir: Vector2, half_angle_rad: float, range_tiles: int,
	blocked: Dictionary, out: Dictionary
) -> void:
	for dx in range(-range_tiles, range_tiles + 1):
		for dy in range(-range_tiles, range_tiles + 1):
			if dx == 0 and dy == 0:
				continue
			var offset := Vector2i(dx, dy)
			if Vector2(offset).length() > float(range_tiles):
				continue
			if absf(Vector2(offset).normalized().angle_to(dir)) > half_angle_rad:
				continue
			var t := origin + offset
			if t.x >= 0 and t.x < GRID_W and t.y >= 0 and t.y < GRID_H \
				and tile_line_clear(origin, t, blocked):
				out[t] = true
```

- [ ] **Step 2: Thread a transient overlay through `update_visibility()`**

Replace the signature and step-3 image-write loop:

```gdscript
## `transient_cone`, if non-null, is a Dictionary:
##   {"origin": Vector2i, "dir": Vector2, "half_angle_rad": float, "range_tiles": int}
## Its tiles get unlocked to VIS_EXPLORED in the OUTPUT image only — never
## written into the persistent tile_states array, so it never becomes
## permanent zombie memory (see design spec §4).
func update_visibility(
	zombies_data: Array[Dictionary], blocked: Dictionary, transient_cone: Variant = null
) -> void:
	for i in range(tile_states.size()):
		if tile_states[i] == STATE_VISIBLE:
			tile_states[i] = STATE_EXPLORED

	for zdata in zombies_data:
		var ztile: Vector2i = zdata["tile"]
		var vision: int = zdata["vision"]
		_reveal_diamond(ztile, vision, blocked)

	var transient: Dictionary = {}
	if transient_cone != null:
		_reveal_cone(
			transient_cone.origin, transient_cone.dir, transient_cone.half_angle_rad,
			transient_cone.range_tiles, blocked, transient
		)

	for x in range(GRID_W):
		for y in range(GRID_H):
			var state: int = tile_states[y * GRID_W + x]
			var vis: float
			match state:
				STATE_UNEXPLORED:
					vis = VIS_UNEXPLORED
				STATE_EXPLORED:
					vis = VIS_EXPLORED
				STATE_VISIBLE:
					vis = VIS_VISIBLE
				_:
					vis = VIS_UNEXPLORED
			if transient.has(Vector2i(x, y)):
				vis = maxf(vis, VIS_EXPLORED)
			visibility_image.set_pixel(x, y, Color(vis, 0.0, 0.0, 1.0))
```

- [ ] **Step 3: Write the headless test**

Mirrors `test/test_fog_los.gd`'s exact style:

```gdscript
extends SceneTree

func _init() -> void:
	var F = load("res://scripts/fog_zombie_controller.gd")
	var failed := 0

	var fzc = F.new()
	fzc.GRID_W = 10
	fzc.GRID_H = 10

	var out := {}
	fzc._reveal_cone(Vector2i(5, 5), Vector2.RIGHT, deg_to_rad(20.0), 4, {}, out)
	if not out.has(Vector2i(8, 5)):
		push_error("tile straight ahead should be revealed"); failed += 1
	if out.has(Vector2i(5, 8)):
		push_error("tile behind (perpendicular) should not be revealed"); failed += 1
	if out.has(Vector2i(1, 5)):
		push_error("tile beyond range should not be revealed"); failed += 1

	var blocked := {Vector2i(6, 5): true}
	var out2 := {}
	fzc._reveal_cone(Vector2i(5, 5), Vector2.RIGHT, deg_to_rad(20.0), 4, blocked, out2)
	if out2.has(Vector2i(8, 5)):
		push_error("tile behind a blocker should not be revealed"); failed += 1

	if failed == 0:
		print("test_reveal_cone: PASS"); quit(0)
	else:
		print("test_reveal_cone: FAIL (%d)" % failed); quit(1)
```

- [ ] **Step 4: Run it (editor closed)**

Per CLAUDE.md gotcha, only with the Godot editor closed:
`Godot --headless --path . --script test/test_reveal_cone.gd`. Expected: `PASS`, exit 0.

- [ ] **Step 5: Verify the project still boots**

Re-open the editor, `project_run`, `logs_read` — expect a clean boot (no other code
calls `update_visibility()` with the new third argument yet until Task 8, so existing
behavior is unchanged: default `transient_cone = null` keeps old callers working as-is).

---

### Task 8: Cross-role flashlight glow (zombie senses the shooter's light)

**Files:**
- Modify: `scripts/zombie_controller.gd` (`_update_fog()` and a new
  `_update_flashlight_glow()`)
- Create: `scripts/flashlight_glow.gd`
- Create: `test/test_flashlight_glow.gd`

**Interfaces:**
- Consumes: `"shooter"` group (Task 2), `_reveal_cone`/extended `update_visibility()`
  (Task 7), `ShooterLighting.make_cone_texture()` (existing), `Balance.AMBIENT_LIFE.flashlight_glow`,
  `Balance.FOG_SHOOTER` (existing: `flashlight_range`, `flashlight_half_angle_deg`).

- [ ] **Step 1: Pure geometry helper**

```gdscript
extends RefCounted
class_name FlashlightGlow

## Pure geometry check: is `zombie_pos` within the shooter's flashlight cone
## (distance + angle from the shooter's aim) with clear tile line-of-sight?
## Used to decide whether the zombie-side flashlight glow should jump to full
## brightness — see design spec §4, "risk/reward promotion".
static func zombie_caught(
	shooter_pos: Vector2, shooter_rot: float, zombie_pos: Vector2,
	range_px: float, half_angle_rad: float,
	ground_layer: TileMapLayer, blocked: Dictionary
) -> bool:
	var to_zombie := zombie_pos - shooter_pos
	if to_zombie.length() > range_px:
		return false
	var dir := Vector2.RIGHT.rotated(shooter_rot)
	if to_zombie.length() > 0.0 and absf(to_zombie.normalized().angle_to(dir)) > half_angle_rad:
		return false
	var FZC = load("res://scripts/fog_zombie_controller.gd")
	var from_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(shooter_pos))
	var to_tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(zombie_pos))
	return FZC.tile_line_clear(from_tile, to_tile, blocked)
```

Create via MCP `script_create` at `res://scripts/flashlight_glow.gd`.

- [ ] **Step 2: Headless test**

```gdscript
extends SceneTree

func _init() -> void:
	var FG = load("res://scripts/flashlight_glow.gd")
	var failed := 0

	if FG.zombie_caught(Vector2.ZERO, 0.0, Vector2(100, 0), 540.0, deg_to_rad(22.0), null, {}) != true:
		push_error("straight ahead, in range, should be caught"); failed += 1
	if FG.zombie_caught(Vector2.ZERO, 0.0, Vector2(0, 100), 540.0, deg_to_rad(22.0), null, {}) != false:
		push_error("perpendicular should not be caught"); failed += 1
	if FG.zombie_caught(Vector2.ZERO, 0.0, Vector2(1000, 0), 540.0, deg_to_rad(22.0), null, {}) != false:
		push_error("beyond range should not be caught"); failed += 1

	if failed == 0:
		print("test_flashlight_glow: PASS"); quit(0)
	else:
		print("test_flashlight_glow: FAIL (%d)" % failed); quit(1)
```

Note: the in-range/in-cone cases above pass `ground_layer = null` and `blocked = {}` —
`tile_line_clear` is only reached when distance+angle already pass, and with an empty
`blocked` dict `local_to_map`/`to_local` on a `null` layer would crash, so this test
only exercises the early-out `false` paths plus one full pass with a **real**
`TileMapLayer`. Since building a real `TileMapLayer` headlessly is exactly the
"headless class_name-extending-scene-type" gotcha risk from CLAUDE.md, keep the
positive (`true`) case verified via live playtest instead (Step 5) rather than fighting
the headless test for that one path.

Run headless (editor closed): `Godot --headless --path . --script test/test_flashlight_glow.gd`.

- [ ] **Step 3: Wire the cone into `_update_fog()`**

In `zombie_controller.gd`, extend `_update_fog()` (after Task 5's static-light block,
before the `fog_zc.update_visibility(...)` call):

```gdscript
	# Shooter's flashlight: transient ambient-glow reveal (never persisted —
	# see design spec §4). Single shooter per match today.
	var cone: Variant = null
	for s in get_tree().get_nodes_in_group("shooter"):
		if s is Node2D:
			var origin: Vector2i = ground_layer.local_to_map(ground_layer.to_local(s.global_position))
			cone = {
				"origin": origin,
				"dir": Vector2.RIGHT.rotated(s.rotation),
				"half_angle_rad": deg_to_rad(Balance.FOG_SHOOTER.flashlight_half_angle_deg),
				"range_tiles": int(Balance.FOG_SHOOTER.flashlight_range / 64.0),
			}
			break

	fog_zc.update_visibility(zombies_data, _fog_blocked, cone)
	fog_texture.update(fog_zc.visibility_image)
	_update_flashlight_glow()
```

(This replaces the existing two-line `fog_zc.update_visibility(...)` /
`fog_texture.update(...)` pair with the three lines above — same calls, `cone`
threaded through, plus the new glow update.)

- [ ] **Step 4: Add the local glow light + brightness switch**

Add a new member near the top of `zombie_controller.gd` (alongside `fog_zc`,
`fog_texture`): `var _flashlight_glow: PointLight2D = null`. Then add:

```gdscript
## Maintains a local, dim Light2D standing in for "the shooter's flashlight,
## as sensed through the fog" — the shooter's own flashlight Light2D is built
## client-side-only (never replicated), so this is a separate light, reusing
## the same cone texture for a consistent look. Energy jumps to full brightness
## when a zombie is caught in the beam (design spec §4's risk/reward promotion).
func _update_flashlight_glow() -> void:
	var shooter_node: Node2D = null
	for s in get_tree().get_nodes_in_group("shooter"):
		if s is Node2D:
			shooter_node = s
			break

	if shooter_node == null:
		if _flashlight_glow:
			_flashlight_glow.visible = false
		return

	var b: Dictionary = Balance.AMBIENT_LIFE.flashlight_glow
	if _flashlight_glow == null:
		_flashlight_glow = PointLight2D.new()
		_flashlight_glow.texture = ShooterLighting.make_cone_texture(
			int(b.cone_tex_size), deg_to_rad(Balance.FOG_SHOOTER.flashlight_half_angle_deg)
		)
		_flashlight_glow.texture_scale = (
			Balance.FOG_SHOOTER.flashlight_range / (float(b.cone_tex_size) / 2.0)
		)
		_flashlight_glow.color = Balance.FOG_SHOOTER.flashlight_color
		_flashlight_glow.shadow_enabled = true
		get_parent().add_child(_flashlight_glow)

	_flashlight_glow.visible = true
	_flashlight_glow.global_position = shooter_node.global_position
	_flashlight_glow.rotation = shooter_node.rotation

	var zombie_in_beam := false
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Node2D and FlashlightGlow.zombie_caught(
			shooter_node.global_position, shooter_node.rotation, zombie.global_position,
			Balance.FOG_SHOOTER.flashlight_range,
			deg_to_rad(Balance.FOG_SHOOTER.flashlight_half_angle_deg),
			ground_layer, _fog_blocked
		):
			zombie_in_beam = true
			break
	_flashlight_glow.energy = b.full_energy if zombie_in_beam else b.dim_energy
```

- [ ] **Step 5: Live-playtest verification**

Two players (or one client switching roles, whatever this project's test setup
allows), one as shooter, one as zombie commander:
1. Shooter walks far from any zombie, flashlight on — zombie-commander screen should
   show a **dim** glow moving around, with terrain visible underneath but no legible
   entity detail — and it should disappear once the shooter turns the area's fog back
   to black-hidden (i.e. moves away, no permanent reveal left behind).
2. Shooter shines the light directly at a zombie cluster — the *entire* cone should
   jump to full brightness on the zombie-commander's screen, not just the small patch
   immediately around the nearest zombie.
3. Confirm no regression to the shooter's own screen (this task never touches
   `ShooterLighting`).

---

### Task 9: Critter behavior scripts

**Files:**
- Create: `scripts/critters/critter_base.gd`
- Create: `scenes/props/critter_rat.tscn`, `scenes/props/critter_bug.tscn`,
  `scenes/props/critter_firefly.tscn`

**Interfaces:**
- Produces: `class_name CritterBase extends Node2D` with an `enum Kind { RAT, BUG, FIREFLY }`
  export, consumed by Task 10 (spawner just instances the three scenes).
- Consumes: `world.gd`'s `noise_event` signal, `"shooter"` group (Task 2) for flashlight
  proximity.

- [ ] **Step 1: Write the shared behavior script**

```gdscript
extends Node2D
class_name CritterBase

## Shared behavior for rats/bugs/lightning bugs (design spec §5). Rats and bugs
## wander idly and flee from the shooter's flashlight cone or a gunshot noise
## event; lightning bugs never flee, they only nudge aside if a
## zombie/NPC/player walks directly through their path. Placeholder shapes only
## (a ColorRect child) — this script owns behavior, not visuals.

enum Kind { RAT, BUG, FIREFLY }

@export var kind: Kind = Kind.RAT
@export var ground_layer: TileMapLayer

var _speed: float
var _wander_dir := Vector2.ZERO
var _wander_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var c: Dictionary = Balance.AMBIENT_LIFE.critters
	match kind:
		Kind.RAT:
			_speed = c.rat_speed
		Kind.BUG:
			_speed = c.bug_speed
		Kind.FIREFLY:
			_speed = c.firefly_speed
	_pick_new_wander_dir()


func _process(delta: float) -> void:
	var c: Dictionary = Balance.AMBIENT_LIFE.critters

	if kind == Kind.FIREFLY:
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_pick_new_wander_dir()
		var nudge := _nudge_away_from_nearby(c.nudge_trigger_px)
		global_position += (_wander_dir + nudge) * _speed * delta
		return

	var flee_dir := _flee_direction(c.flee_trigger_px)
	if flee_dir != Vector2.ZERO:
		global_position += flee_dir * _speed * delta
		return

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_pick_new_wander_dir()
	global_position += _wander_dir * _speed * delta


func _pick_new_wander_dir() -> void:
	var c: Dictionary = Balance.AMBIENT_LIFE.critters
	_wander_dir = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
	_wander_timer = c.wander_change_seconds


## Rats/bugs only: away from the nearest shooter's flashlight cone (if inside
## it) or the most recent gunshot, whichever is closer. Vector2.ZERO if neither
## is within trigger range.
func _flee_direction(trigger_px: float) -> Vector2:
	var away := Vector2.ZERO
	var closest := trigger_px
	for s in get_tree().get_nodes_in_group("shooter"):
		if s is Node2D:
			var d: float = global_position.distance_to(s.global_position)
			if d < closest:
				closest = d
				away = (global_position - s.global_position).normalized()
	if _last_noise_pos != null and global_position.distance_to(_last_noise_pos) < closest:
		away = (global_position - _last_noise_pos).normalized()
	return away


## Lightning bugs only: a small push directly away from any zombie/NPC/player
## within `trigger_px` — not fear, just staying out from underfoot.
func _nudge_away_from_nearby(trigger_px: float) -> Vector2:
	var nudge := Vector2.ZERO
	for group in ["zombies", "npcs", "shooter"]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node2D and global_position.distance_to(n.global_position) < trigger_px:
				nudge += (global_position - n.global_position).normalized()
	return nudge


var _last_noise_pos: Variant = null


func _on_noise(pos: Vector2, _strength: float) -> void:
	_last_noise_pos = pos
```

Create via MCP `script_create` at `res://scripts/critters/critter_base.gd`.

- [ ] **Step 2: Build the three critter scenes**

Via MCP `scene_manage`/`node_create`, for each of `critter_rat.tscn`, `critter_bug.tscn`,
`critter_firefly.tscn`:
- Root: `Node2D`, script = `critter_base.gd`, `kind` set to `RAT`/`BUG`/`FIREFLY`
  respectively.
- Child `ColorRect`, small (rat ~10×6px grey, bug ~5×4px brown, firefly ~3×3px
  pale-yellow), centered on the origin — placeholder shapes per the spec.

- [ ] **Step 3: Wire the noise signal**

In `scenes/world/world.gd`'s `_ready()` (or wherever critters get instantiated —
this connection needs to happen once per spawned critter, so it's simplest done in
Task 10's spawner right after `add_child(prop)`): `prop.get_node("../..")` isn't
reliable here — instead, connect directly where the world node is reachable. Add to
`CritterBase._ready()` itself (append to the function written in Step 1):

```gdscript
	var world_node := get_tree().get_first_node_in_group("world")
	if world_node and world_node.has_signal("noise_event"):
		world_node.noise_event.connect(_on_noise)
```

This requires `world.gd`'s root to be in a `"world"` group — add
`add_to_group("world")` to `world.gd`'s existing `_ready()` (a one-line addition,
harmless alongside whatever else already runs there).

- [ ] **Step 4: Verify**

`project_run`, `logs_read` for a clean boot (no critters spawned yet until Task 10, so
this task alone has nothing to visually check beyond "no script errors").

---

### Task 10: Critter placement/spawning

**Files:**
- Modify: `scripts/prop_scatter.gd`

**Interfaces:**
- Consumes: `CritterBase` scenes (Task 9), `Balance.AMBIENT_LIFE.critters` counts,
  `"grass"`/anywhere-walkable/dumpster-proximity placement rules (spec §5).

- [ ] **Step 1: Add exports + scatter function**

```gdscript
@export var rat_scene: PackedScene
@export var bug_scene: PackedScene
@export var firefly_scene: PackedScene
```

```gdscript
## Scatters the three critter types per their placement rules (design spec §5):
## rats anywhere walkable, bugs near a scattered dumpster, fireflies on grass.
func _scatter_critters() -> void:
	var c: Dictionary = Balance.AMBIENT_LIFE.critters
	var walkable := _get_tiles_of_type(["road", "sidewalk", "grass", "parking"])

	if rat_scene:
		var rat_tiles := walkable.duplicate()
		rat_tiles.shuffle()
		var placed := 0
		for coords in rat_tiles:
			if placed >= c.rat_count:
				break
			var prop: Node2D = rat_scene.instantiate()
			prop.global_position = ground_layer.map_to_local(coords)
			get_parent().add_child(prop)
			placed += 1

	if bug_scene:
		var dumpster_positions: Array[Vector2] = []
		for d in get_tree().get_nodes_in_group("dumpsters"):
			if d is Node2D:
				dumpster_positions.append(d.global_position)
		var placed := 0
		var attempts := 0
		while placed < c.bug_count and attempts < c.bug_count * 20 and not dumpster_positions.is_empty():
			attempts += 1
			var origin: Vector2 = dumpster_positions[_rng_index(dumpster_positions.size())]
			var offset := Vector2.RIGHT.rotated(randf() * TAU) * randf() * c.bug_dumpster_radius_px
			var world_pos := origin + offset
			var tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world_pos))
			var td: TileData = ground_layer.get_cell_tile_data(tile)
			if td == null or not td.get_custom_data("tile_type") in ["road", "sidewalk", "grass", "parking"]:
				continue
			var prop: Node2D = bug_scene.instantiate()
			prop.global_position = world_pos
			get_parent().add_child(prop)
			placed += 1

	if firefly_scene:
		var grass_tiles := _get_tiles_of_type(["grass"])
		grass_tiles.shuffle()
		var placed := 0
		for coords in grass_tiles:
			if placed >= c.firefly_count:
				break
			var prop: Node2D = firefly_scene.instantiate()
			prop.global_position = ground_layer.map_to_local(coords)
			get_parent().add_child(prop)
			placed += 1


func _rng_index(size: int) -> int:
	return randi() % size
```

Call it from `scatter()`, as the last step:

```gdscript
	# 6. Scatter ambient critters
	_scatter_critters()
```

(Note: `_get_dumpster_tiles()`/dumpsters must be scattered before this runs, since bug
placement depends on `"dumpsters"` group membership already existing — `scatter()`'s
existing step order already places dumpsters at step 4, before this new step 6, so
this is naturally satisfied.)

- [ ] **Step 2: Wire scene references**

In the `PropScatter` node's Inspector (`scenes/world/world.tscn`), set `Rat Scene`,
`Bug Scene`, `Firefly Scene` to the three scenes from Task 9.

- [ ] **Step 3: Verify**

`project_run`, `logs_read`, playtest: confirm roughly 20 rats/20 bugs/30 fireflies
spawn, rats wander and flee the flashlight/gunshots, bugs cluster near dumpsters and
do the same, fireflies drift over grass and only nudge aside near characters (no fear
reaction). Check frame rate doesn't visibly suffer with ~70 extra active nodes — if it
does, this is exactly what `Balance.AMBIENT_LIFE.critters` counts are for tuning down.

---

### Task 11: Grass light-dappling

**Files:**
- Modify: `scripts/shooter_lighting.gd` (new helper)
- Modify: `scenes/world/world.gd` (`_setup_fog()`, shooter branch only)

**Interfaces:**
- Consumes: `Balance.AMBIENT_LIFE.grass_dapple`.

**Scope reminder (per spec §6):** shooter-side visual only — does not touch
`FogZombieController` or noise (that's the dumpster's job only, Task 6).

- [ ] **Step 1: Add a grass-occluder-position helper**

In `scripts/shooter_lighting.gd`, add alongside `collect_static_occluder_positions()`:

```gdscript
## Sparse occluder positions across grass tiles — a partial-coverage scatter
## (not one per tile) so the flashlight beam crossing grass looks dappled
## rather than solidly blocked, in the same visual family as how a fence's
## separate small occluders already look (see prop_occluder.gd). Shooter-side
## visual only; does not affect the zombie's fog (design spec §6).
static func collect_grass_dapple_positions(ground_layer: TileMapLayer) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if ground_layer == null:
		return out
	var b: Dictionary = Balance.AMBIENT_LIFE.grass_dapple
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("grass_dapple")  # deterministic — same on every peer
	var used_rect: Rect2i = ground_layer.get_used_rect()
	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
		for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
			var coords := Vector2i(x, y)
			var td: TileData = ground_layer.get_cell_tile_data(coords)
			if td == null or td.get_custom_data("tile_type") != "grass":
				continue
			if rng.randf() < b.coverage_frac:
				out.append(ground_layer.to_global(ground_layer.map_to_local(coords)))
	return out
```

- [ ] **Step 2: Wire it into shooter setup**

In `scenes/world/world.gd`'s `_setup_fog()`, in the `GameState.role == HUMAN` branch,
right after the existing `ShooterLighting.setup(...)` call:

```gdscript
		var grass_positions := ShooterLighting.collect_grass_dapple_positions(ground_layer)
		ShooterLighting.build_static_occluders(
			self, grass_positions, Balance.AMBIENT_LIFE.grass_dapple.occluder_size_px
		)
```

(Reuses `build_static_occluders` exactly as-is — it already just takes a position list
and an occluder size, no changes needed there.)

- [ ] **Step 3: Verify**

Playtest as shooter: walk the flashlight across a grass zone (the park near tiles
(27,2)-(44,9) per `prop_scatter.gd`'s existing tree zones), confirm the beam looks
dappled/broken rather than either solid or unaffected, and confirm it doesn't fully
block movement or vision (occluders here only cast light-shadows, no
`CollisionShape2D`, so no gameplay/physics impact — same as how fence "gap" segments
already work in `prop_occluder.gd`, except these grass points have no adjoining solid
segments at all, so there's no collision consideration here to begin with — the
occluder-only, no-collision approach only requires visual confirmation).

---

### Task 12: Grass character-obscuring

**Files:**
- Modify: `scenes/world/world.gd` (new `_apply_grass_dimming()`, called from `_process()`)

**Interfaces:**
- Consumes: `"shooter"` (Task 2), `"zombies"`, `"npcs"` groups (all pre-existing),
  `Balance.AMBIENT_LIFE.grass_character_alpha`.

**Design choice:** centralized in `world.gd` (which already owns `ground_layer`)
rather than touching `scenes/shooter/shooter.gd` / `scenes/zombie/zombie.gd` /
`scenes/npc/npc_human.gd` individually — those three scripts don't currently share a
common base or helper, and none of them (other than the NPC script) already holds a
`ground_layer` reference, so wiring it into each separately would mean three
near-duplicate blocks plus new inter-node wiring. One `_process()` pass over the
existing groups avoids that.

- [ ] **Step 1: Add the dimming pass**

```gdscript
## Slight visual obscuring for characters standing on grass tiles (design spec
## §6) — purely cosmetic, consistent for every viewer since it's baked into
## the character node's own modulate, not per-viewer.
func _apply_grass_dimming() -> void:
	var alpha: float = Balance.AMBIENT_LIFE.grass_character_alpha
	for group in ["shooter", "zombies", "npcs"]:
		for n in get_tree().get_nodes_in_group(group):
			if not (n is Node2D):
				continue
			var tile: Vector2i = ground_layer.local_to_map(ground_layer.to_local(n.global_position))
			var td: TileData = ground_layer.get_cell_tile_data(tile)
			var on_grass: bool = td != null and td.get_custom_data("tile_type") == "grass"
			n.modulate.a = alpha if on_grass else 1.0
```

Call it from `world.gd`'s existing `_process()` if one exists, otherwise add a minimal
one:

```gdscript
func _process(_delta: float) -> void:
	_apply_grass_dimming()
```

(If `world.gd` already has a `_process()`, append the call there instead of adding a
second one — check before adding, GDScript doesn't allow duplicate `_process` defs in
one script.)

- [ ] **Step 2: Verify**

Playtest: walk the shooter, an NPC, and a zombie through a grass zone, confirm each
dims slightly while on grass and returns to full opacity off it, for every viewer
(shooter's own screen and the zombie-commander's screen both).

---

### Task 13: Changelog + final verification pass

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a changelog entry**

Following the existing phase-bullet style (see the Phase 9 entries from the HUD
reskin work), add one summarizing this feature set: lightposts, burning dumpster
(with noise-masking), cross-role flashlight-glow fog mechanic, three critter types,
and grass light-dappling/character-obscuring.

- [ ] **Step 2: Full live-editor verification**

`project_run`, `logs_read(source="all")` for a clean boot. Then a full owner playtest
covering every piece in this plan at once (a fresh map roll exercises the placement
rules for lightposts/dumpsters/critters together): lightposts and the dumpster light
up and are visible to both roles; gunshots near the dumpster pull zombies from a
shorter range; the zombie-commander senses the shooter's flashlight at reduced
fidelity from a distance and at full fidelity when a zombie is caught in the beam;
critters behave per type; grass dapples the flashlight and dims characters standing
in it.

- [ ] **Step 3: Suggest a commit message**

Per CLAUDE.md, don't commit — just hand back a short suggested message once the
playtest confirms everything works, e.g. `Add ambient lighting, critters, and
cross-role flashlight fog`.
