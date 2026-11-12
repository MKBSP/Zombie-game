# Backlog

Open work only, grouped by theme. Completed items live in [CHANGELOG.md](../CHANGELOG.md).
Keep this current: check items off here, move finished ones to the changelog.

## A. Zombie commander experience (current pain points — Phase 9b)

- [x] **Zombie fog rework** (2026-07-10) — shooter-style lighting fog with
      per-zombie LOS vision lights + unexplored-black explored memory
      (`ZombieLighting`, `FogZombieController.tile_line_clear`).
    - [x] The order ping when ordering a zombie renders **on top of** the fog (already fixed — z 150 over fog z 100).
- [x] **Right-click attack targeting** (2026-07-10) — right-click an NPC/shooter
      snaps selected zombies onto it (`attack_target`, red ping); lock holds
      while any zombie sees the target, then degrades to last-seen move.
- [ ] Right-click another zombie → follow it. If the target is large, small
      zombies form a line behind it (cover from bullets) and slow to match speed.
      Multiple followers extend the line.
- [ ] Click on the minimap/map to send selected zombies there.
- [ ] Zombie AI (consider [LimboAI](https://github.com/limbonaut/limboai)).
- [ ] Better pathfinding for zombies.
- [ ] Zombie HUD (commander overlay parity with shooter HUD polish).

### New zombie skills
- [ ] Big zombie: bash / splash attack.
- [ ] Big zombie: throw a normal zombie forward (gap-closer; thrown zombie loses 10 hp).
- [ ] Master zombie: summon skeletons/zombies in open fields / cemetery.
- [ ] Control zombie rats.
- [ ] Control zombie bird.
- [ ] Zombies can convert dogs.
- [ ] Zombies can drag boxes.
- [ ] Zombies can hide in dumpsters.

## B. NPC behavior

- [x] **Follow pathing fix** (2026-07-10) — NPCs retrace the shooter's breadcrumb
      trail single-file (`NpcFollow.trail_point`).
- [x] Formation (2026-07-10): NPCs stand *behind* the shooter, never between
      shooter and zombies (`NpcFollow.formation_slot`).
    - [x] 1 armed NPC → behind player, offset to one side; unarmed NPCs stack behind.
    - [x] 2 armed NPCs → one on each side of the player.
- [ ] NPCs run away when spotted by zombies.
- [ ] Order menu: `E` near an NPC → Stay / Equip / Go to point / Hold ground &
      shoot on sight / Hide (don't shoot unless attacked).
- [ ] Fix the weapon "handover" to NPCs.
- [ ] NPC aim upgradeable in skill tree (base 20% aim debuff exists).
- [ ] Tooltip: "Press E to equip {weapon}" when near an NPC (box tooltip done).
- [ ] Humans can adopt dogs.

## C. Shooter feel & combat tuning

- [ ] Headshots: stop one-shotting zombies; too common. Options: smaller head
      hitbox / "tunnel" (bullet must fully cross the head box) / 5% proc chance
      on head hit, upgradeable via skill tree. (Smaller bullets alone didn't fix it.)
- [ ] Damage animation (hit feedback).
- [ ] Speed debuffs when injured: 50–99% hp → −10% speed; 1–49% hp → −20% speed.
- [ ] Carry limits: max 2 handguns + 1 two-handed (rifle/shotgun/MG). (Melee limit of 1 done.)
- [ ] Melee: knockback, combos, charge attacks.
- [ ] Fear system (impact TBD).

## D. Map & content

- [ ] **Bigger map** (~4× current size — ties into art v1, Phase 8).
- [ ] Map generation: random NPC/resource spawning on fixed map (Phase 5).
- [ ] Proper sprites & art v1: simple zombies/shooter/map, simple animation, smaller bullets (Phase 8).
- [ ] Art v2: animations, fire, light, parallax buildings, sound, reactions, blood trail (Phase 10).
- [ ] Sound.

## D2. 3D conversion (Phase 10 — in progress)

See [PROJECT.md](../PROJECT.md) → *3D conversion* for what exists today and
[CHANGELOG.md](../CHANGELOG.md) → Phase 10 for the measured history.

- [x] Renderer moved to Forward+ (2026-09-08); 2D game verified unaffected.
- [x] Copenhagen greybox from OSM/blosm (`assets/city/`, ODbL — see CREDITS.md).
- [x] Four camera/aim versions + night twins, one shared rig (8 scenes).
- [x] Cover swoop, camera collision (384-sample clip audit, zero clips),
      unified aim pose, walk/sprint/crouch/jump, night lighting + flashlight.
- [x] **Shipping shooter camera picked: first person (V4)** (2026-09-09).
- [x] **Design spec written** (2026-09-09) —
      `docs/superpowers/specs/2026-09-09-3d-conversion-design.md`. Read it
      before starting any stage below; the S-numbers here match its §9.
- [ ] **Visibility / eye adaptation** — model + live tuning HUD in the v5
      Manhattan scene; see `docs/superpowers/specs/2026-09-16-visibility-and-eye-adaptation.md`.
      Record the settled slider values there. Better minimap reference pending.
- [ ] Manhattan GLB: road/footway surfaces sit at y = 0.31, ground collision at
      y = 0 — re-export with the intended 1–2.5 cm stack.
- [ ] **S8 — commander fog of war in 3D.** No design yet; highest remaining
      risk. The shooter's fog dissolves in first person (real lights + shadows
      do the work), so only this half survives.
- [ ] Confirm the **zombie** model separates per §8.1 (the human model does —
      five meshes, one armature, per-limb vertex groups present). Key unknown:
      does the zombie share the skeleton?
- [ ] Validate the **35 px/m** conversion constant against the prototype.
- [ ] **Zombie-commander view in 3D.** Stays a top-down RTS view, but of the 3D
      world — free-flying/orbiting camera over the same geometry, not a
      separate 2D map. Open: occlusion (roofs hiding units), fog-of-war in 3D,
      selection box + click-to-ground raycast, minimap source.
- [ ] **Headshots in 3D.** The 2D model (`AimModel.is_headshot` — a 5 px
      centre-mass disk) has no 3D meaning. See section C: headshots already
      one-shot too often in 2D, so the 3D design must solve both at once.
- [ ] Port the game systems onto 3D bodies: shooter, zombies + variants +
      merging, NPCs, bullets/ballistics, loot boxes, pickups, melee.
- [ ] Fog-of-war in 3D for both roles (2D `Light2D` occluders do not port).
- [ ] Navigation: `NavigationRegion3D` baked off the greybox, replacing the
      TileMap-grid pathing.
- [ ] Netcode: replicate `Vector3` + basis instead of `Vector2` + rotation;
      confirm the director/server pool is unaffected.
- [ ] Decide the fate of 2D-only systems: `blood_canvas`, tile-grid explored
      memory, `minimap_math`, `fog_zc.gdshader`.

### 3D asset library (needed for the conversion; greybox has none of it)
Street dressing, in rough priority order. Each wants a low-poly model, a
collision shape, and — for anything that emits or blocks light — a light setup.

- [ ] **Vehicles:** car (intact), broken/burnt car, van/truck. Also cover.
- [ ] **Street furniture:** dumpster (plain + burning), lightpost with a working
      lamp, lightpost dark/broken, bins, benches, bollards, barriers.
- [ ] **Fences:** chain-link and slatted — must let light *through* (alpha or
      real gaps), since the night look is built on beams and shadow.
- [ ] **Vegetation:** trees, shrubs, hedges, grass/weeds.
- [ ] **Facades:** the OSM greybox has flat untextured walls — needs windows,
      doors, shopfronts, ground-floor detail, so the canyon reads as a street.
- [ ] **Characters:** shooter, zombie variants (standard / fast / fat / master),
      NPC survivors — modelled, rigged and animated. Head bone required if
      headshots become geometric.
- [ ] **Critters:** rats, bugs, fireflies (3D versions of the 2D ambient life).
- [ ] Decide the pipeline (Blender + glTF; hand-modelled vs. kitbash vs. bought
      packs) and a shared material/scale convention before mass-producing.

## E. Meta / systems

- [ ] Menu: settings screen content (toggle tooltips — default ON, profile/user/stats,
      control remapping for shooter + zombie hotkeys), animations/background/art.
- [ ] Shooter AI (bot shooters).
- [ ] Levels: XP → level gain → skill tree upgrades.
- [ ] Online ranking + level-based matchmaking.
- [ ] Gear, saving, skill tree.

## Phases remaining

| Phase | Scope |
|-------|-------|
| 5 | Map generation (random NPC/resource spawning on fixed map) |
| 8 | Art v1 (simple sprites, 4× map, simple animation, smaller bullets) |
| 9a | Fix-list: shooter items (section C) |
| 9b | Fix-list: zombie items (section A) |
| 10 | **3D conversion** (section D2) — supersedes the old "Art v2" scope |
| 11 | Playtest with real players |
| 12 | Landing page |
