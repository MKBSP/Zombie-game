# Backlog

Open work only, grouped by theme. Completed items live in [CHANGELOG.md](../CHANGELOG.md).
Keep this current: check items off here, move finished ones to the changelog.

## Now: open tracks (in this order unless Mads changes it)

All phases are in `docs/superpowers/plans/2026-11-25-3d-game.md` (approved 2026-11-25).

0. **3D game shell** (phase 1), done 2026-11-25. See CHANGELOG.
    - [x] Main menu: PLAY → shooter or zombie commander → the 3D city.
          MULTIPLAYER hidden until 3D multiplayer (S10) works.
    - [x] ESC menu in game: resume, switch role, cheats (all weapons + unlimited
          ammo), settings, restart, quit to menu. TAB and F9 stay as shortcuts.
    - [x] 2D files kept: 3D multiplayer reuses the online lobby and relay, and
          the Railway server still runs the 2D game. Delete at S11.
    - [x] Tester builds: macOS + Windows presets, instructions in DEPLOY.md Part 3.
    - [ ] Owner playtest from the menu, both roles, and the Mac build on a
          second laptop. The Windows build has never been run.
    - [ ] Hide the cheats menu item before any public release.
1. **Test museum.** Phase 2 (zoo, lighting lab, facade wall, stand-in props,
   menu button) is done (2026-11-25). Phase 3 (stations + gym) is next. See
   section D3.
    - [ ] The commander view in the museum is black (fog of war, no zombies yet).
          Phase 3's commander station adds a few.
2. **3D HUD** (phase 4). The mockup (v4) is at https://claude.ai/artifact/5hAuRpAShsPkGvKjN127Mc.
   The commander panel is laid out like Age of Empires II: three fixed slots, with
   commands, selection and the whole-city map.
    - [ ] Build it as the plan says. It shows the loadouts the game has now;
          dual-wielding and the one-/two-hand bat grip are separate features (below).
    - [ ] Fix the shooter minimap showing zombies it shouldn't.
    - [x] The H tuning panel is hidden by default (2026-11-25).
    - [x] `docs/design_system.md` matches the v2 palette (2026-11-25).
    - [ ] Later features the mockup shows: a gun in each hand (LMB right, RMB
          left, no aiming), and switching the bat between one and two hands.
3. **Online multiplayer in 3D** (phase 5, stage S10: netcode + HUD reconnect). See section D2.
4. **Delete the 2D game** (phase 6, stage S11).

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
- [x] NPCs run away when spotted by zombies (2026-11-17, 3D): 80% run for cover away from the zombie, 20% freeze and cower.
- [ ] Order menu: `E` near an NPC → Stay / Equip / Go to point / Hold ground &
      shoot on sight / Hide (don't shoot unless attacked).
- [x] Fix the weapon "handover" to NPCs (2026-11-17, 3D): the heavy and its real ammo move over and back.
- [ ] NPC aim upgradeable in skill tree (base 20% aim debuff exists).
- [ ] Tooltip: "Press E to equip {weapon}" when near an NPC (box tooltip done).
- [ ] Humans can adopt dogs.

## C. Shooter feel & combat tuning

- [ ] Headshots: stop one-shotting zombies; too common. Options: smaller head
      hitbox / "tunnel" (bullet must fully cross the head box) / 5% proc chance
      on head hit, upgradeable via skill tree. (Smaller bullets alone didn't fix it.)
- [x] Damage animation (hit feedback) (2026-11-17, 3D): blood, flinch, limb gore, crosshair hitmarker.
- [ ] Speed debuffs when injured: 50–99% hp → −10% speed; 1–49% hp → −20% speed.
- [x] Carry limits (2026-11-17, 3D): pistol + torch always, one heavy, one melee (only one handgun exists in 3D). F9 cheat for all, debug builds.
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

Every new asset goes into the test museum's zoo (D3) as soon as it lands.

**Source (decided 2026-11-25):** free low-poly models from [Poly Pizza](https://poly.pizza)
for now, as rough stand-ins until the style gets dialled in. Prefer CC0 authors
(Quaternius, Kenney). CC-BY models (e.g. "Poly by Google") are fine but get a
line in CREDITS.md. Each model is scaled to real metres, sits on the ground and
gets a collision box. Burnt = the same model with a charred material. Burning =
burnt + the shared fire effect. Anything Poly Pizza lacks gets a simple Blender
model.

- [x] (stand-ins, 2026-11-25) **Vehicles:** cars of several types, a bus, a truck. Each one intact,
      burnt-out and burning. They also work as cover.
- [x] (stand-ins, 2026-11-25) **Street furniture:** dumpster (plain + burning), trash cans, bags of trash,
      cinder blocks, street blockades, shopping cart, benches, bollards.
- [x] Lightposts: working, blinking, dead, sparking and fallen (`StreetLight`).
- [x] (2026-11-25, `Fire3D`) **Fire:** flames + smoke + a flickering light, shared by burning cars,
      dumpsters and barrels.
- [ ] **Fences:** chain-link and slatted — must let light *through* (alpha or
      real gaps), since the night look is built on beams and shadow.
- [x] (stand-ins, 2026-11-25) **Vegetation:** trees, shrubs, hedges, and grass and weeds, all overgrown.
- [ ] **Facades:** the small city has procedural facades (windows, doors,
      shopfronts, lit windows), but they don't look good enough yet. Rework
      them on the museum's facade wall (D3).
- [ ] **Characters:** shooter, zombie variants (standard / fast / fat / master),
      NPC survivors — modelled, rigged and animated. Head bone required if
      headshots become geometric.
- [ ] **Critters:** rats, bugs, fireflies (3D versions of the 2D ambient life).
- [ ] Place the props in the city (`Prop3D` can be added by hand). Replace the stand-ins once the style is set.
- [ ] Decide the pipeline (Blender + glTF; hand-modelled vs. kitbash vs. bought
      packs) and a shared material/scale convention before mass-producing.

## D3. Test museum (zoo · museum · gym)

One test scene, `scenes/test/museum.tscn`, where you can look at every asset
under any light, test each system on its own, and tune the look, without
hunting across the city. Open it from the main menu's **Test museum** button
(track 0). Until that lands, open the scene in the editor and press **F6**, the
same as the v6 test map. Number keys jump between areas. The ESC menu swaps
between shooter and zombie commander and turns cheats on. H opens the tuning
panel. Everything has a name sign.
The floor is a grid marked in metres. Nothing in the real game changes.
A design doc comes before building.

**Step 1: zoo, lighting lab, facade wall** (done 2026-11-25, plan phase 2)
- [x] Lighting lab: a panel to set sunlight (strength and angle, i.e. time of
      day) and ambient/moonlight. Lights you can pick up, carry and drop next
      to any asset: flickering lamp, fire, street light, torch. Presets: game
      night, torch only, neutral daylight. A grey ball, a chrome ball and a
      colour chart to judge colour and darkness the same way every time.
- [x] Zoo: every asset on display. The four zombie types, the survivor models,
      the Adventurer, every weapon (world model and first-person), the crate
      (closed and open), every loot item, every street-light state. New files
      in the asset folders show up without editing the scene.
- [x] Survivors and crates in the open, to test recruiting, giving a gun and
      opening a crate.
- [x] Facade wall: every facade variant using the same shader as the map, to
      rework them in one place. That covers all five wall types (shop street,
      residential street, alley, back, blank party wall with ghost sign), brick
      and stucco, a few heights and random seeds, and roofs.

**Step 2: museum.** Stations that each show one game system working, with a
sign that says what to try:
- [ ] Shoot off each body part (zombie crawls without legs, and so on).
- [ ] A pen where zombies chase you, search, and lose sight of you.
- [ ] A wall of every surface to shoot, for bullet holes, dust and sparks.
- [ ] Survivors: recruit, give a gun, watch them shoot.
- [ ] Commander fog of war.

**Step 3: gym.** The player's measurements:
- [ ] Firing range with markers at 5, 10, 20 and 40 m (spread and damage).
- [ ] Doors, stairs and slopes, with their sizes marked.
- [ ] A walk and sprint track.

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
