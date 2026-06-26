# Flashlight Fog of War v2 — Design

**Date:** 2026-06-26
**Status:** Approved, pending implementation plan
**Scope:** Shooter (HUMAN role) fog of war only. The zombie-controller AoE2 fog is untouched.

## Problem

The current shooter fog of war is a screen-space, tile-resolution overlay:

- `FogShooter` (`scripts/fog_shooter.gd`) computes a 47×47 visibility image on the CPU
  every frame — a triangular flashlight cone plus a 3×3 dim bubble, with Bresenham
  raycasts that stop at **static occluders only** (buildings, edge tiles, props).
- `shader/fog_of_war.gdshader` paints pure black with `alpha = 1 - visibility` over a
  `ColorRect` (`$HUDLayer/ShooterFogRect`).

Limitations we want to fix:

1. Fog is pure **black**; we want a tunable dark/grey opaque look.
2. The flashlight is a coarse tile cone; we want a clean hard-edged beam.
3. **Dynamic entities do not block light.** Zombies, NPCs, and the master zombie
   should cast shadows and break the beam.
4. Shadows should be true straight lines from occluders.

## Approach

Replace the screen-space tile overlay with Godot's built-in **2D lighting**. This is
supported in the GL Compatibility renderer the project uses.

In the **HUMAN (shooter) instance only**:

- A **`CanvasModulate`** node tints the entire game world dark — this *is* the fog.
  The HUD lives on its own `CanvasLayer`, so it stays fully bright; only the world
  darkens.
- **`Light2D` nodes add brightness back**, revealing whatever they touch. Entities
  outside any light are swallowed by the dark, so zombies/NPCs are hidden until the
  beam finds them — the intended gameplay payoff.

Each role runs as its own networked process (true even for local multiplayer — it is
all netcode). The ZOMBIE-controller instance therefore never sees the CanvasModulate
or lights, and its `FogZombieController` / `fog_zc.gdshader` fog is completely
unchanged.

### Why not the alternatives

- **Evolve the tile system** — cheap, but stays blocky and can't give clean
  straight-line shadows from dynamic entities without effectively reimplementing a
  light engine on the CPU.
- **Per-pixel shader raymarch** — smooth, but packing dynamic occluder geometry into a
  shader every frame is fiddly and duplicates what Godot's 2D shadow system already
  does well.

The built-in lighting path gives true dynamic shadows for free and removes per-frame
CPU fog work entirely.

## Components

### 1. The two lights (children of the shooter)

The shooter body already rotates to face its aim
(`shooter.gd`: `rotation = (_net_aim_target - global_position).angle()`), so any light
parented to the shooter tracks the aim automatically — **no per-frame fog code is
needed**.

- **Flashlight** — a `PointLight2D` with a **hard-edged cone texture**: solid white
  inside the cone half-angle and within range, transparent outside. The texture is
  **generated in code** from Balance parameters (no art asset to manage). The cone apex
  sits at the shooter via the light's `offset`. `shadow_enabled = true`.
- **Personal halo** — a small `PointLight2D` with a soft radial gradient, low energy, a
  few tiles in radius, so the shooter is never fully blind to his immediate
  surroundings.

### 2. Occluders (what blocks light → straight-line shadows)

- **Static** (building tiles, edge tiles, and props in the `occluders` group — cars,
  trees, dumpsters, statue): at world setup, generate one `LightOccluder2D` square per
  occluding tile/prop, reusing the existing occluder-detection logic from
  `FogShooter.cache_occluders()` and `cache_prop_occluders()`. Built once, HUMAN role
  only.
- **Dynamic** (zombies, master zombie, NPCs — anything that moves): each scene gets a
  body-sized `LightOccluder2D` child so it casts a moving shadow. These are harmless and
  cheap in the zombie instance, where no lights exist.

Godot's 2D shadow system produces the crisp straight-line shadow edges automatically.

### 3. Tuning — `balance.gd`

The current `FOG_SHOOTER` dict is repurposed into light parameters, all live-tweakable:

- `ambient_darkness` — the `CanvasModulate` color/value. **The opacity dial**: lower =
  near-black, higher = faint grey where the map layout stays faintly readable.
- Flashlight: `range`, `energy`, `cone_half_angle`, `color`.
- Halo: `radius`, `energy`.
- Shadow enable toggles.

### 4. Wiring (`world.gd`)

A new helper `scripts/shooter_lighting.gd` builds the CanvasModulate, the two lights,
and the static occluders for the HUMAN role. `_setup_fog()` is replaced by a call into
this helper; the ZOMBIE role does nothing for shooter fog.

## Removals

- `$HUDLayer/ShooterFogRect` ColorRect from `scenes/world/world.tscn`.
- `shader/fog_of_war.gdshader` (+ `.uid`).
- `scripts/fog_shooter.gd` (the `FogShooter` tile-raycaster class).
- The per-frame fog texture update in `world.gd::_process()` and the
  `shooter_fog_rect.visible` lines in `_apply_role()`.

## Testing

- No existing fog unit tests to migrate (`test/` has none for fog).
- Primary verification is **visual**: run the game and capture `editor_screenshot` via
  the godot-ai MCP — confirm the dark world, the hard-edged beam tracking aim, the
  personal halo, and shadows from a building and from a zombie/NPC.
- Add a small headless unit test that occluder generation produces the expected
  `LightOccluder2D` count from a known tilemap fixture.

## Risks / trade-offs

- Runtime-generating one occluder square per building tile may yield a few hundred
  nodes. Fine for Godot 2D shadows; if it ever shows up in profiling, merge contiguous
  building tiles into larger occluder polygons. **YAGNI for now.**
- Cone-texture generation must place the apex correctly at the shooter via `offset`;
  verify visually that the beam originates at the player, not the texture center.
