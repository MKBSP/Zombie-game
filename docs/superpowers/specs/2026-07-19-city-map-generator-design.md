# City Map Generator — Design

**Date:** 2026-07-19
**Status:** Approved (pending spec review)
**Pulls forward:** Phase 5 (map generation) + Phase 8's "4x map" requirement

## Goal

Replace the hand-painted 47×47-tile map in `world.tscn` with maps produced by a
zone-painted procedural generator, so Mads can:

1. Design new maps in minutes by painting zones, not tiles.
2. Get variation by re-rolling a seed.
3. Make the world feel alive by adding new prop assets to palettes, which every
   future bake then uses.

First generated map targets **~90×90 tiles** (2x per side, 4x area of today's
map, ~5760×5760 px at 64 px/tile). Entities, camera, and weapon ranges stay
unchanged; feel-tuning happens from playtests afterwards.

## Decisions made during brainstorming

- **Scale:** 4x area (2x per side), not the full "100 m per block" ratio yet.
- **Generation timing:** **Bake-to-.tscn only.** No runtime generation; every
  peer loads the same scene file, so multiplayer needs no seed sync. Runtime
  generation can be added later since the generator is pure logic.
- **Authoring:** paint zones as a mini-TileMap in the Godot editor (most
  map-design-like workflow), not an ASCII file, not pure-random.
- **No plugins.** Gaea and the WFC addon target caves/landscapes/local tile
  coherence; neither generates roads/lots/buildings. The city logic is small
  and custom. (WFC addon noted as a possible later tool for organic areas.)

## Architecture

Pipeline, each stage simple and inspectable:

```
plan scene (painted zones)
   → CityGen (pure logic: roads → sidewalks → lots via BSP → zone fill → props)
   → validation (flood-fill connectivity)
   → bake tool (EditorScript writes world.tscn: tile layers + prop nodes + spawn markers)
```

### 1. Plan authoring

- New `resources/plan_tileset.tres`: solid-color 64 px tiles, one per zone
  type. Zone types v1: **Residential, Commercial, Park, Parking, Empty**, plus
  marker tiles **Shooter spawn** and **Zombie spawn**.
- Cemetery becomes its own zone when cemetery tile art exists; until then use
  Park.
- Plan scenes live in `maps/plans/` (e.g. `maps/plans/city_a.tscn`) and hold
  **two `TileMapLayer`s**: `Zones` (painted ~9×9 cells) and `Markers` (one
  Shooter-spawn tile + one Zombie-spawn tile painted over a walkable zone;
  exactly one of each required, validated at bake).
- **1 plan cell = 1 city block = `BLOCK_TILES` map tiles (default 10)**:
  2-tile road on shared edges, 1-tile sidewalk ring, ~6-tile interior.
  `BLOCK_TILES` is a config constant, so map scale is a knob.

### 2. Generator — `CityGen` (pure logic)

`extends RefCounted` static-style helper (like `LootTable`, `MinimapMath`) so
headless tests can load it by path. Input: plan grid (`Dictionary` of
`Vector2i → zone id`) + seed (`RandomNumberGenerator`). Output: a result object
with ground-tile dict, building-tile dict, prop placements, spawn positions.

Per-zone fill rules (interior of each block):

| Zone | Fill |
|------|------|
| Residential | BSP-subdivided lots → small/medium building rects with alley gaps, grass between |
| Commercial | BSP lots biased large → 1–2 big buildings, sidewalk ground |
| Park | grass, no buildings; statue chance |
| Parking | parking tiles, fence ring with gaps |
| Empty | grass/road rubble, nothing else |

Roads are shared between adjacent blocks (drawn on north/west edges + map
border) so arteries are continuous by construction. Same plan + same seed =
byte-identical output.

### 3. Props — baked, palette-driven

Per-zone palettes map prop scenes to spawn rules (density, allowed ground
tiles, min separation):

- Residential: trees, dumpsters
- Commercial: dumpsters, parked cars
- Parking: cars, fences
- Park: trees, statue
- Roads (all zones): occasional cars

The bake writes props as **real child nodes** of a `Props` node in
`world.tscn` — each one hand-nudgeable/deletable in the editor. Adding a new
asset (light post, wreck) = add its `.tscn` to a palette entry; every future
bake uses it. Baked maps stop using runtime `prop_scatter.gd` (props are scene
content, multiplayer-identical by construction); the script is retired once
the baked map ships.

### 4. Bake tool — `EditorScript`

`tools/bake_city_map.gd`, run from the **live editor** (File → Run). No
headless Godot involved (avoids the `.godot/` cache-fight gotcha). Steps:

1. Load plan scene (path + seed configured at top of script).
2. Run `CityGen`, then the connectivity check — abort with a clear error if
   any walkable region is unreachable.
3. Write into `world.tscn`: `GroundLayer`/`BuildingLayer` tile data, rebuild
   `Props` children, set `SpawnMarkers/ShooterSpawn` + `SpawnMarkers/ZombieSpawn`
   (`Marker2D`s).
4. Save the scene.

**Re-bake = full rewrite** of tiles, props, and markers. Hand-polish is done
after the layout is final, or it will be overwritten.

### 5. `world.gd` changes

- Read spawn positions from `SpawnMarkers` nodes instead of the hardcoded
  zombie tile `(43, 3)` / fallback `Vector2(2700, 300)`.
- Drop the `prop_scatter.scatter()` call once the baked map lands.
- Everything else (loot, NPC, crate placement, blood canvas, fog occluders,
  minimap, navigation) already derives from the tile layers and adapts
  untouched.

### 6. Rebalancing

Area-scaled counts move to / are tuned in `Balance`: NPC count, zombie count,
loot-box count, prop densities (per-zone, in the palette config). Flashlight,
weapon ranges, bullet travel, camera zoom: **unchanged for now**, revisited
from playtest feel.

### 7. Testing

Headless `test/` scripts (editor closed, per CLAUDE.md gotchas; load `CityGen`
via `load("res://...")`, never bare `class_name`):

- Determinism: same plan + seed twice → identical output.
- Connectivity: flood-fill from shooter spawn reaches every walkable tile.
- Road continuity: every block edge has its road tiles.
- Zone legality: each zone type only emits its allowed tile types; markers
  resolve to walkable positions.

Bake + gameplay verified in the live editor (`project_run` + `logs_read`,
owner playtest).

### 8. Documentation (final step, required)

A comprehensive user guide: **`docs/map_generator_guide.md`** covering:

- How the system works (plan → generator → bake, with the pipeline diagram).
- Step-by-step: creating a new plan scene, painting zones, placing spawn
  markers, running the bake, checking the result, hand-polishing.
- Step-by-step: adding a new prop asset to a palette; adding a new zone type.
- Changing map scale (`BLOCK_TILES`, plan grid size).
- Troubleshooting: bake errors (missing markers, connectivity failure, bad
  plan tiles), props not appearing, spawns in walls, re-bake overwriting
  polish, editor/import gotchas for new PNGs.

Plus the usual: CHANGELOG.md entry, ARCHITECTURE.md / PROJECT.md updates.

## Build order

1. `CityGen` core (roads/sidewalks/BSP lots/zone fill) + headless tests
2. Plan tileset + example plan `city_a.tscn`
3. Bake tool writing tiles into `world.tscn`
4. Spawn markers + `world.gd` de-hardcoding
5. Prop palettes + baked props
6. Rebalance counts for 4x area
7. Playtest + tune
8. Write `docs/map_generator_guide.md` + update project docs

Each step leaves the game runnable.

## Out of scope (explicitly)

- Runtime/random per-match generation (generator stays pure so this stays easy).
- New tile art, cemetery/dirt/alley tiles, curved roads, L-shaped buildings.
- Sprint mechanic and the full 100 m-block real-world scale.
- Multi-map selection UI (world.tscn keeps holding the single active map).
