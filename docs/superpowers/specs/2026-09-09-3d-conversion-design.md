# 3D conversion — design

**Date:** 2026-09-09 · **Phase:** 10 · **Status:** design approved, not yet implemented

Converts *Zombie Game* from top-down 2D to a 3D world. The shooter plays in
**first person**; the zombie commander keeps its top-down RTS view, but of the
3D world rather than a 2D map. Every existing mechanic is preserved except the
headshot model, which is replaced (§6).

Companion docs: [PROJECT.md](../../../PROJECT.md) → *3D conversion* for current
state, [CHANGELOG.md](../../../CHANGELOG.md) → Phase 10 for the measured
history of the camera work, [BACKLOG.md](../../BACKLOG.md) § D2 for open items.

---

## 1. Decisions locked

| # | Decision | Consequence |
|---|---|---|
| D1 | **Shooter camera is first person (V4).** | Closes the four-version camera trial. |
| D2 | **Commander stays top-down, above the roofline.** | Needs occlusion handling (§7). |
| D3 | **Buildings/roofs go ~90% transparent when a zombie is underneath.** | Roofs must be separable meshes (§8). |
| D4 | **Zombies get per-part HP** — Head, Body, Arm L/R, Leg L/R. | Replaces global HP (§6). |
| D5 | **Death on Head → 0 or Body → 0.** Limbs never kill. | Limbs are control, not damage. |
| D6 | **No bleed** from limb damage into the body pool. | Every shot is a decision. |
| D7 | **Legs:** 1 lost → hobble; 2 lost → crawl animation. | New zombie state. |
| D8 | **Arms:** 1 lost → slower attack; 2 lost → still attacks, weakly. | Never fully harmless. |
| D9 | **Build 3D as a parallel scene tree**, cut over at the end. | 2D game keeps working throughout. |

## 2. Why parallel rather than in-place

The 2D game is the only working reference for whether a ported mechanic still
*plays* right. Rewriting in place destroys that reference exactly when it is
most needed. So 3D is built under new paths (`scenes/world3d/`, `scripts/3d/`)
reusing the dimension-agnostic helpers, and the 2D scenes are retired only at
cutover (S11).

This is cheap because most of the codebase is not dimensional:

**Ports unchanged** — `balance.gd` (after §5), `loot_table.gd`,
`interact_pick.gd`, `lobby_model.gd`, `network.gd`, `game_state.gd`,
`settings.gd`, `merge_manager.gd` pairing math, `ui_theme.gd` / `ui_style.gd`,
all menu/loading/settings/pause/game-over scenes, the Go director and server
pool.

**Rewritten** — `bullet.gd`, `blood_canvas.gd`, `minimap.gd` +
`minimap_math.gd`, `fog_zombie_controller.gd` + `fog_zc.gdshader`,
`shooter_lighting.gd`, `zombie_lighting.gd`, `prop_occluder.gd`,
`aim_cursor.gd`, tile-grid pathing, and the movement/aim halves of
`shooter.gd`, `zombie.gd`, `npc_human.gd`.

**Deleted outright** — the shooter's 2D fog-of-war stack. See §4.

## 3. What already exists

`scripts/test/test_player.gd` (498 lines) and `scripts/test/camera_rig.gd`
(494 lines) are a working 3D locomotion + aim + flashlight prototype: walk
3.00 / sprint 5.64 / crouch 1.40 m/s, jump apex 1.07 m with tuned non-physical
gravity, stance-driven reticle volume, camera collision (384-sample sweep, zero
clips), night lighting with volumetric fog and a flickering practical.

`test_player.gd` is the seed of the 3D shooter. `camera_rig.gd`'s collision and
occlusion logic feeds the **commander** rig, not the shooter — first person
needs none of it.

## 4. What first person deletes

In first person you see only what is lit and in front of you. The flashlight,
volumetric fog and real shadows **are** the shooter's fog of war. This retires
`shooter_lighting.gd`, the `prop_occluder` polygon system and the whole faked-LOS
layer, and removes what was the highest-risk stage of the conversion.

Only the **commander's** fog still needs a real 3D design (S8).

## 5. Units: pixels → metres

The 2D game is tuned in pixels. The 3D prototype walks at 3.00 m/s against
`SHOOTER.speed = 105` px/s, implying **≈35 px per metre**. Every other value
converts to a physically sensible number at that constant:

| 2D | → 3D | Reads as |
|---|---|---|
| `ZOMBIE.speed` 42.5 | 1.21 m/s | shamble |
| `FAST.speed` 110 | 3.14 m/s | run |
| `FAT.speed` 38.25 | 1.09 m/s | lumber |
| `MASTER.speed` 30 | 0.86 m/s | slow advance |
| `contact_px` 38 | 1.09 m | melee reach |
| `PISTOL.optimal_range_px` 640 | 18.3 m | street length |
| `RIFLE.optimal_range_px` 1024 | 29.3 m | down the block |
| `SHOTGUN.optimal_range_px` 320 | 9.1 m | room-to-room |

So balance **converts** rather than gets re-invented: one mechanical pass over
`balance.gd` with a single constant. **Validate, don't assume** — S3 confirms
the constant against the prototype before the rest of the conversion leans on
it. Sprint (5.64 m/s) has no 2D equivalent and is new tuning.

## 6. Damage model — per-part HP

### 6.1 Why the 2D model cannot port

`AimModel.is_headshot()` is not a headshot. It tests whether the bullet's path
passes within `HEADSHOT.radius_px` (5 px) of the zombie's **origin** — a
centre-mass disk — and multiplies damage 4×. `docs/BACKLOG.md` § C already flags
the result as broken: headshots one-shot zombies and fire far too often.

In 3D the head is real geometry, so the model is replaced entirely rather than
retuned. First person also fixes the frequency problem structurally: the head is
a small, moving, often body-occluded target, so a headshot is earned by aim
rather than granted by a proximity test.

### 6.2 Parts and pools

Six colliders, six independent HP pools: **Head · Body · Arm L · Arm R ·
Leg L · Leg R**. There is **no global HP pool**; `Balance.<VARIANT>.max_hp`
becomes the *body* pool, so existing per-variant tuning carries over.

| Variant | Head | Body | Leg (ea) | Arm (ea) |
|---|---|---|---|---|
| Standard | 35 | 150 | 50 | 40 |
| Fast | 30 | 150 | 35 | 35 |
| Fat | 105 | 750 | 120 | 90 |
| Master | 140 | 450 | 90 | 70 |

Sized against current weapon damage (pistol 35 · rifle 87.5 · shotgun 28×5 ·
MG 22), so:

- A pistol headshot one-shots a standard zombie; 5 body shots do the same job.
- A rifle one-shots any head **except** fat's — "send the fat ones first"
  becomes real commander counterplay rather than a stat line.
- Both legs off a standard zombie costs 4 shots against 5 for a kill, so
  crippling is a genuine choice under ammo pressure, not a free action.
- The shotgun's 5 pellets scatter across parts, making it a close-range limb
  shredder with no special-casing.

### 6.3 Rules

- **Death:** Head → 0 **or** Body → 0. Nothing else kills. (D5)
- **No bleed:** limb damage never reduces the body pool. (D6)
- **Legs:** one destroyed → hobble, `speed × 0.5`. Both destroyed → crawl
  animation, `speed × 0.2`, hitbox drops to ground height. Still lethal on
  contact — and at night a crawler is genuinely hard to see, which quietly
  makes it one of the commander's better units. (D7)
- **Arms:** one destroyed → `attack_interval × 1.6`. Both destroyed → the
  zombie still attacks, at `attack_interval × 2.4`. Never fully harmless. (D8)
  *These two multipliers are proposed starting values, not measured ones —
  they land in `Balance` and are expected to move after the first playtest.*
- **Damage falloff** (`AimModel.damage_mult`) applies before the zone lookup,
  unchanged in behaviour.

### 6.4 Accepted risk

Because limbs never feed the body pool, a player who sprays and clips limbs
kills **nothing**. This is a deliberate tightening of the ammo economy versus
the 2D game and is the single number most likely to need revision after the
first playtest. Revisit only with playtest evidence; do not pre-emptively soften
it, or the "limbs are control, body is damage" rule stops being legible.

### 6.5 Hit resolution

Server-authoritative. The shot is a ray from the muzzle toward a random point
inside the reticle sphere (the model `test_player.gd` already implements:
0.95 m hip → 0.28 m aimed over `reticle_settle`, scaled by stance). The first
part collider hit determines the zone. **No proc roll anywhere** — spread
geometry is the only randomness, so a shot the player lined up is never
overridden by a dice throw.

### 6.6 Replication

Clients do not need exact part HP. Replicate a **6-bit destroyed-part mask**
plus the coarse body HP already used by the health bar; part HP stays
server-side. Destroyed-part changes are events, not per-frame state.

## 7. Commander view

Top-down over the 3D world (D2), free-flying/orbiting, **above** the roofline —
the opposite of the shooter cameras, which the Phase 10 trial deliberately drove
*below* it.

**Occlusion (D3):** any building, tunnel or overhang goes ~90% transparent while
a zombie is underneath it. This replaces the shooter's cover-swoop answer, which
does not generalise: the commander tracks a horde spread across a city, not one
body, so the camera cannot dive under a roof.

Also needed: selection box + click-to-ground raycast (replacing
`_screen_to_world` / `_make_world_rect` in `zombie_controller.gd`), unit
silhouettes through geometry, order pings in 3D, and a minimap sourced from the
3D world.

**Commander fog of war (S8)** stays a real open problem. The 2D system
(per-zombie LOS vision lights + tile-grid explored memory) does not port.
Deferred to its own design; do not let it block S1–S7.

## 8. Assets

**Pipeline:** poly.pizza low-poly packs → **Blender** → glTF → Godot. Sourced
packs cover weapons, human/player, zombie and rat.

Establish conventions on **one reference asset end-to-end before mass
production**: metric scale (1 unit = 1 m), −Z forward, material naming,
collision-shape convention, LOD policy, where lights live.

### 8.1 Character mesh separation (confirmed)

The human/player model is **five meshes sharing one `CharacterArmature`**, split
by costume region rather than by limb:

| Mesh | Tris | Holds |
|---|---|---|
| `Adventurer_Head` | 3,620 | head |
| `Adventurer_Body` | 3,528 | torso + both arms |
| `Adventurer_Legs` | 822 | both legs |
| `Adventurer_Feet` | 480 | boots + lower-leg overlap |
| `Backpack` | 1,748 | rides on `Chest` |

Per-limb vertex groups are present and correctly named — `UpperArm.L/R`,
`LowerArm.L/R`, `UpperLeg.L/R`, `LowerLeg.L/R`, `Foot.L/R` — so
**Separate-by-Selection works**. Severable set: head, L arm, R arm, L leg,
R leg, backpack.

Two wrinkles the implementation must handle:

1. **Legs span two meshes.** A leg lives in both `Adventurer_Legs` and
   `Adventurer_Feet`, so one leg is **two fragments that must be hidden
   together** — you cannot drop the trouser and leave the boot floating. Model
   a limb as a *list* of mesh fragments, not one mesh.
2. **Weights are not binary.** Select-by-group in Edit Mode grabs everything
   above weight 0, pulling in the blend band around each joint. Cut lines need
   tightening by hand or an arm takes a ring of shoulder with it.

Arms are clean (`Adventurer_Body` owns them outright). `Backpack` is entirely
`Chest`-weighted — a free toggle.

**Still to confirm:** the same pass on the **zombie** model. The key question is
whether it shares this skeleton — if so, animations are interchangeable and one
separation procedure covers both.

**Fallback if a rig resists separation:** scale the limb's bone to ~0 in Godot.
Zero Blender work, works on any rig, looks worse (no stump). Route A is
preferred; this exists so the damage model can never be blocked by a model.

### 8.2 Library

Each item wants a low-poly model, a collision shape, and — where it emits or
blocks light — a light setup.

- **Vehicles:** car, broken/burnt car, van/truck. Double as cover.
- **Street furniture:** dumpster (plain + burning), lightpost lit, lightpost
  dark/broken, bins, benches, bollards, barriers.
- **Fences:** chain-link and slatted — **must transmit light** (alpha or real
  gaps); the night look is built on beams and shadow.
- **Vegetation:** trees, shrubs, hedges, grass.
- **Facades:** windows, doors, shopfronts, ground-floor detail. The OSM greybox
  is flat untextured wall — the "canyon you are inside" reading depends on this
  more than on any other asset.
- **Characters:** shooter, zombie variants (standard/fast/fat/master), NPC
  survivors. Rigged, animated, limb-separated per §8.1. Animations needed:
  idle, walk, run, attack, hobble, crawl, death.
- **Critters:** rats, bugs, fireflies.
- **Buildings:** roofs as **separate meshes with their own material instance**,
  or D3's transparency cannot be driven per-building.

### 8.3 Map

The current greybox (`assets/city/copenhagen_greybox.glb`, OSM via blosm,
**ODbL 1.0 — attribution required**, see `CREDITS.md`) has a 208 × 602 m visual
extent but **collision only in a ~85 × 120 m patch** at its southern end;
everything beyond is visual-only geometry a player would fall through. Tallest
building 23.0 m.

A replacement map is being authored. Build **one block end-to-end first** —
import it, confirm scale, confirm the nav bake, confirm a roof actually goes 90%
transparent with a zombie underneath — *then* mass-produce. A wrong convention
is cheap to fix on one block and brutal across a finished city.

## 9. Stage plan

| # | Stage | Depends on | Notes |
|---|---|---|---|
| S0 | ~~Pick shooter camera~~ | — | **Closed: first person (D1)** |
| S1 | Asset pipeline + library | — | Starts now, parallel. §8 |
| S2 | World: nav bake, collision, materials, 3D prop scatter | S1 | **Slice, not city.** §9.1 |
| S3 | Units pass px → m | — | §5. Mechanical, testable, unblocks S4–S6 |
| S4 | Shooter (first person) | S2, S3 | Seeded by `test_player.gd` |
| S5 | Zombies: variants, merging, part hitboxes, crawl | S1, S3 | §6 lands here |
| S6 | Ballistics + zone resolution + FX | S4, S5 | Server-authoritative |
| S7 | Commander view + roof transparency | S2, S5 | §7 |
| S8 | Commander fog of war | S7 | Own design; shooter's is free |
| S9 | NPC survivors | S5 | |
| S10 | Netcode + HUD reconnect | S4–S8 | `Vector3` + pitch; 6-bit part mask |
| S11 | Cutover; retire 2D scenes | all | |

### 9.1 S2 is a slice, not a city

S2 needs a **playable slice**: a nav bake, collision, materials and prop scatter
on one street. The existing greybox corridor is already adequate. The full map
is an art track running **parallel to** systems work, never ahead of it —
building a city before the systems exist is the expensive way to be wrong.

Port the *placement rules* in `prop_scatter.gd` (dumpster against a building or
on the street; lightpost on sidewalk bordering the road, head facing the
carriageway) — they are good and largely dimension-agnostic.

## 10. Open questions

1. **Commander fog of war** (S8) — no design yet. Highest remaining risk.
2. **Zombie model separation** — §8.1 pass not yet run on the zombie; shared
   skeleton unconfirmed.
3. **px→m constant** — 35 is derived, not yet validated (S3).
4. **Crawler pathing** — a ground-height hitbox interacts with `NavigationMesh`
   agent radius/height; may need its own nav layer.
5. **Fat-zombie head at 105 HP** — deliberately survives a rifle shot. Confirm
   that reads as counterplay and not as the game ignoring the player.
6. **Ammo economy** under §6.4. Playtest-gated.

## 11. Out of scope

- Rebalancing beyond the mechanical px→m conversion.
- New weapons, zombie variants or mechanics.
- Web export (already dropped; itch.io downloadable builds only).
- Any change to the Go director / server pool.
- Player-character dismemberment — §6 covers zombies only.
