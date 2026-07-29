# Ambient Lighting & Life — Design Spec

> **For agentic workers:** This is a brainstorming design spec, not an implementation
> plan. REQUIRED NEXT STEP: use superpowers:writing-plans to turn this into a
> task-by-task implementation plan before writing any code.

**Goal:** Give the map a sense of life — lightposts, a burning dumpster, scurrying/flying
critters, and grass that visually interacts with light and characters — while adding one
real new mechanic: the zombie-commander player can now sense the shooter's flashlight
through their own fog of war, with a deliberate risk/reward tradeoff for the shooter.

**Architecture:** Everything here is additive to three systems that already exist:
the shooter's `Light2D`-based flashlight/fog (`shooter_lighting.gd`), the zombie
commander's per-zombie vision lights + persistent tile-grid exploration memory
(`zombie_lighting.gd` + `fog_zombie_controller.gd`), and the map-wide gunshot noise
signal (`world.gd`'s `emit_noise`/`noise_event`). Nothing here replaces those systems;
new features feed into them as additional inputs.

**Tech Stack:** GDScript, Godot `Light2D`/`LightOccluder2D`, the existing tile-grid fog
shader (`shader/fog_zc.gdshader`), no new external dependencies.

## Global Constraints
- All new tunable numbers (counts, radii, speeds, damping %) live in `scripts/balance.gd`,
  not hardcoded in scene/behavior scripts, per project convention.
- All game-file edits go through the godot-ai MCP tools, per CLAUDE.md.
- Everything in this spec ships as placeholder/programmer art (circles, rectangles,
  sticks) — no new binary image assets. A later, separate spec swaps in real sprites
  once these mechanics are proven.
- Pure logic (placement rules, reveal-math helpers) belongs in `extends RefCounted`
  static helper classes, referenced via `load("res://...")` in tests rather than bare
  `class_name`, per the project's headless-test gotcha (class_names that extend scene
  types don't resolve in headless `test/` runs).

---

## 1. Existing systems this builds on (context for the plan author)

- **`scripts/shooter_lighting.gd`** — builds the HUMAN role's fog: a dark
  `CanvasModulate` over the world, a cone `PointLight2D` (flashlight) + radial halo
  parented to the shooter, and static `LightOccluder2D`s from building/edge tiles and
  props. `collect_static_occluder_positions()` and `build_static_occluders()` are
  reusable helpers.
- **`scripts/zombie_lighting.gd`** — same visual approach for the ZOMBIE role: ambient
  darkness + one `Light2D` per zombie (`refresh_lights()`), with `shadow_item_cull_mask`
  set so only static geometry casts vision shadows (entities never block each other's
  vision).
- **`scripts/fog_zombie_controller.gd`** (`FogZombieController`) — the ZOMBIE role's
  **persistent exploration memory**, separate from the live vision lights above. A
  47×47 (`GRID_W`×`GRID_H`, from `Balance.FOG_ZC`) tile grid with three states per tile:
  `STATE_UNEXPLORED` (0), `STATE_EXPLORED` (1, "terrain visible, no moving entities"),
  `STATE_VISIBLE` (2, fully visible). `update_visibility(zombies_data, blocked)` runs
  every frame: demotes all `VISIBLE` tiles to `EXPLORED`, then re-promotes tiles within
  each zombie's vision range back to `VISIBLE` via `_reveal_diamond()`, which is
  LOS-honest via `tile_line_clear()` (Bresenham, respecting a `blocked` dict of
  wall tiles). The result is written into `visibility_image`, sampled by
  `shader/fog_zc.gdshader` with `filter_linear` (already smoothly interpolated on
  screen, not blocky) as a darkness overlay: `alpha = 1.0 - vis`.
- **`world.gd`'s noise system** — `emit_noise(world_pos, strength)` (world.gd:431) is
  the single funnel point for every gunshot: server-side, it checks
  `distance_to(world_pos) <= Balance.AGGRO.alert_radius_px` per zombie for aggro, then
  broadcasts a `noise_event` signal (used for minimap ripples, UI feedback).
- **Ground tiles already carry a `tile_type` custom-data field** (`"road"`,
  `"sidewalk"`, `"grass"`, `"parking"`, `"building"`, `"edge"`, etc.), queried via
  `TileData.get_custom_data("tile_type")`. This is the hook for all placement rules
  below.
- **Props are already scattered with a shared, seeded RNG** (`prop_scatter.gd`) so
  scenery is identical for both peers in a match — new props/critters reuse this
  pattern.

---

## 2. Lightposts

**Placement:** 3 per map. Valid tile = `sidewalk` adjacent (orthogonally) to a `road`
tile. Falls back to ordinary seeded random walkable-tile scatter if no adjacency match
is found nearby, so map generation never fails to place one.

**Visual (placeholder):** a stick + small box/circle "lamp head." The lamp head visual
rotates to face the adjacent road tile's direction — it leans toward the street rather
than sitting neutral. Steady `Light2D` (no flicker).

**Shooter view:** no new code needed — it's a normal `Light2D` in the scene; Godot's 2D
lighting illuminates anything in range regardless of who owns the light, cutting through
the shooter's `CanvasModulate` darkness automatically.

**Zombie persistent fog:** unlike the roaming flashlight (see §4), a lightpost is a
fixed, static location — not a moving intel leak. Feed it into
`FogZombieController` as a **permanent pseudo-vision source**: same reveal mechanism as
a zombie's own vision cone (LOS-honest via the existing `blocked` check), granting full
visibility (including entities) within its radius. Because it's fed through the same
`tile_states` array real exploration uses, it also naturally becomes permanent
"explored" memory once seen — no new state needed.

The lamp's cosmetic facing (leaning toward the street) does **not** need to affect the
fog-reveal shape — keep that a plain circle for simplicity. A streetlamp lighting the
ground roughly around its base holds up fine even if the fixture cosmetically leans.

---

## 3. Burning dumpster

**Placement:** 3 per map. Valid tile = `sidewalk` adjacent to a `building` tile, OR any
`road` tile (either satisfies "against buildings, or on the street"). Same scatter
fallback as lightposts.

**Visual (placeholder):** a box + a small flickering-orange `Light2D` (energy jittered
per-frame for the flicker) + optionally a simple particle puff for smoke.

**Shooter view + zombie persistent fog:** identical treatment to lightposts — a
permanent pseudo-vision source feeding `FogZombieController`, full visibility within
radius, LOS-honest. The visual flicker is cosmetic only; the fog-reveal radius stays
constant so the fog computation isn't re-run off a jittering value every frame.

**Noise dampening (the one gameplay-coupled piece specific to the dumpster):** it does
**not** attract zombie aggro. Instead, it masks gunshots — any `emit_noise()` call whose
`world_pos` is within the dumpster's masking radius has its effective
`Balance.AGGRO.alert_radius_px` reduced by ~20% before the per-zombie distance check at
`world.gd:436`. Single, contained change at the one funnel point for all gunshot noise.

---

## 4. Cross-role flashlight visibility (zombie senses the shooter's light)

> **Correction made while writing the implementation plan:** the mechanism below was
> revised after inspecting the actual current `Balance.FOG_ZC` values. The shader file's
> own comments (`vis = 0.35 → mostly opaque (explored...)`) are stale — the live values
> are `vis_explored = 1.0, vis_visible = 1.0` (identical). The code comment "explored =
> terrain visible, no moving entities" is achieved *not* by the tile-grid encoding a
> brightness level, but by the separate, always-on `ambient_darkness` `CanvasModulate`
> plus whichever `Light2D`s are actually live in that spot — the tile-grid only gates a
> **binary** "is this hidden by opaque black fog, yes/no". This also means lighting/fog
> setup is built independently, client-side only, per role (`ShooterLighting.setup`/
> `ZombieLighting.setup` are called from `world.gd`'s `_setup_fog()` based on
> `GameState.role` — never both on the same client), so there is no shooter `Light2D`
> object replicated to the zombie's client to "see" directly. The revised mechanism
> below accounts for both facts.

This is the one genuinely new mechanic in this spec, and the one with real design
nuance — the goal is: the zombie-commander player should get *some* signal that the
shooter's flashlight is on somewhere on the map, without that becoming a permanent,
map-wide intel leak, **and** there should be real risk for the shooter in shining their
light directly at a group of zombies.

**Mechanism — reuses the existing tile-grid fog pipeline, not a new rendering system.**
`FogZombieController`'s "explored" tile state already means exactly "terrain visible,
no moving entities" per its own code comment — that's already the right *semantic* for
a distant glow. So:

1. **Unlock the binary fog-hide, transiently.** Each frame, before the per-zombie
   reveal pass runs, compute which tiles the shooter's flashlight cone currently
   reaches (a new `_reveal_cone()` in `FogZombieController`, sibling to the existing
   `_reveal_diamond()` — same LOS-honesty via `tile_line_clear()`, additionally gated
   by an angle-from-aim-direction check). Write `vis_explored`'s value into those
   tiles' slot in the output `visibility_image` **only** — never into the persistent
   `tile_states` array the way real exploration does. The moment the flashlight moves
   off an area, it reverts to whatever the zombie side actually knows from its own
   exploration history. This is what stops the shooter from passively "painting" the
   whole map known just by walking around with the light on — and it's *only* the
   binary hide/unhide gate, not brightness.
2. **The actual glow is a real, dim `Light2D`**, added locally on the zombie's client
   (reusing `ShooterLighting.make_cone_texture`/`make_radial_texture`, so it looks like
   the same flashlight shape), positioned and rotated to match the shooter's replicated
   position/rotation every frame. `shadow_enabled = true`, so it's naturally LOS-honest
   through existing occluders with zero new geometry code. Default energy is low — a
   capped "there's light over there" glow, not enough for small moving sprites to read
   clearly against the general gloom.
3. **Risk/reward promotion:** if any zombie is currently within that cone and has clear
   LOS to the shooter, bump this same `Light2D`'s energy up to a full-brightness value
   for that frame — no separate tile-state logic needed, since real entity legibility
   was already just a brightness effect (see the correction note above). This is the
   "shine your light directly on a cluster of zombies and they can see everything in
   the beam" risk, implemented as a single distance+angle+LOS check against each
   zombie, gating one number.

**Dependency, resolved:** the zombie-controller side needs the shooter's current world
position + aim direction each frame. `world.gd`'s own `shooter` variable is explicitly
"this client's own shooter (owning peer)" — null on other peers — so `zombie_controller.gd`
can't read it directly. `shooter.rotation` already *is* the aim direction (confirmed:
`rotation = (get_global_mouse_position() - global_position).angle()` and the networked
equivalent in `scenes/shooter/shooter.gd`), and the node itself is replicated via its
`MultiplayerSynchronizer` — it just needs a stable way to be *found* from the zombie
side. Fix, corrected during implementation: no new group needed — `scenes/shooter/shooter.tscn`
already declares `groups=["shooter"]` on its root node directly in the scene file, so
every shooter instance is already in a `"shooter"` group on every peer.
`zombie_controller.gd` finds it via `get_tree().get_nodes_in_group("shooter")`, the
same pattern `_get_enemy_at_position()` already uses elsewhere in that same file.

**New helper needed:** `FogZombieController` currently only has `_reveal_diamond()`
(Manhattan-distance, omnidirectional). This needs a sibling **cone-reveal** function —
same LOS-honesty via `tile_line_clear()`, but gated by an angle-from-origin check
against the flashlight's aim direction and half-angle, not just distance.

---

## 5. Critters

Three distinct types, low-fidelity placeholder shapes, all placed via the existing
seeded-scatter pattern so both peers see identical placement.

| Type | Look | Speed/size | Idle behavior | Stimulus behavior | Spawn rule | Starting count |
|---|---|---|---|---|---|---|
| Rats | small shape, ground | bigger, faster | ambient wander | flee from flashlight cone + gunshot noise | anywhere walkable | 20 |
| Bugs | small shape, ground | smaller, slower than rats | ambient wander | flee from flashlight cone + gunshot noise | walkable tile within a small radius of a scattered dumpster prop | 20 |
| Lightning bugs | tiny shape, flying | soft drifting motion | gentle idle drift | **no fear behavior** — only a slight nudge-aside if a zombie/NPC/player walks directly through their path (local collision-avoidance, not fear-driven) | `grass` tiles | 30 |

All counts are starting defaults in `Balance.gd`, expected to be tuned after seeing
them run (particularly checking performance with this many active nodes).

Flee/nudge triggers reuse existing signals — no new plumbing: the shooter's flashlight
cone (same data needed for §4) and `world.gd`'s existing `noise_event` signal
(`zombie_controller.gd:138` already shows the pattern for listening to it).

---

## 6. Grass

Scope, precisely (to avoid ambiguity): grass tiles get **two** effects. They do **not**
dampen gunshot noise (that's the dumpster's job only, per §3) and they do **not**
change the zombie-side fog-reveal computation (kept decoupled from §4's already
nontrivial fog math).

1. **Light dappling on the shooter's flashlight** — similar in *character* to how a
   fence's shadow already looks (fences are real, solid `LightOccluder2D`s, so their
   shadow is a hard-edged cast shadow, made visually "dappled" simply because each
   fence prop casts its own separate small square occluder rather than one continuous
   wall). Grass reuses this same mechanism: scatter a moderate density of small
   occluders across `grass` tiles (not full per-tile coverage — partial, so the beam
   crossing grass looks broken/dappled rather than either fully lit or fully blocked).
   This is a shooter-side-only visual effect; it does not touch `FogZombieController`.
2. **Slight visual obscuring of characters standing in grass** — when a character
   (shooter, zombie, NPC) is on a `grass` tile, reduce their sprite's `modulate.a`
   slightly (e.g. to ~0.7), reverting when they leave the tile. This is intrinsic to
   the character node, so it's automatically consistent for every viewer (shooter's own
   screen, zombie's screen) without any per-viewer special-casing.

---

## Non-goals / explicitly deferred

- **Real art** for lightposts, dumpster, critters, grass — separate future spec, once
  these mechanics are proven with placeholder shapes.
- **General spawn-zone authoring system** for map building (the broader tool the user
  wants eventually, so designers can paint arbitrary spawn rules for props/items/
  playable characters) — out of scope here. This spec implements the *specific* rules
  requested (dumpster/lightpost adjacency) as plain code checks, which doesn't block
  building the general tool later.
- **Building lean/parallax visual mechanic** — fully separate spec (pure rendering,
  no lighting/noise/fog involvement, brainstormed separately).
- **Dumpster fire as an aggro/noise-attraction source** — explicitly declined; it only
  dampens gunshot noise, it doesn't attract zombies itself.
- **Grass noise-damping** — explicitly out of scope; only the dumpster dampens noise.

## Testing / verification

Per CLAUDE.md: verify in the live editor (MCP `project_run` + `logs_read`), not headless
(headless `--import`/`--script` runs risk corrupting `.godot/` while the editor is open,
and headless `class_name`-extending-scene-type tests don't resolve anyway). Pure-logic
pieces (placement adjacency rules, cone/diamond reveal math) should get `extends
RefCounted` static helpers with their own `test/` scripts, runnable with the editor
closed. The cross-role flashlight visibility (§4) and critter flee behavior (§5) need
an actual two-role playtest to confirm — there's no way to drive both a shooter and a
zombie-commander view simultaneously through the MCP game-capture bridge alone.
