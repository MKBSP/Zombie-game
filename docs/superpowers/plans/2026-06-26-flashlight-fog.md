# Flashlight Fog of War v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shooter's screen-space tile fog with Godot 2D lighting — a dark CanvasModulate "fog", a hard-edged flashlight cone plus a personal halo, and real straight-line shadows cast by buildings, props, zombies, and NPCs.

**Architecture:** In the HUMAN (shooter) instance only, a `CanvasModulate` darkens the world; two `PointLight2D` children of the shooter (cone flashlight + radial halo) add brightness back. `LightOccluder2D` nodes — generated at runtime for static tiles/props, and authored into the moving-entity scenes — block the light. The shooter body already rotates to face aim, so the beam tracks aim with no per-frame code. The zombie-controller instance is a separate networked process and is untouched.

**Tech Stack:** Godot 4.6.3, GL Compatibility renderer (2D lights + shadows + CanvasModulate all supported), GDScript. Tests are headless `SceneTree` scripts.

## Global Constraints

- Engine: Godot 4.6.3, GL Compatibility renderer, 2D.
- All gameplay/visual numbers live in `scripts/balance.gd` — never hard-code them in scenes or logic.
- No `Co-Authored-By` / Claude attribution in commit messages.
- Do not push. Commit locally per task.
- After meaningful changes, update `CHANGELOG.md` (and `ARCHITECTURE.md` / `PROJECT.md` if structure/status shifts).
- A live Godot editor is usually running — prefer the **godot-ai MCP** (`script_patch`, `node_create`, `node_set_property`, `scene_open`, `scene_save`, `test_run`, `editor_screenshot`) over blind file writes for scene work. Check `editor_state` first.
- Tests run headless as `SceneTree` scripts: `godot --headless --path . -s res://test/<file>.gd` (or godot-ai MCP `test_run`). A passing run prints `ALL TESTS PASSED` and exits 0.

---

## File Structure

**Create:**
- `scripts/shooter_lighting.gd` — `ShooterLighting`, a stateless helper (static functions): generates the cone texture, the halo texture, occluder polygons, and the list of static occluder world positions. Also a `setup(...)` that assembles CanvasModulate + lights + static occluders under a given parent for the HUMAN role.
- `test/test_shooter_lighting.gd` — headless unit tests for the pure helpers.

**Modify:**
- `scripts/balance.gd` — repurpose `FOG_SHOOTER` into lighting params.
- `scenes/world/world.gd` — replace `_setup_fog()` and per-frame fog update with `ShooterLighting` setup; drop `shooter_fog_rect` references.
- `scenes/world/world.tscn` — remove the `ShooterFogRect` ColorRect node.
- `scenes/zombie/zombie.tscn`, `scenes/zombie/master_zombie.tscn`, `scenes/npc/npc_human.tscn` — add a `LightOccluder2D` child to each.
- `CHANGELOG.md`, `ARCHITECTURE.md`, `PROJECT.md` — document the change.

**Delete:**
- `scripts/fog_shooter.gd` (+ `.uid`) — the old `FogShooter` tile-raycaster.
- `shader/fog_of_war.gdshader` (+ `.uid`) — the old screen-space fog shader.

---

## Task 1: Balance lighting parameters

**Files:**
- Modify: `scripts/balance.gd:124-130` (the `FOG_SHOOTER` dict)

**Interfaces:**
- Produces: `Balance.FOG_SHOOTER` with keys `ambient_darkness: Color`, `flashlight_range: float`, `flashlight_energy: float`, `flashlight_half_angle_deg: float`, `flashlight_color: Color`, `halo_radius: float`, `halo_energy: float`, `halo_color: Color`, `shadows_enabled: bool`, `dynamic_occluder_radius: float`, `cone_tex_size: int`, `halo_tex_size: int`.

- [ ] **Step 1: Replace the FOG_SHOOTER dict**

Replace the existing dict (currently `scripts/balance.gd:124-130`) with:

```gdscript
# --- Fog: shooter flashlight lighting (2D lights) --------------------------
# ambient_darkness is the CanvasModulate tint over the whole world — the
# "opacity dial": lower = near-black, higher = faint grey where the street
# layout stays readable. Everything else tunes the two lights / occluders.
const FOG_SHOOTER := {
	ambient_darkness = Color(0.16, 0.16, 0.19, 1.0),
	flashlight_range = 540.0,          # px, cone reach from the shooter
	flashlight_energy = 1.5,
	flashlight_half_angle_deg = 22.0,  # half the cone's opening angle
	flashlight_color = Color(1.0, 0.97, 0.85, 1.0),
	halo_radius = 140.0,               # px, ~2 tiles around the shooter
	halo_energy = 0.9,
	halo_color = Color(0.82, 0.86, 1.0, 1.0),
	shadows_enabled = true,
	dynamic_occluder_radius = 14.0,    # px, body-sized occluder for entities
	cone_tex_size = 512,               # generated cone texture resolution
	halo_tex_size = 256,               # generated halo texture resolution
}
```

- [ ] **Step 2: Verify the project still parses**

Run: `godot --headless --path . --check-only scripts/balance.gd` (or open via godot-ai MCP `editor_state` and confirm no parse errors).
Expected: no parse errors.

- [ ] **Step 3: Commit**

```bash
git add scripts/balance.gd
git commit -m "balance: repurpose FOG_SHOOTER into 2D-light params"
```

---

## Task 2: Pure lighting helpers (textures + polygon)

**Files:**
- Create: `scripts/shooter_lighting.gd`
- Test: `test/test_shooter_lighting.gd`

**Interfaces:**
- Produces:
  - `ShooterLighting.make_cone_texture(tex_size: int, half_angle_rad: float) -> ImageTexture` — white inside the cone (apex at texture center, opening toward local +X), transparent outside; alpha is a hard 0/255 edge.
  - `ShooterLighting.make_radial_texture(tex_size: int) -> ImageTexture` — white with a soft radial alpha falloff (1 at center → 0 at the edge).
  - `ShooterLighting.make_square_occluder_polygon(size: float) -> OccluderPolygon2D` — a closed square polygon `size`×`size` centered on origin.

- [ ] **Step 1: Write the failing test**

Create `test/test_shooter_lighting.gd`:

```gdscript
extends SceneTree

var _failures := 0

func _init() -> void:
	_test_cone()
	_test_radial()
	_test_square()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)

func _alpha_at(tex: ImageTexture, x: int, y: int) -> int:
	return int(round(tex.get_image().get_pixel(x, y).a * 255.0))

func _test_cone() -> void:
	var size := 512
	var tex := ShooterLighting.make_cone_texture(size, deg_to_rad(22.0))
	var c := size / 2
	# A point just forward (+X) of the apex is inside the cone -> lit.
	_check("cone forward lit", _alpha_at(tex, c + 20, c) > 200)
	# Straight up from the apex (-90 deg) is outside a 22-deg half-angle.
	_check("cone up dark", _alpha_at(tex, c, c - 100) == 0)
	# Behind the apex (-X) is outside the cone.
	_check("cone behind dark", _alpha_at(tex, c - 100, c) == 0)
	# The far corner is beyond the radius -> dark.
	_check("cone corner dark", _alpha_at(tex, size - 1, size - 1) == 0)

func _test_radial() -> void:
	var size := 256
	var tex := ShooterLighting.make_radial_texture(size)
	var c := size / 2
	_check("radial center bright", _alpha_at(tex, c, c) > 230)
	_check("radial edge dark", _alpha_at(tex, c, 0) == 0)
	_check("radial mid partial", _alpha_at(tex, c, c - size / 4) > 80 and _alpha_at(tex, c, c - size / 4) < 200)

func _test_square() -> void:
	var poly := ShooterLighting.make_square_occluder_polygon(28.0)
	var pts := poly.polygon
	_check("square has 4 points", pts.size() == 4)
	_check("square corner correct", pts[0].is_equal_approx(Vector2(-14, -14)))
	_check("square closed", poly.closed)

func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s res://test/test_shooter_lighting.gd`
Expected: FAIL — `ShooterLighting` is not defined yet (parser error / class not found).

- [ ] **Step 3: Implement the helpers**

Create `scripts/shooter_lighting.gd`:

```gdscript
extends Node
class_name ShooterLighting

## Stateless helpers that build the shooter's 2D-light fog of war:
## generated cone / halo textures, occluder polygons, and the assembly of
## CanvasModulate + lights + static occluders for the HUMAN role.


## Hard-edged cone light texture. Apex at the texture center, opening toward
## local +X (the shooter's forward/aim direction). Alpha is a crisp 0/255 edge.
static func make_cone_texture(tex_size: int, half_angle_rad: float) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := float(tex_size) / 2.0
	var radius := float(tex_size) / 2.0
	for y in range(tex_size):
		for x in range(tex_size):
			var dx := float(x) + 0.5 - center
			var dy := float(y) + 0.5 - center
			var dist := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)  # 0 = +X (forward)
			var lit: bool = dist <= radius and absf(ang) <= half_angle_rad
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if lit else 0.0))
	return ImageTexture.create_from_image(img)


## Soft radial light texture: alpha 1 at the center, linearly to 0 at the edge.
static func make_radial_texture(tex_size: int) -> ImageTexture:
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := float(tex_size) / 2.0
	var radius := float(tex_size) / 2.0
	for y in range(tex_size):
		for x in range(tex_size):
			var dx := float(x) + 0.5 - center
			var dy := float(y) + 0.5 - center
			var dist := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - dist / radius, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## A closed square occluder polygon, size x size, centered on the origin.
static func make_square_occluder_polygon(size: float) -> OccluderPolygon2D:
	var half := size / 2.0
	var poly := OccluderPolygon2D.new()
	poly.closed = true
	poly.polygon = PackedVector2Array([
		Vector2(-half, -half),
		Vector2(half, -half),
		Vector2(half, half),
		Vector2(-half, half),
	])
	return poly
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s res://test/test_shooter_lighting.gd`
Expected: `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/shooter_lighting.gd test/test_shooter_lighting.gd
git commit -m "feat: add ShooterLighting cone/halo/occluder helpers"
```

---

## Task 3: Static occluder collection

**Files:**
- Modify: `scripts/shooter_lighting.gd`
- Test: `test/test_shooter_lighting.gd`

**Interfaces:**
- Consumes: `make_square_occluder_polygon` from Task 2.
- Produces:
  - `ShooterLighting.collect_static_occluder_positions(ground_layer: TileMapLayer, building_layer: TileMapLayer, props: Array[Node2D]) -> Array[Vector2]` — world-space centers of every occluding tile (`tile_type` `"building"` or `"edge"` on either layer) and every prop. Mirrors the detection in the old `FogShooter.cache_occluders()` / `cache_prop_occluders()`.
  - `ShooterLighting.build_static_occluders(parent: Node, positions: Array[Vector2], tile_size: float) -> int` — adds one `LightOccluder2D` (square polygon `tile_size`) at each position under `parent`; returns the count added.

Note: `collect_static_occluder_positions` needs real `TileMapLayer`s with a configured TileSet, so it is verified visually in Task 4, not unit-tested. `build_static_occluders` is unit-tested against an explicit position list (no tilemap required).

- [ ] **Step 1: Add the failing test**

Append to `test/test_shooter_lighting.gd` — add a call `_test_build_occluders()` inside `_init()` before the pass/fail print, and add this method:

```gdscript
func _test_build_occluders() -> void:
	var parent := Node2D.new()
	var positions: Array[Vector2] = [Vector2(64, 64), Vector2(128, 64), Vector2(64, 128)]
	var count := ShooterLighting.build_static_occluders(parent, positions, 64.0)
	_check("build returns count", count == 3)
	_check("occluder nodes added", parent.get_child_count() == 3)
	var first := parent.get_child(0)
	_check("child is LightOccluder2D", first is LightOccluder2D)
	_check("occluder positioned", (first as LightOccluder2D).global_position.is_equal_approx(Vector2(64, 64)))
	_check("occluder has polygon", (first as LightOccluder2D).occluder != null)
	parent.free()
```

Wire it into `_init()`:

```gdscript
	_test_square()
	_test_build_occluders()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path . -s res://test/test_shooter_lighting.gd`
Expected: FAIL — `build_static_occluders` not defined.

- [ ] **Step 3: Implement both functions**

Append to `scripts/shooter_lighting.gd`:

```gdscript
## World-space centers of every tile that blocks the flashlight (buildings and
## map-edge tiles on either layer) plus every prop. Mirrors the old FogShooter
## occluder detection.
static func collect_static_occluder_positions(
	ground_layer: TileMapLayer,
	building_layer: TileMapLayer,
	props: Array[Node2D]
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if ground_layer == null:
		return out
	for layer in [ground_layer, building_layer]:
		if layer == null:
			continue
		var used_rect: Rect2i = layer.get_used_rect()
		for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
			for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
				var coords := Vector2i(x, y)
				var td: TileData = layer.get_cell_tile_data(coords)
				if td == null:
					continue
				var tile_type: String = td.get_custom_data("tile_type")
				if tile_type == "building" or tile_type == "edge":
					out.append(layer.to_global(layer.map_to_local(coords)))
	for prop in props:
		out.append(prop.global_position)
	return out


## Spawn one square LightOccluder2D per position under `parent`. Returns count.
static func build_static_occluders(parent: Node, positions: Array[Vector2], tile_size: float) -> int:
	var poly := make_square_occluder_polygon(tile_size)
	for pos in positions:
		var occ := LightOccluder2D.new()
		occ.occluder = poly
		occ.global_position = pos
		parent.add_child(occ)
	return positions.size()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `godot --headless --path . -s res://test/test_shooter_lighting.gd`
Expected: `ALL TESTS PASSED`, exit 0.

Note: `global_position` is only valid after a node is inside the tree. In the test, `build_static_occluders` sets `global_position` after `add_child`, so the assertion holds. Keep that ordering in the implementation.

- [ ] **Step 5: Commit**

```bash
git add scripts/shooter_lighting.gd test/test_shooter_lighting.gd
git commit -m "feat: collect + build static light occluders"
```

---

## Task 4: Assemble lights in the world (HUMAN role)

**Files:**
- Modify: `scripts/shooter_lighting.gd` (add `setup`)
- Modify: `scenes/world/world.gd` (replace fog setup + per-frame update)
- Modify: `scenes/world/world.tscn` (remove `ShooterFogRect`)

**Interfaces:**
- Consumes: `Balance.FOG_SHOOTER`; `make_cone_texture`, `make_radial_texture`, `make_square_occluder_polygon`, `collect_static_occluder_positions`, `build_static_occluders`.
- Produces: `ShooterLighting.setup(world: Node2D, shooter: Node2D, ground_layer: TileMapLayer, building_layer: TileMapLayer, props: Array[Node2D]) -> void` — adds a `CanvasModulate` under `world`, a cone `PointLight2D` + radial `PointLight2D` under `shooter`, and the static occluders under `world`.

- [ ] **Step 1: Implement `setup` in ShooterLighting**

Append to `scripts/shooter_lighting.gd`:

```gdscript
## Build the full shooter fog: dark CanvasModulate over the world, a cone
## flashlight + radial halo parented to the shooter, and static occluders.
## Call once, on the HUMAN-role instance only.
static func setup(
	world: Node2D,
	shooter: Node2D,
	ground_layer: TileMapLayer,
	building_layer: TileMapLayer,
	props: Array[Node2D]
) -> void:
	var b: Dictionary = Balance.FOG_SHOOTER

	# 1. Darken the world (the "fog"). HUD is on its own CanvasLayer -> stays bright.
	var modulate := CanvasModulate.new()
	modulate.color = b.ambient_darkness
	world.add_child(modulate)

	# 2. Flashlight cone — child of the shooter so it tracks position + aim.
	var cone := PointLight2D.new()
	cone.texture = make_cone_texture(b.cone_tex_size, deg_to_rad(b.flashlight_half_angle_deg))
	cone.texture_scale = b.flashlight_range / (float(b.cone_tex_size) / 2.0)
	cone.energy = b.flashlight_energy
	cone.color = b.flashlight_color
	cone.shadow_enabled = b.shadows_enabled
	shooter.add_child(cone)

	# 3. Personal halo — small soft radial light, no aim dependence.
	var halo := PointLight2D.new()
	halo.texture = make_radial_texture(b.halo_tex_size)
	halo.texture_scale = b.halo_radius / (float(b.halo_tex_size) / 2.0)
	halo.energy = b.halo_energy
	halo.color = b.halo_color
	halo.shadow_enabled = b.shadows_enabled
	shooter.add_child(halo)

	# 4. Static occluders (buildings, edges, props).
	var tile_size: float = ground_layer.tile_set.tile_size.x
	var positions := collect_static_occluder_positions(ground_layer, building_layer, props)
	build_static_occluders(world, positions, tile_size)
```

- [ ] **Step 2: Rewrite `_setup_fog()` in world.gd**

Replace the entire `_setup_fog()` function (`scenes/world/world.gd:104-123`) with:

```gdscript
func _setup_fog() -> void:
	if not fog_enabled:
		return  # testing: fog disabled
	if GameState.role != GameState.Role.HUMAN:
		return  # only the shooter view gets the flashlight fog
	var props: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("occluders"):
		if node is Node2D:
			props.append(node)
	ShooterLighting.setup(self, shooter, ground_layer, building_layer, props)
```

- [ ] **Step 3: Remove the per-frame fog update**

In `scenes/world/world.gd`, replace the whole `_process()` function (`scenes/world/world.gd:124-148`) with nothing — delete it. The flashlight is a child of the shooter and needs no per-frame driving.

Also delete these now-unused declarations near the top of `world.gd`:
- `@onready var shooter_fog_rect: ColorRect = $HUDLayer/ShooterFogRect`
- `var fog_shooter: FogShooter`
- `var fog_texture: ImageTexture`

- [ ] **Step 4: Drop the `shooter_fog_rect` lines in `_apply_role()`**

In `_apply_role()` (`scenes/world/world.gd`), delete both lines that reference it:
- `shooter_fog_rect.visible = fog_enabled` (HUMAN branch)
- `shooter_fog_rect.visible = false` (ZOMBIE branch)

- [ ] **Step 5: Remove the ShooterFogRect node from world.tscn**

Using the godot-ai MCP: `scene_open` `res://scenes/world/world.tscn`, then `node_manage` op `delete` on `HUDLayer/ShooterFogRect`, then `scene_save`. (If editing the file directly instead, remove the `[node name="ShooterFogRect" ...]` block and any sub-resources only it references.)

- [ ] **Step 6: Verify it runs and looks right**

Run the game via godot-ai MCP `project_run` (or `godot --path .`). Drive the shooter and capture `editor_screenshot`.
Expected: the world is dark (per `ambient_darkness`); a hard-edged bright cone extends from the shooter in the aim direction and rotates as you aim; a soft halo surrounds the shooter; the beam stops at building walls casting straight shadows. No errors in the log about `shooter_fog_rect`, `FogShooter`, or `_process`.

- [ ] **Step 7: Commit**

```bash
git add scripts/shooter_lighting.gd scenes/world/world.gd scenes/world/world.tscn
git commit -m "feat: shooter flashlight fog via 2D lights + static occluders"
```

---

## Task 5: Dynamic occluders on moving entities

**Files:**
- Modify: `scenes/zombie/zombie.tscn`
- Modify: `scenes/zombie/master_zombie.tscn`
- Modify: `scenes/npc/npc_human.tscn`

**Interfaces:**
- Consumes: nothing new. Each entity gets a body-sized `LightOccluder2D` so it casts a moving shadow through the flashlight. Body radii: zombie 13, master zombie 13, npc 14 (px). Use `dynamic_occluder_radius` (14) from Balance as the square half-extent → a 28×28 square occluder, which comfortably covers all three.

- [ ] **Step 1: Add a LightOccluder2D to the zombie scene**

Using the godot-ai MCP: `scene_open` `res://scenes/zombie/zombie.tscn`. Add a child of the root `Zombie` node:
- `node_create` type `LightOccluder2D`, name `Occluder`, parent `Zombie`.
- Create an `OccluderPolygon2D` resource on its `occluder` property with a closed 28×28 square centered on origin — polygon points `[(-14,-14),(14,-14),(14,14),(-14,14)]`, `closed = true`.

Then `scene_save`.

(If editing the `.tscn` directly: add a `[sub_resource type="OccluderPolygon2D" id="Occ_dyn"]` with `polygon = PackedVector2Array(-14, -14, 14, -14, 14, 14, -14, 14)`, and a `[node name="Occluder" type="LightOccluder2D" parent="."]` with `occluder = SubResource("Occ_dyn")`.)

- [ ] **Step 2: Add the same occluder to the master zombie scene**

Repeat Step 1 for `res://scenes/zombie/master_zombie.tscn`, root node `MasterZombie`.

- [ ] **Step 3: Add the same occluder to the NPC scene**

Repeat Step 1 for `res://scenes/npc/npc_human.tscn`, root node `NPCHuman`.

- [ ] **Step 4: Verify dynamic shadows**

Run via `project_run`. Aim the flashlight so the beam passes a zombie and an NPC; capture `editor_screenshot`.
Expected: the zombie and NPC cast straight-line shadows that move with them and break the beam behind them.

- [ ] **Step 5: Commit**

```bash
git add scenes/zombie/zombie.tscn scenes/zombie/master_zombie.tscn scenes/npc/npc_human.tscn
git commit -m "feat: entities cast flashlight shadows via LightOccluder2D"
```

---

## Task 6: Delete the old fog system

**Files:**
- Delete: `scripts/fog_shooter.gd`, `scripts/fog_shooter.gd.uid`
- Delete: `shader/fog_of_war.gdshader`, `shader/fog_of_war.gdshader.uid`

**Interfaces:**
- Consumes: nothing. This removes dead code now that Task 4 replaced all references.

- [ ] **Step 1: Confirm there are no remaining references**

Run: `grep -rn "FogShooter\|fog_shooter\|fog_of_war\|shooter_fog_rect\|fog_texture" --include="*.gd" --include="*.tscn" .`
Expected: no matches outside the files being deleted. If `world.gd` or `world.tscn` still match, fix Task 4 before deleting.

- [ ] **Step 2: Delete the files**

```bash
git rm scripts/fog_shooter.gd scripts/fog_shooter.gd.uid shader/fog_of_war.gdshader shader/fog_of_war.gdshader.uid
```

- [ ] **Step 3: Verify the project still loads and runs**

Run via `project_run` (or `godot --headless --path . --quit-after 2`).
Expected: no load errors about missing `FogShooter` / `fog_of_war.gdshader`. Game starts; flashlight fog still works.

- [ ] **Step 4: Run the unit tests**

Run: `godot --headless --path . -s res://test/test_shooter_lighting.gd`
Expected: `ALL TESTS PASSED`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove old screen-space fog (FogShooter + shader)"
```

---

## Task 7: Visual tuning pass + docs

**Files:**
- Modify: `scripts/balance.gd` (tune `FOG_SHOOTER` values to taste)
- Modify: `CHANGELOG.md`, `ARCHITECTURE.md`, `PROJECT.md`

**Interfaces:**
- Consumes: the working system from Tasks 1-6.

- [ ] **Step 1: Tune the look**

Run the game. Adjust `Balance.FOG_SHOOTER` values and re-run until the look is right:
- `ambient_darkness` brighter/darker for how readable the unlit map is.
- `flashlight_range`, `flashlight_half_angle_deg`, `flashlight_energy` for beam reach/width/intensity.
- `halo_radius`, `halo_energy` for the personal bubble.
Capture a final `editor_screenshot` showing the tuned result.

- [ ] **Step 2: Update CHANGELOG.md**

Add an entry under the current phase summarizing: shooter fog of war rebuilt on Godot 2D lighting — dark CanvasModulate fog, hard-edged flashlight cone + personal halo, real straight-line shadows from buildings/props/zombies/NPCs; removed the old screen-space `FogShooter` + `fog_of_war.gdshader`.

- [ ] **Step 3: Update ARCHITECTURE.md and PROJECT.md**

In `ARCHITECTURE.md`, update the fog-of-war section: the shooter fog now lives in `scripts/shooter_lighting.gd` (2D lights + occluders), assembled from `world.gd::_setup_fog()` for the HUMAN role; the zombie-controller fog (`FogZombieController` / `fog_zc.gdshader`) is unchanged. In `PROJECT.md`, reflect the updated status if it tracks fog work.

- [ ] **Step 4: Commit**

```bash
git add scripts/balance.gd CHANGELOG.md ARCHITECTURE.md PROJECT.md
git commit -m "docs: record flashlight fog rebuild; tune light values"
```

---

## Self-Review

**Spec coverage:**
- Dark/grey opaque fog → Task 1 `ambient_darkness` + Task 4 CanvasModulate. ✓
- Flashlight reveals through fog where aiming → Task 4 cone `PointLight2D` parented to the auto-rotating shooter. ✓
- Hard-edged cone → Task 2 `make_cone_texture` (crisp 0/255 alpha). ✓
- Personal halo → Task 4 radial `PointLight2D`. ✓
- Blocked by buildings/props → Task 3 + Task 4 static occluders. ✓
- Blocked by zombies/NPCs/master → Task 5 dynamic occluders. ✓
- Straight-line shadows → Godot 2D shadow system (`shadow_enabled`). ✓
- Tunable opacity in balance.gd → Task 1. ✓
- Zombie-controller fog untouched → only HUMAN role builds lights (Task 4 guard). ✓
- Removals (ShooterFogRect, shader, FogShooter, per-frame update) → Tasks 4 & 6. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; commands have expected output.

**Type consistency:** `make_cone_texture(int, float)`, `make_radial_texture(int)`, `make_square_occluder_polygon(float)`, `collect_static_occluder_positions(TileMapLayer, TileMapLayer, Array[Node2D])`, `build_static_occluders(Node, Array[Vector2], float)`, `setup(Node2D, Node2D, TileMapLayer, TileMapLayer, Array[Node2D])` — names/signatures consistent across Tasks 2-4. `Balance.FOG_SHOOTER` keys defined in Task 1 are exactly those read in Task 4.
