# Detailed Discovered-World Minimap — Design

**Date:** 2026-06-29
**Status:** Approved, building directly (increment on Phase 7 minimap)

## Summary

Upgrade the Zombie Controller minimap from a flat fog-tinted grid into an
AoE-style discovered-world map: real terrain, buildings, and discovered static
features (trees, props, loot boxes), with live units over the top. Move it to the
bottom-left and add a Rally-All command.

Dropped during brainstorming (no fit for a 1v1, no-economy game): warning flare,
chat, and the unit filter cycle.

## Rendering layers (back to front)

1. **Terrain base (cached once):** at `setup()`, sample `ground_layer` +
   `building_layer` for every grid cell (47×47) into a `PackedColorArray`. Terrain
   never changes, so this is built once. Colors:
   - building present → dark slate `(0.15,0.15,0.18)`
   - road `(0.33,0.33,0.35)` · sidewalk `(0.45,0.45,0.47)` · grass
     `(0.20,0.40,0.22)` · parking `(0.34,0.30,0.25)` · none → black
   Each frame, draw each cell as its cached color **dimmed by fog state**:
   unexplored → black, explored → ×0.4, visible → ×1.0.
2. **Discovered static features** (drawn only where the tile is explored or
   visible — they persist once found because they don't move):
   - **props** group: trees (node name contains "Tree") → green dot, others → grey
     dot. Props get a new `props` group on their 5 scenes.
   - **loot_boxes** group → gold square.
3. **Dynamic units** (unchanged from Phase 7):
   - zombies (own) → red, always
   - shooter + npcs → yellow when in a zombie's vision; fading grey ghost at
     last-seen otherwise. Plus under-attack pulse and gunshot ripple.

## Layout

- Minimap moves to the **bottom-left** corner (`Balance.MINIMAP.margin_px`).
- `StancePanel` (world.tscn) shifts right of the minimap (offset_left ≈ size +
  2×margin) so they don't overlap. MergePanel stays bottom-right.

## Rally All

- A runtime **"Rally All"** button just above the minimap, plus the **G** hotkey.
- Arming: button/hotkey sets `minimap.rally_armed = true` (minimap draws a colored
  border while armed).
- The next **left-click on the minimap** emits `rally_point_picked(world_pos)` and
  disarms; an un-armed click still jumps the camera.
- `ZombieController._rally_all(world_pos)` collects every node in group `zombies`
  and issues the existing `rpc_command_move(names, world_pos)` — the whole horde
  (master included) moves there, temporarily overriding stances, then reverts. The
  current selection is left untouched.

## Interfaces

- `MinimapMath.terrain_color(tile_type: String, has_building: bool) -> Color`
  (pure, unit-tested).
- `Minimap.setup(fog_zc, camera)` gains a `building_layer` field; `Minimap` builds
  `_terrain_colors` and exposes `rally_armed: bool` + `signal
  rally_point_picked(world_pos: Vector2)`.
- `ZombieController._rally_all(world_pos)`, a runtime Rally-All button, and a `G`
  binding.

## Data / dependencies

- `building_layer` reached from `zombie_controller` via `get_node_or_null(
  "../BuildingLayer")` (sibling of `ZombieControllerNode` under `World`).
- Grid cell (x,y) aligns 1:1 with tilemap cell (x,y) (47×47 over the 3008px map),
  so `tile_states[y*GRID_W+x]` and `get_cell_tile_data(Vector2i(x,y))` match.

## Non-goals

- No flare, chat, or unit filter cycle.
- No new replication: static features read local group membership + the existing
  fog; rally uses the existing move RPC.

## Testing

- `MinimapMath.terrain_color` unit-tested headless.
- Terrain rendering, discovered features, layout, and rally verified in the live
  editor (clean boot) + owner playtest.
