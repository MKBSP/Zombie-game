# City Map Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zone-painted procedural city generator that bakes a ~94×94-tile map (4x area) into `world.tscn`, replacing the hand-painted 47×47 map.

**Architecture:** Pure-logic `CityGen` (RefCounted, headless-testable) turns a painted plan scene (Zones + Markers TileMapLayers) into ground/building tile dicts + prop placements + spawn tiles. An `EditorScript` bake tool writes the result into `world.tscn` as real tile data, prop nodes, and spawn markers. Runtime scripts derive map size from `get_used_rect()` so any future map size works untouched.

**Tech Stack:** Godot 4.6.3 GDScript. Spec: `docs/superpowers/specs/2026-07-19-city-map-generator-design.md`.

## Global Constraints

- **All game-file edits via the godot-ai MCP** (`script_create`, `script_patch`, `filesystem_manage`, `scene_*`) so the live editor stays in sync. Check `editor_state` first each session.
- **NEVER run headless Godot while the live editor is open** (wipes `.godot/`). Run `test/` scripts via MCP `test_run` if available; otherwise ask Mads to close the editor first, then run: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_city_gen.gd` (exit 0 = pass).
- **In test files, load helpers by path** (`load("res://scripts/city_gen.gd")`), never by bare `class_name` (headless parse gotcha).
- **No commits** unless Mads asks; **NEVER `git push`**. At the end, suggest a 1–2 phrase commit message (imperative, no attribution trailer).
- All tuning numbers live in `scripts/balance.gd` (`Balance.CITYGEN`). `CityGen` never reads the `Balance` autoload directly (headless tests can't see autoloads) — it takes a `cfg: Dictionary`; tests load balance by path: `load("res://scripts/balance.gd").CITYGEN`.
- Ground tile atlas x-coords in `resources/city_tileset.tres` (source 0, row 0): 0=road, 1=sidewalk, 2=grass, 3=building, 4=parking, 5=edge. Custom data `tile_type` strings: `"road"`, `"sidewalk"`, `"grass"`, `"building"`, `"parking"`, `"edge"`. Walkable = road/sidewalk/grass/parking. Tile size 64px.
- **New PNGs:** let the open editor import them on focus; never run headless `--import`. Commit the generated `.import` file when Mads commits.

---

### Task 1: CityGen base geometry (map size, roads, sidewalks, edge ring)

**Files:**
- Create: `scripts/city_gen.gd`
- Create: `test/test_city_gen.gd`
- Modify: `scripts/balance.gd` (add `CITYGEN` block after `FOG_ZC`)

**Interfaces:**
- Produces: `CityGen.map_size(w, h, cfg) -> Vector2i`, `CityGen.block_origin(cell, cfg) -> Vector2i`, `CityGen.interior_rect(cell, cfg) -> Rect2i`, `CityGen.paint_base(w, h, cfg) -> Dictionary` ({Vector2i: int tile-id}), tile-id consts `T_ROAD..T_EDGE`, zone consts `Z_RES..Z_EMPTY, M_SHOOTER, M_ZOMBIE`.
- Geometry contract (block_tiles=10, road_w=2): map = `w*10 + 4` tiles wide (1 edge + blocks + 2 closing road + 1 edge). Block local layout: cols/rows 0–1 road, 2 sidewalk, 3–8 interior (6×6), 9 sidewalk. 9×9 plan → 94×94 tiles.

- [ ] **Step 1: Add `CITYGEN` to `scripts/balance.gd`** (via MCP `script_patch`), after the `FOG_ZC` const:

```gdscript
# --- City map generator (bake-time only; see docs/map_generator_guide.md) --
# Consumed by tools/bake_city_map.gd, which passes it into CityGen as `cfg`.
const CITYGEN := {
	block_tiles = 10,        # tiles per plan cell: road 2 + sidewalk 1 + interior 6 + sidewalk 1
	road_w = 2,
	tile_px = 64.0,
	res_min_lot = 3,         # BSP stop size for residential lots
	com_split_chance = 0.5,  # chance a commercial block holds 2+ buildings instead of 1
	road_car_chance = 0.06,  # per road tile (max 2 cars per block's roads)
	parking_fenced = true,
	car_scene = "res://scenes/props/prop_car.tscn",
	fence_scene = "res://scenes/props/prop_fence.tscn",
	props = {},              # per-zone palettes — filled in Task 4
}
```

- [ ] **Step 2: Write the failing test** — create `test/test_city_gen.gd` (via MCP `script_create`):

```gdscript
extends SceneTree

## Headless unit test for CityGen. Run via MCP test_run, or with the editor
## CLOSED:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_city_gen.gd

var _failures := 0
var _CG = load("res://scripts/city_gen.gd")
var _cfg: Dictionary = load("res://scripts/balance.gd").CITYGEN


func _init() -> void:
	_test_geometry()
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _test_geometry() -> void:
	_check("map_size 9x9 is 94x94", _CG.map_size(9, 9, _cfg) == Vector2i(94, 94))
	_check("map_size 1x2 is 14x24", _CG.map_size(1, 2, _cfg) == Vector2i(14, 24))
	_check("block_origin (0,0)", _CG.block_origin(Vector2i(0, 0), _cfg) == Vector2i(1, 1))
	_check("block_origin (2,1)", _CG.block_origin(Vector2i(2, 1), _cfg) == Vector2i(21, 11))
	_check("interior (0,0) is 6x6 at (4,4)",
		_CG.interior_rect(Vector2i(0, 0), _cfg) == Rect2i(4, 4, 6, 6))

	var g: Dictionary = _CG.paint_base(2, 1, _cfg)
	var size: Vector2i = _CG.map_size(2, 1, _cfg)  # 24x14
	_check("paint_base covers every tile", g.size() == size.x * size.y)
	_check("corner is edge", g[Vector2i(0, 0)] == _CG.T_EDGE)
	_check("far corner is edge", g[Vector2i(size.x - 1, size.y - 1)] == _CG.T_EDGE)
	_check("block NW corner is road", g[Vector2i(1, 1)] == _CG.T_ROAD)
	_check("second road row", g[Vector2i(5, 2)] == _CG.T_ROAD)
	_check("sidewalk ring row", g[Vector2i(5, 3)] == _CG.T_SIDEWALK)
	_check("interior is grass", g[Vector2i(5, 5)] == _CG.T_GRASS)
	_check("south sidewalk of block", g[Vector2i(5, 10)] == _CG.T_SIDEWALK)
	_check("closing road strip east", g[Vector2i(size.x - 2, 5)] == _CG.T_ROAD)
	_check("closing road strip south", g[Vector2i(5, size.y - 2)] == _CG.T_ROAD)
	_check("second block west road is shared", g[Vector2i(11, 5)] == _CG.T_ROAD)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
```

- [ ] **Step 3: Run the test — expect FAIL** (script missing / methods undefined). Use MCP `test_run`, else headless with editor closed. Expected: parse error or FAIL lines, nonzero exit.

- [ ] **Step 4: Implement** — create `scripts/city_gen.gd` (via MCP `script_create`):

```gdscript
extends RefCounted
## CityGen — pure city-map generation: painted plan grid -> ground/building
## tiles + prop placements + spawn tiles. No scene or autoload dependencies so
## headless tests can load it by path. All tunables arrive via `cfg`
## (Balance.CITYGEN in real use). See docs/map_generator_guide.md.

## Ground tile atlas x-coords in resources/city_tileset.tres (source 0, row 0).
const T_ROAD := 0
const T_SIDEWALK := 1
const T_GRASS := 2
const T_BUILDING := 3
const T_PARKING := 4
const T_EDGE := 5

## Zone / marker ids = atlas x-coords in resources/plan_tileset.tres.
const Z_RES := 0
const Z_COM := 1
const Z_PARK := 2
const Z_PARKING := 3
const Z_EMPTY := 4
const M_SHOOTER := 5
const M_ZOMBIE := 6

const WALKABLE: Array[int] = [T_ROAD, T_SIDEWALK, T_GRASS, T_PARKING]
const TYPE_NAMES := {
	T_ROAD: "road", T_SIDEWALK: "sidewalk", T_GRASS: "grass",
	T_BUILDING: "building", T_PARKING: "parking", T_EDGE: "edge",
}


## Total map size in tiles for a w x h plan:
## 1 edge + w*block_tiles + closing road (road_w) + 1 edge per axis.
static func map_size(w: int, h: int, cfg: Dictionary) -> Vector2i:
	var bt: int = cfg.block_tiles
	var rw: int = cfg.road_w
	return Vector2i(w * bt + rw + 2, h * bt + rw + 2)


## Top-left map tile of a plan cell's block. Local (0,0) of a block is its
## NW road corner (roads sit on each block's north and west sides).
static func block_origin(cell: Vector2i, cfg: Dictionary) -> Vector2i:
	return Vector2i(1, 1) + cell * int(cfg.block_tiles)


## Interior rect of a block: inside the road strip and sidewalk ring.
static func interior_rect(cell: Vector2i, cfg: Dictionary) -> Rect2i:
	var bt: int = cfg.block_tiles
	var inset: int = int(cfg.road_w) + 1
	var o := block_origin(cell, cfg)
	return Rect2i(o + Vector2i(inset, inset), Vector2i(bt - inset - 1, bt - inset - 1))


## Base ground for the whole map: edge ring, shared road grid, sidewalk rings,
## grass interiors (zones repaint interiors later).
static func paint_base(w: int, h: int, cfg: Dictionary) -> Dictionary:
	var bt: int = cfg.block_tiles
	var rw: int = cfg.road_w
	var size := map_size(w, h, cfg)
	var ground := {}
	for y in size.y:
		for x in size.x:
			var p := Vector2i(x, y)
			if x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
				ground[p] = T_EDGE
				continue
			var ix := x - 1
			var iy := y - 1
			if ix >= w * bt or iy >= h * bt:
				ground[p] = T_ROAD  # closing road strip along the far south/east
				continue
			var lx := ix % bt
			var ly := iy % bt
			if lx < rw or ly < rw:
				ground[p] = T_ROAD
			elif lx == rw or ly == rw or lx == bt - 1 or ly == bt - 1:
				ground[p] = T_SIDEWALK
			else:
				ground[p] = T_GRASS
	return ground
```

- [ ] **Step 5: Run the test — expect PASS** (all geometry checks, exit 0).

---

### Task 2: BSP lots + residential/commercial buildings

**Files:**
- Modify: `scripts/city_gen.gd`
- Modify: `test/test_city_gen.gd`

**Interfaces:**
- Consumes: Task 1 geometry helpers.
- Produces: `CityGen.bsp_lots(rect, rng, min_side) -> Array[Rect2i]`, `CityGen.lot_building(lot) -> Rect2i`, `CityGen.fill_zone(ground, buildings, cell, zone, rng, cfg) -> void` (mutates dicts; buildings dict {Vector2i: T_BUILDING}).
- Contract: buildings never overwrite road/sidewalk (only interior tiles); every lot keeps a 1-tile alley on its south and east; buildings smaller than 2×2 are skipped.

- [ ] **Step 1: Add failing tests** to `test/test_city_gen.gd` — add `_test_lots()` and call it from `_init()` after `_test_geometry()`:

```gdscript
func _test_lots() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rect := Rect2i(4, 4, 6, 6)
	var lots: Array[Rect2i] = _CG.bsp_lots(rect, rng, 3)
	_check("bsp produces >= 1 lot", lots.size() >= 1)
	var area := 0
	var inside := true
	for lot in lots:
		area += lot.size.x * lot.size.y
		if not rect.encloses(lot):
			inside = false
	_check("lots tile the rect exactly", area == 36)
	_check("lots stay inside the rect", inside)
	_check("lot_building keeps 1-tile alley",
		_CG.lot_building(Rect2i(4, 4, 3, 6)) == Rect2i(4, 4, 2, 5))

	# Deterministic: same seed twice -> identical lots.
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 42
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 42
	_check("bsp deterministic", str(_CG.bsp_lots(rect, rng_a, 3)) == str(_CG.bsp_lots(rect, rng_b, 3)))

	# Residential fill: buildings only on interior tiles, never on road/sidewalk.
	var ground: Dictionary = _CG.paint_base(1, 1, _cfg)
	var buildings := {}
	var rng_c := RandomNumberGenerator.new()
	rng_c.seed = 3
	_CG.fill_zone(ground, buildings, Vector2i(0, 0), _CG.Z_RES, rng_c, _cfg)
	_check("residential placed >= 1 building tile", buildings.size() >= 1)
	var interior: Rect2i = _CG.interior_rect(Vector2i(0, 0), _cfg)
	var ok := true
	for p in buildings:
		if not interior.has_point(p):
			ok = false
	_check("buildings only inside interior", ok)

	# Commercial fill: interior ground becomes sidewalk, big building appears.
	var ground2: Dictionary = _CG.paint_base(1, 1, _cfg)
	var buildings2 := {}
	var rng_d := RandomNumberGenerator.new()
	rng_d.seed = 3
	_CG.fill_zone(ground2, buildings2, Vector2i(0, 0), _CG.Z_COM, rng_d, _cfg)
	_check("commercial interior ground is sidewalk",
		ground2[interior.position] == _CG.T_SIDEWALK)
	_check("commercial placed >= 4 building tiles", buildings2.size() >= 4)
```

- [ ] **Step 2: Run — expect FAIL** (`bsp_lots` not defined).

- [ ] **Step 3: Implement** — append to `scripts/city_gen.gd`:

```gdscript
## Recursively split `rect` into lots. A side splits while it can hold two
## `min_side` halves; split positions come from `rng` (deterministic per seed).
static func bsp_lots(rect: Rect2i, rng: RandomNumberGenerator, min_side: int) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	_bsp(rect, rng, min_side, out)
	return out


static func _bsp(rect: Rect2i, rng: RandomNumberGenerator, min_side: int, out: Array[Rect2i]) -> void:
	var can_x := rect.size.x >= min_side * 2
	var can_y := rect.size.y >= min_side * 2
	if not can_x and not can_y:
		out.append(rect)
		return
	var split_x := can_x
	if can_x and can_y:
		if rect.size.x == rect.size.y:
			split_x = rng.randf() < 0.5
		else:
			split_x = rect.size.x > rect.size.y
	if split_x:
		var cut := rng.randi_range(min_side, rect.size.x - min_side)
		_bsp(Rect2i(rect.position, Vector2i(cut, rect.size.y)), rng, min_side, out)
		_bsp(Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y)), rng, min_side, out)
	else:
		var cut := rng.randi_range(min_side, rect.size.y - min_side)
		_bsp(Rect2i(rect.position, Vector2i(rect.size.x, cut)), rng, min_side, out)
		_bsp(Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut)), rng, min_side, out)


## Building footprint for a lot: the lot minus a 1-tile alley on its south and
## east sides (adjacent lots' buildings therefore never touch).
static func lot_building(lot: Rect2i) -> Rect2i:
	return Rect2i(lot.position, lot.size - Vector2i(1, 1))


## Repaint one block's interior for its zone and add building tiles.
static func fill_zone(ground: Dictionary, buildings: Dictionary, cell: Vector2i, zone: int, rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var interior := interior_rect(cell, cfg)
	match zone:
		Z_RES:
			for lot in bsp_lots(interior, rng, int(cfg.res_min_lot)):
				_paint_building(buildings, lot_building(lot))
		Z_COM:
			_fill_rect(ground, interior, T_SIDEWALK)
			var lots: Array[Rect2i] = [interior]
			if rng.randf() < float(cfg.com_split_chance):
				lots = bsp_lots(interior, rng, int(cfg.res_min_lot))
			for lot in lots:
				_paint_building(buildings, lot_building(lot))
		Z_PARK:
			pass  # stays grass; props (trees/statue) come from the palette
		Z_PARKING:
			_fill_rect(ground, interior, T_PARKING)
		Z_EMPTY:
			pass  # stays grass


static func _paint_building(buildings: Dictionary, b: Rect2i) -> void:
	if b.size.x < 2 or b.size.y < 2:
		return  # slivers stay open ground
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			buildings[Vector2i(x, y)] = T_BUILDING


static func _fill_rect(d: Dictionary, r: Rect2i, t: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			d[Vector2i(x, y)] = t
```

- [ ] **Step 4: Run — expect PASS** (all Task 1 + Task 2 checks, exit 0).

---

### Task 3: generate() — plan parsing, markers, connectivity validation

**Files:**
- Modify: `scripts/city_gen.gd`
- Modify: `test/test_city_gen.gd`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `CityGen.generate(zones: Dictionary, markers: Dictionary, cfg: Dictionary, seed_val: int) -> Dictionary` with keys: `ground: {Vector2i:int}`, `buildings: {Vector2i:int}`, `props: Array[Dictionary]`, `shooter_tile: Vector2i`, `zombie_tile: Vector2i`, `size: Vector2i`, `errors: Array[String]`. Inputs: `zones` = {plan cell: zone id}, `markers` = {plan cell: M_SHOOTER|M_ZOMBIE}. Also `CityGen.is_walkable(ground, buildings, p) -> bool`, `CityGen.connectivity_ok(ground, buildings, start) -> bool`.
- Contract: empty `errors` means the map is valid and fully connected. Spawn tiles are the marked blocks' NW road corners. Plan cells are normalized (any painted offset works). A hole inside the plan's bounding rect is an error.

- [ ] **Step 1: Add failing tests** — add `_test_generate()`; call from `_init()`:

```gdscript
func _make_plan(w: int, h: int, zone: int) -> Dictionary:
	var plan := {}
	for y in h:
		for x in w:
			plan[Vector2i(x, y)] = zone
	return plan


func _test_generate() -> void:
	var zones := _make_plan(3, 3, _CG.Z_RES)
	zones[Vector2i(1, 1)] = _CG.Z_PARK
	var markers := { Vector2i(0, 2): _CG.M_SHOOTER, Vector2i(2, 0): _CG.M_ZOMBIE }
	var r: Dictionary = _CG.generate(zones, markers, _cfg, 1234)
	_check("no errors on valid plan", r.errors.is_empty())
	_check("size is 34x34", r.size == Vector2i(34, 34))
	_check("shooter tile is block (0,2) NW road", r.shooter_tile == Vector2i(1, 21))
	_check("zombie tile is block (2,0) NW road", r.zombie_tile == Vector2i(21, 1))
	_check("spawn tiles are road", r.ground[r.shooter_tile] == _CG.T_ROAD
		and r.ground[r.zombie_tile] == _CG.T_ROAD)
	_check("connectivity holds", _CG.connectivity_ok(r.ground, r.buildings, r.shooter_tile))

	# Determinism: same inputs -> identical output.
	var r2: Dictionary = _CG.generate(zones, markers, _cfg, 1234)
	_check("generate deterministic", str(r.ground) == str(r2.ground)
		and str(r.buildings) == str(r2.buildings) and str(r.props) == str(r2.props))
	var r3: Dictionary = _CG.generate(zones, markers, _cfg, 99)
	_check("different seed differs", str(r.buildings) != str(r3.buildings))

	# Plan offset doesn't matter (normalization).
	var shifted := {}
	for c in zones:
		shifted[c + Vector2i(5, 7)] = zones[c]
	var mshift := {}
	for c in markers:
		mshift[c + Vector2i(5, 7)] = markers[c]
	var r4: Dictionary = _CG.generate(shifted, mshift, _cfg, 1234)
	_check("offset plan normalizes", str(r4.ground) == str(r.ground))

	# Error cases.
	var holey := _make_plan(2, 2, _CG.Z_RES)
	holey.erase(Vector2i(1, 0))
	_check("hole in plan is an error",
		not _CG.generate(holey, markers, _cfg, 1).errors.is_empty())
	_check("missing markers is an error",
		not _CG.generate(_make_plan(2, 2, _CG.Z_RES), {}, _cfg, 1).errors.is_empty())
	var g_ok: Dictionary = { Vector2i(2, 2): _CG.T_ROAD, Vector2i(3, 2): _CG.T_ROAD, Vector2i(9, 9): _CG.T_ROAD }
	_check("disconnected ground fails connectivity",
		not _CG.connectivity_ok(g_ok, {}, Vector2i(2, 2)))
```

- [ ] **Step 2: Run — expect FAIL** (`generate` not defined).

- [ ] **Step 3: Implement** — append to `scripts/city_gen.gd`:

```gdscript
## Full pipeline: plan cells + markers -> tiles, spawns, props, validation.
## Returns { ground, buildings, props, shooter_tile, zombie_tile, size, errors }.
## Non-empty `errors` means the result must not be baked.
static func generate(zones: Dictionary, markers: Dictionary, cfg: Dictionary, seed_val: int) -> Dictionary:
	var res := {
		ground = {}, buildings = {}, props = [],
		shooter_tile = Vector2i(-1, -1), zombie_tile = Vector2i(-1, -1),
		size = Vector2i.ZERO, errors = [] as Array[String],
	}
	if zones.is_empty():
		res.errors.append("plan has no zone cells")
		return res

	# Normalize so the painted rect's top-left cell becomes (0,0).
	var bounds := _cells_bounds(zones.keys())
	var plan := {}
	for c in zones:
		plan[c - bounds.position] = zones[c]
	var marks := {}
	for c in markers:
		marks[c - bounds.position] = markers[c]
	var w := bounds.size.x
	var h := bounds.size.y

	for y in h:
		for x in w:
			if not plan.has(Vector2i(x, y)):
				res.errors.append("plan hole at cell (%d,%d) — paint every cell of the rectangle" % [x, y])

	var shooter_cells: Array = []
	var zombie_cells: Array = []
	for c in marks:
		if marks[c] == M_SHOOTER:
			shooter_cells.append(c)
		elif marks[c] == M_ZOMBIE:
			zombie_cells.append(c)
	if shooter_cells.size() != 1:
		res.errors.append("need exactly 1 shooter-spawn marker, found %d" % shooter_cells.size())
	if zombie_cells.size() != 1:
		res.errors.append("need exactly 1 zombie-spawn marker, found %d" % zombie_cells.size())
	if not res.errors.is_empty():
		return res

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	res.size = map_size(w, h, cfg)
	res.ground = paint_base(w, h, cfg)
	var cells: Array = plan.keys()
	cells.sort()  # deterministic fill order regardless of dict order
	for c in cells:
		fill_zone(res.ground, res.buildings, c, plan[c], rng, cfg)
	res.shooter_tile = block_origin(shooter_cells[0], cfg)
	res.zombie_tile = block_origin(zombie_cells[0], cfg)
	for c in cells:
		place_props(res, c, plan[c], rng, cfg)
	if not connectivity_ok(res.ground, res.buildings, res.shooter_tile):
		res.errors.append("connectivity check failed: some walkable tiles are unreachable")
	return res


static func _cells_bounds(cells: Array) -> Rect2i:
	var r := Rect2i(cells[0], Vector2i.ONE)
	for c in cells:
		r = r.expand(c).expand(c + Vector2i.ONE)
	return r


static func is_walkable(ground: Dictionary, buildings: Dictionary, p: Vector2i) -> bool:
	return ground.get(p, -1) in WALKABLE and not buildings.has(p)


## Flood fill from `start`: true when every walkable tile is reachable.
static func connectivity_ok(ground: Dictionary, buildings: Dictionary, start: Vector2i) -> bool:
	if not is_walkable(ground, buildings, start):
		return false
	var total := 0
	for p in ground:
		if is_walkable(ground, buildings, p):
			total += 1
	var seen := { start: true }
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = p + d
			if not seen.has(n) and is_walkable(ground, buildings, n):
				seen[n] = true
				queue.append(n)
	return seen.size() == total


## Placeholder until Task 4 — keeps generate() callable.
static func place_props(_res: Dictionary, _cell: Vector2i, _zone: int, _rng: RandomNumberGenerator, _cfg: Dictionary) -> void:
	pass
```

- [ ] **Step 4: Run — expect PASS** (exit 0).

---

### Task 4: Prop placement (palettes, road cars, statue, fence ring)

**Files:**
- Modify: `scripts/city_gen.gd` (replace the `place_props` placeholder)
- Modify: `scripts/balance.gd` (fill `CITYGEN.props`)
- Modify: `test/test_city_gen.gd`

**Interfaces:**
- Consumes: `generate()` from Task 3 (calls `place_props` per block).
- Produces: `res.props` entries: `{ scene: String, pos: Vector2 (world px), rot: float }`. Palette entry shape: `{ scene, count_min, count_max, on: Array[String of tile_type], jitter_px, min_sep_px }`, or `{ scene, at_center = true, chance }`.

- [ ] **Step 1: Fill `CITYGEN.props` in `scripts/balance.gd`** (replace `props = {},`):

```gdscript
	props = {
		residential = [
			{ scene = "res://scenes/props/prop_tree.tscn",     count_min = 1, count_max = 3, on = ["grass"],    jitter_px = 14.0, min_sep_px = 90.0 },
			{ scene = "res://scenes/props/prop_dumpster.tscn", count_min = 0, count_max = 1, on = ["sidewalk"], jitter_px = 6.0,  min_sep_px = 90.0 },
		],
		commercial = [
			{ scene = "res://scenes/props/prop_dumpster.tscn", count_min = 0, count_max = 2, on = ["sidewalk"], jitter_px = 6.0, min_sep_px = 90.0 },
		],
		park = [
			{ scene = "res://scenes/props/prop_tree.tscn",   count_min = 3, count_max = 6, on = ["grass"], jitter_px = 14.0, min_sep_px = 80.0 },
			{ scene = "res://scenes/props/prop_statue.tscn", at_center = true, chance = 0.35 },
		],
		parking = [
			{ scene = "res://scenes/props/prop_car.tscn", count_min = 1, count_max = 4, on = ["parking"], jitter_px = 8.0, min_sep_px = 110.0 },
		],
		empty = [],
	},
```

- [ ] **Step 2: Add failing tests** — add `_test_props()`; call from `_init()`:

```gdscript
func _test_props() -> void:
	var zones := _make_plan(2, 2, _CG.Z_PARK)
	zones[Vector2i(1, 1)] = _CG.Z_PARKING
	var markers := { Vector2i(0, 0): _CG.M_SHOOTER, Vector2i(1, 0): _CG.M_ZOMBIE }
	var r: Dictionary = _CG.generate(zones, markers, _cfg, 5)
	_check("props were placed", r.props.size() > 0)

	var tp: float = _cfg.tile_px
	var trees := 0
	var fences := 0
	var legal := true
	for p in r.props:
		if String(p.scene).contains("tree"):
			trees += 1
			var t := Vector2i((p.pos / tp).floor())
			if r.ground.get(t, -1) != _CG.T_GRASS or r.buildings.has(t):
				legal = false
		elif String(p.scene).contains("fence"):
			fences += 1
	_check("parks grew trees", trees >= 6)  # 3 park blocks x count_min 3... at least 3 each is not guaranteed by tries; >=6 is safe
	_check("trees stand on grass", legal)
	_check("parking block got a fence ring", fences > 0)

	# Determinism again, now with props in play.
	var r2: Dictionary = _CG.generate(zones, markers, _cfg, 5)
	_check("props deterministic", str(r.props) == str(r2.props))
```

- [ ] **Step 3: Run — expect FAIL** (no props placed; placeholder still active).

- [ ] **Step 4: Implement** — replace the `place_props` placeholder in `scripts/city_gen.gd`:

```gdscript
const ZONE_KEYS := {
	Z_RES: "residential", Z_COM: "commercial", Z_PARK: "park",
	Z_PARKING: "parking", Z_EMPTY: "empty",
}


## Palette-driven props for one block: zone palette entries, then road cars,
## then a fence ring on parking blocks. Positions are world px (tile centers
## + jitter); everything draws from `rng` in a fixed order for determinism.
static func place_props(res: Dictionary, cell: Vector2i, zone: int, rng: RandomNumberGenerator, cfg: Dictionary) -> void:
	var tp: float = float(cfg.tile_px)
	var interior := interior_rect(cell, cfg)
	var placed: Array[Vector2] = []

	for e in cfg.props[ZONE_KEYS[zone]]:
		if e.get("at_center", false):
			if rng.randf() < float(e.chance):
				var center := (Vector2(interior.position) + Vector2(interior.size) * 0.5) * tp
				res.props.append({ scene = e.scene, pos = center, rot = 0.0 })
				placed.append(center)
			continue
		var want: int = rng.randi_range(int(e.count_min), int(e.count_max))
		var tries: int = want * 12
		while want > 0 and tries > 0:
			tries -= 1
			# Sample the interior plus its sidewalk ring (1 tile out).
			var t := Vector2i(
				rng.randi_range(interior.position.x - 1, interior.end.x),
				rng.randi_range(interior.position.y - 1, interior.end.y))
			if res.buildings.has(t):
				continue
			if not TYPE_NAMES.get(res.ground.get(t, -1), "") in e.on:
				continue
			var pos := (Vector2(t) + Vector2(0.5, 0.5)) * tp + Vector2(
				rng.randf_range(-float(e.jitter_px), float(e.jitter_px)),
				rng.randf_range(-float(e.jitter_px), float(e.jitter_px)))
			if _too_close(pos, placed, float(e.min_sep_px)):
				continue
			placed.append(pos)
			res.props.append({ scene = e.scene, pos = pos, rot = 0.0 })
			want -= 1

	_place_road_cars(res, cell, rng, cfg, placed)
	if zone == Z_PARKING and bool(cfg.get("parking_fenced", true)):
		res.props.append_array(_fence_ring(interior, tp, String(cfg.fence_scene)))


static func _place_road_cars(res: Dictionary, cell: Vector2i, rng: RandomNumberGenerator, cfg: Dictionary, placed: Array[Vector2]) -> void:
	var tp: float = float(cfg.tile_px)
	var bt: int = cfg.block_tiles
	var rw: int = cfg.road_w
	var o := block_origin(cell, cfg)
	var cars := 0
	for ly in bt:
		for lx in bt:
			if cars >= 2:
				return
			if lx >= rw and ly >= rw:
				continue  # only this block's north/west road strips
			if rng.randf() >= float(cfg.road_car_chance):
				continue
			var t := o + Vector2i(lx, ly)
			if res.ground.get(t, -1) != T_ROAD:
				continue
			var pos := (Vector2(t) + Vector2(0.5, 0.5)) * tp
			if _too_close(pos, placed, 140.0):
				continue
			var horizontal := ly < rw
			placed.append(pos)
			res.props.append({
				scene = cfg.car_scene, pos = pos,
				rot = (0.0 if horizontal else PI * 0.5) + rng.randf_range(-0.12, 0.12),
			})
			cars += 1


## Fence posts along a parking block's interior boundary, with a 2-tile
## entrance gap in the middle of the north side. Horizontal segments rot 0,
## vertical rot PI/2, positioned on the tile-edge lines.
static func _fence_ring(interior: Rect2i, tp: float, fence_scene: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var gap0: int = interior.position.x + interior.size.x / 2 - 1
	for x in range(interior.position.x, interior.end.x):
		if x != gap0 and x != gap0 + 1:
			out.append({ scene = fence_scene, pos = Vector2(x + 0.5, interior.position.y) * tp, rot = 0.0 })
		out.append({ scene = fence_scene, pos = Vector2(x + 0.5, interior.end.y) * tp, rot = 0.0 })
	for y in range(interior.position.y, interior.end.y):
		out.append({ scene = fence_scene, pos = Vector2(interior.position.x, y + 0.5) * tp, rot = PI * 0.5 })
		out.append({ scene = fence_scene, pos = Vector2(interior.end.x, y + 0.5) * tp, rot = PI * 0.5 })
	return out


static func _too_close(pos: Vector2, placed: Array[Vector2], min_sep: float) -> bool:
	for q in placed:
		if pos.distance_to(q) < min_sep:
			return true
	return false
```

- [ ] **Step 5: Run — expect PASS** (full suite, exit 0). If "parks grew trees" flakes below 6 with this seed, lower the threshold to `>= 3` — the guarantee under test is "parks get trees", not an exact count.

---

### Task 5: Plan tileset + demo plan scene

**Files:**
- Create: `textures/plan_tiles.png` (generated; editor imports it)
- Create: `resources/plan_tileset.tres`
- Create: `tools/make_demo_plan.gd` (EditorScript)
- Create: `maps/plans/city_a.tscn` (output of the EditorScript)

**Interfaces:**
- Produces: plan scenes whose `Zones`/`Markers` TileMapLayers use source 0, atlas `(zone_id, 0)` with zone ids matching `CityGen.Z_* / M_*`. Task 6's bake tool reads exactly this structure.

- [ ] **Step 1: Generate the tile strip PNG** — 7 solid 64×64 squares in one 448×64 image (order = zone ids): residential yellow, commercial blue, park green, parking gray, empty brown, shooter-marker white, zombie-marker red. Run from the repo root:

```bash
python3 - <<'EOF'
import struct, zlib
colors = [(217,194,74),(74,127,217),(74,217,106),(138,138,138),(122,92,58),(255,255,255),(217,74,74)]
w, h = 448, 64
rows = b""
for y in range(h):
    row = b"\x00"
    for x in range(w):
        c = colors[x // 64]
        # 4px dark border inside each tile so painted cells read as cells
        lx, ly = x % 64, y
        if lx < 4 or lx >= 60 or ly < 4 or ly >= 60:
            c = (int(c[0]*0.55), int(c[1]*0.55), int(c[2]*0.55))
        row += bytes(c)
    rows += row
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(rows))
png += chunk(b"IEND", b"")
open("textures/plan_tiles.png", "wb").write(png)
print("wrote textures/plan_tiles.png")
EOF
```

Then focus the Godot editor once so it imports the PNG (per gotchas — no headless `--import`). Verify `textures/plan_tiles.png.import` appears.

- [ ] **Step 2: Create `resources/plan_tileset.tres`** (via MCP `filesystem_manage` / file write; path-only ext_resource, no uid needed):

```
[gd_resource type="TileSet" format=3]

[ext_resource type="Texture2D" path="res://textures/plan_tiles.png" id="1"]

[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_plan"]
texture = ExtResource("1")
texture_region_size = Vector2i(64, 64)
0:0/0 = 0
1:0/0 = 0
2:0/0 = 0
3:0/0 = 0
4:0/0 = 0
5:0/0 = 0
6:0/0 = 0

[resource]
tile_size = Vector2i(64, 64)
sources/0 = SubResource("TileSetAtlasSource_plan")
```

- [ ] **Step 3: Create `tools/make_demo_plan.gd`** — builds and saves the demo 9×9 plan programmatically (also serves as the reference for plan-scene structure):

```gdscript
@tool
extends EditorScript
## Builds maps/plans/city_a.tscn — the demo 9x9 city plan. Run from the
## editor: File -> Run. Chars: R residential, C commercial, P park,
## K parking, E empty. Markers painted separately below.

const LAYOUT := [
	"RRCCCRRKR",
	"RRCCCRRRR",
	"PPCCCRRRR",
	"PPRRRRREE",
	"RRRKRRRPP",
	"RCRRRRRPP",
	"RCRRERRRR",
	"RRRRERRCC",
	"RRPPRRRCC",
]
const ZONE_OF := { "R": 0, "C": 1, "P": 2, "K": 3, "E": 4 }
const SHOOTER_CELL := Vector2i(1, 7)
const ZOMBIE_CELL := Vector2i(7, 1)


func _run() -> void:
	var ts: TileSet = load("res://resources/plan_tileset.tres")
	var root := Node2D.new()
	root.name = "CityPlan"
	var zones := TileMapLayer.new()
	zones.name = "Zones"
	zones.tile_set = ts
	root.add_child(zones)
	zones.owner = root
	var markers := TileMapLayer.new()
	markers.name = "Markers"
	markers.tile_set = ts
	markers.modulate = Color(1, 1, 1, 0.6)  # zone color shows through
	root.add_child(markers)
	markers.owner = root

	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			zones.set_cell(Vector2i(x, y), 0, Vector2i(ZONE_OF[LAYOUT[y][x]], 0))
	markers.set_cell(SHOOTER_CELL, 0, Vector2i(5, 0))
	markers.set_cell(ZOMBIE_CELL, 0, Vector2i(6, 0))

	DirAccess.make_dir_recursive_absolute("res://maps/plans")
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, "res://maps/plans/city_a.tscn")
	print("make_demo_plan: saved city_a.tscn, err=%d" % err)
```

- [ ] **Step 4: Run it in the live editor** (File → Run with the script open, or MCP equivalent). Expected output in editor log: `make_demo_plan: saved city_a.tscn, err=0`.

- [ ] **Step 5: Verify** — open `maps/plans/city_a.tscn` in the editor: a 9×9 colored grid with two marker tiles, paintable with the normal TileMap tools.

---

### Task 6: Bake tool — write the generated map into world.tscn

**Files:**
- Create: `tools/bake_city_map.gd` (EditorScript)
- Modifies (as data, when run): `scenes/world/world.tscn`

**Interfaces:**
- Consumes: `CityGen.generate(zones, markers, cfg, seed)` (Task 3/4 result shape), plan scene structure from Task 5, `Balance.CITYGEN`.
- Produces in `world.tscn`: repainted `GroundLayer`/`BuildingLayer` (position reset to `(0,0)` — GroundLayer currently sits at `(1,0)`), a rebuilt `Props` Node2D whose children are instanced prop scenes, and `SpawnMarkers` Node2D with `ShooterSpawn`/`ZombieSpawn` Marker2D children. Task 7's `world.gd` reads `SpawnMarkers/*`.

- [ ] **Step 1: Create `tools/bake_city_map.gd`:**

```gdscript
@tool
extends EditorScript
## Bakes a city plan into scenes/world/world.tscn. Run from the editor:
## File -> Run. IMPORTANT: close the world.tscn scene tab first (or reload it
## when prompted after the bake) — the bake rewrites the file on disk.
## Re-baking REPLACES all tiles, all Props children, and the spawn markers;
## hand-polish only after the layout is final.

const PLAN_PATH := "res://maps/plans/city_a.tscn"
const WORLD_PATH := "res://scenes/world/world.tscn"
const SEED := 1


func _run() -> void:
	var CityGen = load("res://scripts/city_gen.gd")
	var cfg: Dictionary = load("res://scripts/balance.gd").CITYGEN

	# 1. Read the plan.
	var plan_root: Node = (load(PLAN_PATH) as PackedScene).instantiate()
	var zones_layer: TileMapLayer = plan_root.get_node("Zones")
	var markers_layer: TileMapLayer = plan_root.get_node("Markers")
	var zones := {}
	for c in zones_layer.get_used_cells():
		zones[c] = zones_layer.get_cell_atlas_coords(c).x
	var markers := {}
	for c in markers_layer.get_used_cells():
		markers[c] = markers_layer.get_cell_atlas_coords(c).x
	plan_root.free()

	# 2. Generate + validate.
	var r: Dictionary = CityGen.generate(zones, markers, cfg, SEED)
	if not r.errors.is_empty():
		for e in r.errors:
			push_error("bake_city_map: " + e)
		print("BAKE ABORTED — fix the plan and re-run.")
		return

	# 3. Open the world scene for editing (preserve sub-scene instances).
	var world_packed: PackedScene = load(WORLD_PATH)
	var world: Node = world_packed.instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	var ground: TileMapLayer = world.get_node("GroundLayer")
	var buildings: TileMapLayer = world.get_node("BuildingLayer")
	ground.position = Vector2.ZERO  # legacy map had a stray (1,0) offset
	buildings.position = Vector2.ZERO

	# 4. Repaint tile layers (atlas row 0, source 0 — city_tileset.tres).
	ground.clear()
	for p in r.ground:
		ground.set_cell(p, 0, Vector2i(r.ground[p], 0))
	buildings.clear()
	for p in r.buildings:
		buildings.set_cell(p, 0, Vector2i(r.buildings[p], 0))

	# 5. Rebuild Props.
	var props: Node2D = world.get_node_or_null("Props")
	if props != null:
		world.remove_child(props)
		props.free()
	props = Node2D.new()
	props.name = "Props"
	world.add_child(props)
	world.move_child(props, world.get_node("BuildingLayer").get_index() + 1)
	props.owner = world
	for entry in r.props:
		var scene: PackedScene = load(entry.scene)
		var node: Node2D = scene.instantiate()
		node.position = entry.pos
		node.rotation = entry.rot
		props.add_child(node)
		node.owner = world

	# 6. Spawn markers.
	var sm: Node2D = world.get_node_or_null("SpawnMarkers")
	if sm != null:
		world.remove_child(sm)
		sm.free()
	sm = Node2D.new()
	sm.name = "SpawnMarkers"
	world.add_child(sm)
	sm.owner = world
	var tp: float = float(cfg.tile_px)
	for def in [["ShooterSpawn", r.shooter_tile], ["ZombieSpawn", r.zombie_tile]]:
		var m := Marker2D.new()
		m.name = def[0]
		m.position = (Vector2(def[1]) + Vector2(0.5, 0.5)) * tp
		sm.add_child(m)
		m.owner = world

	# 7. Save.
	var packed := PackedScene.new()
	var perr := packed.pack(world)
	if perr != OK:
		push_error("bake_city_map: pack failed (%d)" % perr)
		return
	var serr := ResourceSaver.save(packed, WORLD_PATH)
	world.free()
	print("bake_city_map: %s (%dx%d tiles, %d props), save err=%d"
		% [WORLD_PATH, r.size.x, r.size.y, r.props.size(), serr])
```

- [ ] **Step 2: Bake.** In the live editor: close the `world.tscn` tab (or accept the reload prompt after), open `tools/bake_city_map.gd`, File → Run. Expected editor-log line: `bake_city_map: res://scenes/world/world.tscn (94x94 tiles, N props), save err=0`.

- [ ] **Step 3: Verify visually.** Open `world.tscn`: 94×94 city with roads, sidewalks, buildings, parks, parking lots, props, and a `SpawnMarkers` node. Confirm `GroundLayer` and `BuildingLayer` still reference `city_tileset.tres` and that sub-scene instances (HUD, GameOver, PauseMenu, AimCursor) survived the repack — check the Scene dock shows them as instances (film-strip icon), not inlined trees. **If the repack inlined them, stop and fix before proceeding** (this invalidates the bake approach and needs a different write path, e.g. editing only the two layers' `tile_map_data` via the MCP scene tools).

- [ ] **Step 4: Boot check.** MCP `project_run`, then `logs_read source=all` — zero `SCRIPT ERROR` = clean boot (game will still use old spawn logic; full runtime wiring is Task 7).

---

### Task 7: Runtime de-hardcoding — spawns from markers, map size from used_rect

**Files:**
- Modify: `scenes/world/world.gd`
- Modify: `scripts/zombie_controller.gd`
- Modify: `scripts/minimap.gd`
- Modify: `scripts/fog_zombie_controller.gd`

**Interfaces:**
- Consumes: `SpawnMarkers/ShooterSpawn`, `SpawnMarkers/ZombieSpawn` (Task 6), `GroundLayer.get_used_rect()`.
- Produces: `World.map_px: Vector2` (world extent in px, origin (0,0)); `ZombieController.map_px: Vector2` (set by world before use); `Minimap.world_px: float` member replacing `Balance.MINIMAP.world_px` reads; `FogZombieController.grid_override: Vector2i` (set before `add_child`; `Vector2i.ZERO` = use `Balance.FOG_ZC` defaults).

All edits via MCP `script_patch`.

- [ ] **Step 1: `scenes/world/world.gd` — derive map size and apply it.** Add member `var map_px: Vector2 = Vector2(3008, 3008)`. In `_ready()`, immediately before `_create_grid()`:

```gdscript
	# Derive world extent from the baked map so any map size just works.
	var used := ground_layer.get_used_rect()
	map_px = Vector2(used.position + used.size) * 64.0
	var zc_cam: Camera2D = $ZCCamera
	zc_cam.limit_right = int(map_px.x)
	zc_cam.limit_bottom = int(map_px.y)
	zc_cam.position = map_px * 0.5
	var fog_rect: Control = $ZCFogRect
	fog_rect.offset_right = map_px.x
	fog_rect.offset_bottom = map_px.y
	zc_node.map_px = map_px
```

(`zc_node` is the existing zombie-controller reference in world.gd — confirm its var name at the top of the file and reuse it.)

- [ ] **Step 2: `world.gd` — GridDrawer size.** In `class GridDrawer` change `var map_size := 3000` from a local into an exported member: replace the `_draw()` local `var map_size := 3000` with a class member `var map_size := 3000` (same default), and in `_create_grid()` set `grid.map_size = int(map_px.x)` before `add_child(grid)`.

- [ ] **Step 3: `world.gd` — spawns from markers.** Replace the body of `_spawn_master_zombie()`'s first two lines:

```gdscript
	var zm: Marker2D = get_node_or_null("SpawnMarkers/ZombieSpawn")
	var near_tile := ground_layer.local_to_map(zm.position) if zm != null else Vector2i(43, 3)
	var tile := _find_clear_road_tile_near(near_tile)
	var spawn_pos: Vector2
	if tile != Vector2i(-1, -1):
		spawn_pos = ground_layer.map_to_local(tile)
	elif zm != null:
		spawn_pos = zm.position
	else:
		spawn_pos = Vector2(2700, 300)
```

In `_random_shooter_spawn()`, before the existing random loop, add a marker-biased attempt (keep the old loop as fallback):

```gdscript
	var sm: Marker2D = get_node_or_null("SpawnMarkers/ShooterSpawn")
	if sm != null:
		var center := ground_layer.local_to_map(sm.position)
		for i in 40:
			var cand := center + Vector2i(randi_range(-4, 4), randi_range(-4, 4))
			var td: TileData = ground_layer.get_cell_tile_data(cand)
			if td == null or not td.get_custom_data("tile_type") in walkable:
				continue
			if building_layer.get_cell_tile_data(cand) != null:
				continue
			var world_pos := ground_layer.map_to_local(cand)
			if world_pos.distance_to(master_zombie_spawn_pos) < min_z:
				continue
			return world_pos
```

(Match local var names — `walkable`, `min_z` — to what that function already declares; also update the hardcoded `var fallback := Vector2(300, 2700)` to `var fallback := Vector2(map_px.x * 0.1, map_px.y * 0.9)`.)

- [ ] **Step 4: `world.gd` — retire prop scatter.** Remove the `prop_scatter.scatter()` call from `_ready()` (leave the `PropScatter` node + script in place, dormant, until the baked map has proven itself in playtest — deleting them is a follow-up cleanup). Verify prop occluder collection still works: the loop at ~line 138 must pick up `Props` children (check what populates the `props` array — if it iterates `prop_scatter` children or a group, adjust it to also/instead walk `$Props.get_children()`).

- [ ] **Step 5: `scripts/zombie_controller.gd` — camera clamp.** Add member `var map_px := Vector2(3008, 3008)`. Replace the hardcoded clamp at ~line 492:

```gdscript
	camera.global_position = camera.global_position.clamp(Vector2.ZERO, map_px)
```

Also pass size into fog + minimap where they're created (~lines 71 and 90):

```gdscript
	fog_zc.grid_override = Vector2i(map_px / 64.0)
	...
	minimap.world_px = map_px.x
```

**Ordering caveat:** `zombie_controller._ready()` runs before `world._ready()` sets `zc_node.map_px`. So at the top of `zombie_controller._ready()`, derive it directly instead of waiting:

```gdscript
	var gl: TileMapLayer = get_parent().get_node("GroundLayer")
	var used := gl.get_used_rect()
	map_px = Vector2(used.position + used.size) * 64.0
```

(World setting `zc_node.map_px` afterwards is then a harmless overwrite with the same value.)

- [ ] **Step 6: `scripts/minimap.gd` — world_px member.** Add `var world_px: float = Balance.MINIMAP.world_px`. Replace the three read sites (lines ~61, ~201, ~207): `Balance.MINIMAP.world_px` → `world_px`.

- [ ] **Step 7: `scripts/fog_zombie_controller.gd` — grid override.** Add `var grid_override := Vector2i.ZERO` near the top. In `_ready()` replace the two grid lines:

```gdscript
	GRID_W = grid_override.x if grid_override.x > 0 else b.grid_w
	GRID_H = grid_override.y if grid_override.y > 0 else b.grid_h
```

- [ ] **Step 8: Verify in the live editor.** MCP `project_run` + `logs_read source=all`: zero `SCRIPT ERROR`. Then owner playtest checks: shooter spawns near the white-marker block, master zombie near the red-marker block; zombie-commander camera pans the full 94×94 map and clamps at its edges; minimap shows the whole new map; zombie fog covers the map (no black band past tile 47); props render with fog occluders.

---

### Task 8: Rebalance counts for 4x area

**Files:**
- Modify: `scripts/balance.gd`

**Interfaces:** none new — existing `Balance.WORLD` / `Balance.LOOT` consumers pick the numbers up.

- [ ] **Step 1: Scale populations** (starting numbers — playtest tunes them). Via MCP `script_patch`:

```gdscript
const WORLD := {
	base_zombie_count = 30,          # was 15 — map area x4, density ~x2 feels right to start
	zombies_per_extra_shooter = 8,   # was 5
	npc_per_player = 8,              # was 5
	fog_enabled = true,
}
```

And in `LOOT`: `box_count = 20,` (was 8).

- [ ] **Step 2: Boot check.** MCP `project_run` + `logs_read`: clean boot, no spawn-loop warnings (the spawn helpers give up after N attempts — if logs show shortfalls, the map has room, so raise the attempt caps in `world.gd`'s `_spawn_standard_zombies` / `_spawn_npcs` rather than lowering counts).

---

### Task 9: Playtest + tune (owner gate)

**Files:** possibly `scripts/balance.gd` (tuning only).

- [ ] **Step 1: Ask Mads for a full playtest**, both roles. Checklist to hand him:
  - Shooter: spawn location, walk a few blocks — do streets/alleys read as a city? Flashlight and weapon ranges feel OK at this scale? Loot boxes findable?
  - Zombie commander: spawn, fog reveal, minimap orders across the far map, camera pan/clamp at all four edges.
  - NPCs: follow across long streets; zombies path around the new buildings (NavigationAgent2D uses the tileset nav polygons — regenerated automatically from the baked tiles).
  - Multiplayer smoke test (two windows): both peers load the identical baked map; props identical on both.
- [ ] **Step 2: Apply tuning feedback** to `Balance.CITYGEN` densities / `WORLD` counts / `LOOT.box_count`; re-bake if plan-level changes are wanted (new seed, new zone layout).

---

### Task 10: Documentation

**Files:**
- Create: `docs/map_generator_guide.md`
- Modify: `CHANGELOG.md`, `ARCHITECTURE.md`, `PROJECT.md`

- [ ] **Step 1: Write `docs/map_generator_guide.md`** — the comprehensive guide Mads asked for. Required contents (write each as a real section with concrete steps, not summaries):
  1. **How it works** — the pipeline (plan scene → CityGen → validation → bake → world.tscn), the block geometry diagram (10×10 layout: 2 road / 1 sidewalk / 6 interior / 1 sidewalk), what each zone type generates, where every tunable lives (`Balance.CITYGEN`).
  2. **Step-by-step: make a new map** — duplicate `maps/plans/city_a.tscn` (or run `tools/make_demo_plan.gd` for a fresh start), paint zones with the tile editor (tile ↔ zone color legend table), paint exactly one shooter + one zombie marker on the `Markers` layer, set `PLAN_PATH`/`SEED` in `tools/bake_city_map.gd`, close the world.tscn tab, File → Run, reopen and inspect.
  3. **Step-by-step: add a new prop asset** — save the prop scene under `scenes/props/`, (new PNGs: let the editor import on focus, commit the `.import`), add a palette entry to `Balance.CITYGEN.props` with `scene/count_min/count_max/on/jitter_px/min_sep_px`, re-bake.
  4. **Step-by-step: add a new zone type** — new color square in `textures/plan_tiles.png` (the python snippet from the plan), new atlas tile in `plan_tileset.tres`, new `Z_*` const + `fill_zone` branch + `ZONE_KEYS` entry in `city_gen.gd`, palette in `Balance.CITYGEN.props`, test in `test/test_city_gen.gd`.
  5. **Changing map scale** — plan grid size vs `block_tiles`; what each does to the result; reminder that populations (`Balance.WORLD`, `LOOT.box_count`) scale with area by hand.
  6. **Troubleshooting** — bake aborts with marker/hole/connectivity errors (what each means, how to fix the plan); "my hand-edits disappeared" (re-bake overwrites — polish last); props missing on one multiplayer peer (stale world.tscn — both must run the same baked file); spawns in odd places (markers on non-walkable cells — bake snaps to nearest road, check the Markers layer); editor shows old map (close/reopen the world.tscn tab after bake); test script fails headless (`class_name` gotcha, editor must be closed); new PNG invisible (needs one editor-focus import).
- [ ] **Step 2: Update project docs.** CHANGELOG.md: one entry for the generator + 4x map. ARCHITECTURE.md: add `city_gen.gd`, `tools/`, `maps/plans/`, the Props/SpawnMarkers nodes, the runtime map-size derivation, note prop_scatter dormant. PROJECT.md: Phase 5 status → done (bake-time generation), map now 94×94.
- [ ] **Step 3: Suggest a commit message** for Mads, e.g. `Add zone-painted city map generator + bake 4x map`.

---

## Self-review notes

- Spec coverage: plan scene w/ two layers (T5), CityGen pipeline + BSP + validation (T1–4), palette props baked as nodes (T4/T6), EditorScript bake (T6), spawn markers + de-hardcoded map size (T7), rebalance (T8), headless tests by path (T1–4), live-editor verification (T6–8), comprehensive guide (T10). Out-of-scope items from the spec remain out.
- Known risk, surfaced in T6 Step 3: `PackedScene.pack()` must preserve sub-scene instances (uses `GEN_EDIT_STATE_MAIN`); the step includes an explicit stop-and-verify gate with a fallback path.
- `CityGen` never touches `Balance`/autoloads/scene types → headless-safe.
