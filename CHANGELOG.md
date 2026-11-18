# Changelog

Phase-organized history (newest first), reconstructed from git. Append a line
here as part of finishing any meaningful change.

## Phase 10 — 3D conversion (in progress)
- **Commander zoom + minimap, casing crash (2026-11-18).**
  - **Crash:** after about 30 shots in a session the game froze into the editor's
    debugger ("Trying to assign invalid previously freed instance" in `viewmodel._shell`):
    the casing list kept casings their 4 s timer had freed, and the cap pulled one into a
    typed variable. Now untyped. Test: `test_fp_aim.gd`.
  - **Zoom:** only real wheel clicks zoomed; a MacBook trackpad sends two-finger scroll as
    a pan gesture. `Commander.zoom_factor` takes the wheel, trackpad scroll, pinch and -/=.
  - **Minimap** (`scripts/3d/commander_map.gd`, top right): the whole city under the
    horde's fog (black never seen, dim explored, clear seen) with "Explored N%"; zombies
    (selected white), enemies only while seen, the camera's view, and each gunshot as a
    ring of zombie hearing (70 m) for 4 s. LMB/drag looks there, RMB sends the selection.
    Test: `test/test_commander_map.gd`.
- **Dust puffs instead of sparks (2026-11-17).** Shots into walls, ground and wood threw
  10-12 tiny fast specks that the torch lit up like sparks. They now raise a soft dust
  puff: 3-5 blobs that drift slowly off the surface, grow 2.5x and fade over about 1 s,
  shown only where light falls (`Balance.IMPACT` `puff`, `puff_grow`, `puff_alpha`;
  `ImpactFx.burst`). Sparks only off metal (lamp posts); glass and blood unchanged.
- **First-person aim fixes (2026-11-17).**
  - **Minimap:** its camera drew the commander's render layer, so the shooter saw the
    zombies' fog of war (black, streets hidden) and their markers. `test_hud.gd` now
    leaves out `Zombie3D.COMMANDER_LAYER`.
  - **Spread:** the reticle sphere had a fixed radius in metres (0.95 hip, 0.28 aimed),
    so close shots sprayed and far ones were near-perfect. Spread is now an angle
    (`spread_deg_hip` 3.5, `spread_deg_aim` 1.0, `TestPlayer.spread_radius`): the sphere
    grows with distance. Each pellet flies from the gun's muzzle to a random point in
    the sphere (`viewmodel.shot_origin`; from the eye when something sits between eye
    and muzzle).
  - **Pitch:** first person looks 85° up and down (`Balance.FP.pitch_deg`, was ±28° from
    the shoulder-cam trial). Looking steeply down, the aim stays where you look
    instead of jumping 12 m ahead. Test: `test/test_fp_aim.gd`.
- **Review fixes (2026-11-17).**
  - **Crate items:** they could land inside the building behind a crate (navmesh islands
    in the hollow shells) or inside the crate itself, which hit 25 of 65 items on the v6
    map. `LootCrate._landing` now tries 8 directions and accepts only an outdoor,
    reachable spot at least 0.7 m from the crate; failing that, the item rests on the
    open crate. Re-check: 66 of 66 good.
  - **Shots and loot:** pickups no longer stop bullets or catch the reticle. The new
    `ImpactFx.SHOT_MASK` covers everything but zombie capsules and loot, and is used by
    the shooter, the survivors and the bat. Bat hits on zombies now bleed.
  - **Blocked survivors:** a relocate or flee leg far over its expected time
    (`Npc3D.leg_overdue`) now counts as blocked, so a crate in the way can't trap a
    survivor. Relocation also gets the 0.3 s "finished before the first path" grace.
  - **Death clip:** it no longer replays on a loop on a dead survivor (pre-existing).
- **Survivor cower pose (2026-11-17).** None of the survivor models has a crouch, so
  `character_anim.gd` gets `freeze(clip, at)` / `unfreeze()`, which hold one frame of any
  clip. The frames were picked from contact sheets: Business Man and Hoodie use the crouch
  just before a Roll (0.12), Man the squat at the start of Standing (0.0). Each is in
  `Npc3D.MODELS`. A cowering survivor drops into it with no blend, and gets up as soon
  as it leaves COWERING (calm, recruited or bitten). Tested in `test_npc_hiding.gd`.
- **Survivors hide in cover, flee or freeze when spotted (2026-11-17).** `npc_3d.gd`:
  - **Hiding spots:** a hiding spot is now the best of 16 candidates, each slid against
    the nearest wall (`spot_by_wall`) and scored by `cover_score`. That counts how many of
    8 rays, 4 m long, hit a building: against a wall 3, alley 6. A spot needs 3, must be
    outdoors, unseen by the horde, and `reachable`.
  - **Courtyards:** enclosed courtyards are navmesh islands nobody can walk into. They
    used to win on cover, so survivors "arrived" without moving. Survivor spawns and
    crates now require reachability from the shooter too.
  - **Spotted:** every 0.2 s a hidden or relocating survivor checks whether a zombie can
    see it (`can_see`, the fog's test). One roll per sighting (`react()`, `NPC_3D.freeze_chance` 0.2).
  - **FLEEING:** the survivor runs at 4.5 m/s to cover at least 18 m from that zombie, on
    the far side of it, along a route that never loops back past it
    (`path_keeps_away`). It hides again on arrival if unseen, or runs on (up to 3 legs,
    then cowers).
  - **COWERING:** it freezes until no zombie has seen it for 6 s.
  - **Unchanged:** followers never react; walking into one still recruits it; a bite
    still converts it.
  - **Fixed:** "navigation finished" is ignored for the first 0.3 s of a leg, since the
    agent says so before its first path.
  - **Tests:** `test_npc_hiding.gd` (cover, outdoors, angled walls, `path_arrives`,
    `path_keeps_away`, `react`).
- **Crates spread evenly over the map (2026-11-17).** `scripts/3d/loot_scatter.gd` is a pure,
  seeded jittered grid: about `crate_count` near-square cells in a seeded order, one point
  per cell, at least `min_sep_m` apart. A cell with nowhere valid stays empty.
  `LootCrate.spawn_all()` runs it over the baked navmesh's bounds once the commander has
  spawned the horde. Each spot snaps to the navmesh, must be under open sky
  (`Npc3D.outdoors`), and slides to the nearest building wall within 8 m
  (`Npc3D.wall_spot`). It also stays 25 m from the shooter. The v6 map gets 13 crates,
  at least 36 m apart, with one guaranteed weapon. Found on the way: the navmesh has
  floor islands inside the hollow building shells (crates landed indoors until
  `outdoors()`), and `next_to_building` only looked along the X/Z axes (the streets
  aren't), so it now casts 8 rays. Tests: `test_loot_scatter.gd`, `test_npc_hiding.gd`.
- **3D loot crates and pickups (2026-11-17).** `scripts/3d/loot_crate.gd`: a solid wooden
  crate (wood impacts). E opens it into 1–3 items rolled by the 2D rules (`LootTable`,
  `Balance.LOOT` counts and weights; a `guarantee_weapon` crate always holds one). The
  rolls use the crate's own seeded rng, so every peer gets the same loot. Items land
  around it on walkable ground. `scripts/3d/pickup_3d.gd`: ammo mag (+1 pistol mag),
  bandage / medpack (`test_player.heal`), or a weapon via `viewmodel.give()`, with the
  weapon it replaces dropping in its place. Pickups sit on physics layer 7 (64), which
  only the interact ray sees. The crosshair prompt reads "E  open crate", "E  take Rifle",
  "E  give Rifle" or "E  take back Rifle". 3D kinds mirror the 2D `Pickup.Kind` order
  (the 2D script can't load headless). Test: `test/test_loot_3d.gd`.
- **Start with pistol + torch, carry limit, debug cheat (2026-11-17).** The shooter now
  spawns on `L.START` (pistol + torch) and can only select what they carry. The 2D slots
  are pure rules in `fp_loadout.gd` (`available` / `take` / `fallback`): pistol + torch
  always, one heavy (a second one swaps it out and drops the first), one bat. E is now a
  general "use" (`viewmodel._interact()`: crate, pickup or survivor). Hand-over moves the
  real heavy and its ammo, as in 2D, and taking it back restores them. **F9** toggles a
  cheat (`OS.is_debug_build()` only): every weapon, no carry limit, T refills; without
  it T does nothing. `test_player.heal()` added. Tests: `test_fp_loadout.gd`,
  `test_shooter_health.gd`.
- **Crosshair hitmarker (2026-11-17).** Four ticks around the crosshair flash when a shot
  or swing lands on a zombie. They're white on a hit, orange when a part comes off, and
  red and 1.5x on a kill, fading over 0.18 s (`Balance.FP.hitmarker`). A shotgun blast
  shows its strongest pellet. `viewmodel.marker_look()` is tested in `test_zombie_3d.gd`.
  No sound yet: there's no 3D audio.
- **Zombie hit feedback: blood, flinch, hit results (2026-11-17).** `Zombie3D.take_part_hit`
  (and `Hitbox.take_hit`) now return `Zombie3D.Hit` (`NONE` / `HIT` / `LIMB` / `KILL`, from
  the pure `hit_result()`). A shot into a zombie part or a survivor sprays blood
  (`Balance.IMPACT.flesh`), and a splat lands on whatever is up to 2.5 m behind along
  the shot. A part blown off bursts `gore` at its bone. A hit that takes nothing off
  jerks the zombie (`ZombieBody.flinch()`: start of `Hit_reaction`, `ZOMBIE_PARTS.flinch_s`
  0.25), with no stun. Tests: `test_zombie_3d.gd` (hit results), `test_impact_fx.gd`.
- **Shoot out street lamps (2026-11-17).** Any lamp with its lens glass still there
  (working, blinking, sparking, or a dead or fallen one whose roll kept the glass) carries a lens hitbox
  (`StreetLight.LensHitbox`, debris layer, meta `surface = "glass"`). A bullet calls
  `shatter()`: glass bursts, the light is freed, and the lamp goes `DEAD`, or `SPARKING`
  with `Balance.STREET_LIGHTS.shatter_spark_chance` (0.3, from the lamp's own seeded
  rng). A second shot does nothing. Local only until S10 replicates shattered lamps.
  Tests in `test/test_street_lights.gd` (lamps built after the first frame).
- **Surface-aware bullet impacts (2026-11-17).** `scripts/3d/impact_fx.gd` now owns hit
  effects for the shooter's guns and bat and for armed survivors (who left nothing
  before). Each surface gets its own burst from `Balance.IMPACT`: dust off ground and
  walls, sparks off metal (lamp poles carry meta `surface = "metal"`), shards off glass,
  chips off wood. Holes share one 60-decal budget. Found on the way: the impact sparks
  and muzzle smoke **never rendered**. A new `CPUParticles3D` already reports
  `emitting = true`, so the old "set emitting = true" did nothing. And without
  `billboard_keep_scale` each particle would have drawn 1 m wide. Both are fixed in
  `ImpactFx.particles()`; test: `test/test_impact_fx.gd`.
- **NPC survivors in 3D (2026-11-13).** `scripts/3d/npc_3d.gd`, ported from
  `scenes/npc/npc_human.gd` with the same states and `Balance.NPC` numbers (px -> m):
  hide 10-20 s beside a building, wander to a new spot via jittered waypoints; walk
  into one and it follows your breadcrumb trail (`test_player.trail`) single file,
  taking formation slots behind you when a zombie is near (`NpcFollow`, sticky threat
  with hysteresis), running at 90% of your sprint to catch up; a zombie's bite starts
  a 5 s "TURNING" conversion into a standard zombie handed to the commander; bullets
  kill them and never make a zombie. Interact (E) on a follower hands it the gun in
  your hand (or takes it back); armed followers fight once you fire (engagement
  latch), with 2D NPC aim (`NpcAim`) scaled for 3D (`NPC_3D.aim_scale`), hold fire
  when you're in the way, and their shots draw zombies. 10 survivors spawn at hiding
  spots >= 30 m from you and the horde, on the Quaternius Business Man / Hoodie / Man
  models (`character_anim.gd`, CC0); hidden from the commander unless a zombie sees
  them. Fixed on the way: agents' "reached" radius must exceed the navmesh's ~0.45 m
  float above the ground. `Balance.NPC_3D` holds the 3D-only numbers.
- **Zombie model + per-part damage (2026-11-13).** `assets/characters/zombie.glb`
  (bachosoftdesign, CC-BY 3.0 — credited in CREDITS.md) replaces the capsules via
  `scripts/3d/zombie_body.gd`: standard walks (Walk2), fast is the running crawler
  (Running_Crawl), fat (x1.3, green) and master (x1.2, purple) lumber (Walk); clips
  speed up to match the body's real speed, their root motion is stripped once, attacks
  squeeze Attack into 0.9 s, deaths play Die / Die2 and leave a corpse for 12 s.
  Spec §6 lands: six bone-attached hitboxes (head, body, arms, legs) on physics layer
  6, with `Balance.ZOMBIE_PARTS` pools; head or body at 0 kills, limbs never bleed;
  one leg hobbles (x0.5), two crawl (x0.2, Crawl clip, low capsule), one arm slows the
  attack (x1.6), two x2.4. A destroyed limb's bone is scaled to ~0 (spec §8.1 fallback).
  Weapon rays and the bat skip the zombies' movement capsules (layer 2) so every shot
  lands on a part; the bat hits one part per zombie per swing. Commander rim
  silhouettes now follow the model. NPC models (Quaternius Man / Business Man /
  Hoodie, CC0) added for the survivors.
- **Shooter health + first character model (2026-11-13).** `test_player.gd` gets the 2D
  shooter's health: `Balance.SHOOTER.max_hp` (100), whole-point damage with fractions
  carried, wounds widen the reticle (`debuff_injured` +20%, `debuff_hurt` +40% below
  half), death at 0 (`died`): the shooter freezes, the viewmodel shows a red death
  screen (ENTER restarts) and the commander "SHOOTER DOWN - the zombies win". HP
  readout bottom-centre, red flash per bite. Measured: three standard zombies kill in
  ~4.5 s. The shooter's commander-visible body is now Quaternius' Adventurer
  (`assets/characters/adventurer.glb`, CC0) with `scripts/3d/character_anim.gd`
  playing Idle / Walk / Run from measured speed and Death once. The zombie model
  (bachosoftdesign, CC-BY 3.0) is supporter-only on Poly Pizza, so it waits for a
  manual download. `test/test_shooter_health.gd`.
- **Zombie reactions, strict fog, free rotation (2026-11-13, second playtest).** Zombies
  no longer stay glued on: a 0.6 s beat to register a new target, then a fresh read of
  where it is every ~0.45 s (+-30%), momentum (`accel_mps2`, fast 8 m/s²) so a juke
  overshoots, and after losing sight round a corner they run to the last-seen spot for
  up to 5 s (`Balance.ZOMBIE_3D`). Measured: from contact a sprinting shooter opens 4 m
  in 0.5 s and ~7 m by 1.5 s (was creeping away at ~0.5 m/s). Fog: never-seen is now
  black for everything (no streets, buildings or window glow); building footprints are
  single outlines that only shadow from their far side, so a seen facade makes its
  building known and the shadow starts behind it; explored stays dim. Camera back to
  free rotation (Q/E hold, middle-drag), HOME = north, compass shows 8 directions.
  Street lights: lying / hanging debris moved to physics layer 5 (bullets hit it,
  bodies step over it; a snapped lamp across the pavement was trapping zombies), and
  standing poles are now baked into the navmesh.
- **Commander fog of war, camera, zombie speed / sight / hearing (2026-11-13, playtest).**
  Fog (`scripts/3d/commander_fog.gd` + `shader/commander_fog.gdshader`): the 2D
  ZombieLighting idea on the 3D city. A top-down SubViewport where each zombie is a
  shadow-casting PointLight2D (radius = its sight) and each roof triangle a
  LightOccluder2D gives "seen now"; a second, never-cleared SubViewport adds it up into
  "explored". A full-screen quad on the commander layer shades each pixel by its world
  XZ (from depth): unexplored near-black, explored dim, seen full; buildings never below
  dim; bright light (torches, lamps, windows) glows through like the 2D flashlight glow.
  Shooters / NPCs are drawn for the commander only while a zombie can see them (meshes
  swap to render layer 4 otherwise), and only seen enemies can be right-clicked.
  Camera: north-up and fixed-angle (classic RTS), Q/E turn 90° with a smooth snap
  (XCOM-style), HOME back to north, middle-drag pans, tilt goes 50° -> 72° as you zoom
  out; status line shows the facing. Zombies (`Balance.ZOMBIE_3D`): fast = the shooter's
  sprint +1% (6.06 m/s), standard 2.0, fat 1.6, master 1.3 m/s; sight 20 m (fat 16,
  master 30) with a line-of-sight check past buildings (`can_see`, also used to acquire
  targets); gunshots heard at 70 m (was 3.7 m sight / 17 m hearing, converted from 2D).
- **Zombie commander in 3D, first slice (2026-11-13).** `scripts/3d/commander.gd` on the v6
  scene: TAB swaps between the first-person shooter and a tilted, rotating RTS camera
  (WASD/edge pan, Q/E or MMB rotate, wheel zoom; never drops below the roof under it).
  The 2D commander's controls and stances are ported as they are: click / box / SHIFT
  select, CTRL+A, RMB move (sunflower spread so a group doesn't fight for one spot) or
  attack the enemy under the cursor, CTRL+1-9 / 1-9 groups, G + RMB rally, aggressive /
  hold, free / patrol / flee (sight, hit, idle), merge 2 -> fast and 3 -> fat (walk
  together, lock 2 s per zombie; several merges can run at once). Gunshots from the
  first-person weapons pull aggressive zombies within 17 m (`noise_listeners` group).
  Buildings between the camera and its focus or any zombie dither out to ~10%
  (`instance uniform fade` in `city_building.gdshader`); zombies also get a rim
  silhouette through walls. Commander-only markers (rings, stance dots, pings,
  silhouettes) sit on render layer 3, which the shooter's camera never draws; the
  commander's camera has its own fog-free, moonlit environment.
  `scripts/3d/zombie_3d.gd`: placeholder capsule per variant (standard / fast / fat /
  master) with the 2D stance machine ported in metres (Balance px / `FP.px_per_m`);
  first-person hits land in `take_hit` (one HP pool until per-part HP, S5).
  Navmesh baked at runtime from the city colliders (~0.4 s), horde of 15 + master
  spawned on the street ~45 m from the shooter. The tuning panel's hide key moved from
  Tab to H. Not yet: fog of war, minimap, HUD design, NPCs, networking.
  `test/test_zombie_3d.gd`.
- **Street lights (2026-11-12).** `scripts/3d/street_light.gd` (`StreetLight`, `@tool`):
  a 7 m cobra-head lamp built from primitives, with a sodium spot (shadowed, distance-faded)
  and collision. States: working, blinking (on, stutters out, dark, stutters back), dead
  (lens intact or smashed), sparking (bursts of bouncing sparks + blue-white arc flash), and
  four fallen builds: leaning, snapped (stump + top lying beside it), toppled (uprooted,
  footing and all) and folded (kinked, head hanging). Angles, break heights and fall
  direction (always roadward) are rolled per lamp; fallen lamps can keep live, sparking wires.
  State = deterministic roll from position + seed, odds blended from `calm` to `wrecked`
  by a ~110 m damage noise, so whole stretches are lit and others dark and smashed; every
  peer gets the same lamps with no syncing. `scripts/3d/street_lights.gd` lines both kerbs
  of the road mesh (kerbs read from the baked road UVs) every 28 m, staggered, dropping
  spots on junctions, under buildings/trees or too close to another lamp: 50 lamps on the
  v6 map. Odds and light numbers in `Balance.STREET_LIGHTS`. `test/test_street_lights.gd`.
- **Viewmodel arms + torch pass (2026-11-12, second playtest).** Arms are now skinned
  (`fp_arms.glb`: two armatures, fingers curled/relaxed baked in as rest) and posed every
  frame: hand exactly on the grip, forearm aimed at an elbow point, wrist + elbow bend to
  fit. This replaces the rigid arms that forced the forearm square to the grip (the
  horizontal "pipe" arm). Viewmodel drawn through its own FOV (62°, 50° aimed) via an X/Y
  stretch, so no edge stretching and the gun doesn't zoom with ADS. Pistol + torch: torch
  out on the left at the hip (side-by-side, as Amnesia: The Bunker does), Harries hold only
  when aiming. Torch lens glows while on. Arm/weapon materials de-metalled and matted (they
  imported 40% metallic, glossy skin). Aimed elbows drop/splay; long guns shoulder with the
  elbow out; pistol aims at arm's length (0.55 m), shotgun stock closer to the cheek.
- **Weapon feel pass (2026-11-12, after Mads' playtest).** Torch: the beam now starts
  where the torch *appears* (the viewmodel is drawn at 1/10 scale, so the light used
  to sit 4 cm from the eye and lit the torch's own handle + the fog in your face).
  Added a soft additive beam shaft from the lens (depth-faded, dithered), and the
  viewmodel moved to render layer 2, which the torch/halo skip. The viewmodel brings
  its own dim fill, torch spill and muzzle lights, with omni attenuation 0, since
  1/d falloff at 3 cm made them ~30x too bright. Pistol + torch is now the Harries hold:
  ice-pick grip at the tail cap, torch fist under the gun wrist, torch parallel to
  the barrel, moving with the pistol's recoil. Recoil is springs (fast kick, slower
  settle): gun spring = push into the shoulder + muzzle climb with random yaw/roll,
  view spring = punch that returns, plus a small kept climb (`Balance.FP.climb_deg`).
  Muzzle flash = camera-facing star + crossed flame planes (procedural textures,
  HDR additive, 2–4 frames, randomised), a short fast-fading light from the apparent
  muzzle, and a separate light on the hands. Lit smoke puffs; brass cases are
  little rigid bodies that bounce, and the shotgun drops two red shells when
  reloading. Bat: eased keys (short cocked wind-up, cubic ease-in into contact,
  follow-through, recovery), a swoosh ribbon, a 70 ms freeze on contact + shake +
  view jolt. The reticle ball hides when nothing in hand shoots.
- **First-person arms + weapons (2026-11-12).** `scripts/3d/viewmodel.gd` (child of
  the v6 camera) gives the test player 8 loadouts on keys 1–8 / mouse wheel:
  hands, torch, pistol, pistol + torch, shotgun, rifle, uzi, bat. Two-handed
  loadouts set `test_player.torch_in_hand = false`, so no torch, whatever F
  says; the torch beam now starts at the torch lens (`light_anchor`). Rules are
  the 2D ones via `scripts/3d/fp_loadout.gd`: Balance stats, auto-reload on an
  empty mag, switching cancels a reload, 2D falloff in metres (35 px/m), bat
  reach/fatigue from `Balance.MELEE`; uzi = the 2D machine gun (hold to fire).
  New 3D-only numbers in `Balance.FP` (camera kick per shot, rifle scope FOV,
  pistol reserve). Shots are hitscan from the eye through a random point in the
  reticle volume (`reticle_radius` x weapon `spread_mult`, from 2D aim_base);
  shotgun fires 5 pellets. Hits leave bullet-hole decals + sparks and call
  `take_hit(damage, point, dir)` on anything that has it (ready for zombies).
  Rifle aims through a scope overlay at 20° FOV. Weapons are CC0 (CreativeTrio
  pack, `assets/weapons/`); arms + torch are baked from `arms.blend` by
  `assets/blender/other/build_fp_arms.py` into rigid grip/open meshes. Each frame
  a hand sits on its weapon's grip point with the forearm aimed at a fixed elbow,
  so recoil/reload/swing motion carries the hands with it. The viewmodel is drawn at
  1/10 scale and 10x closer (camera near 0.01), so guns never clip walls.
  R reloads, T refills (test convenience). Check: `test/test_fp_loadout.gd`.
- **Small dressed city (2026-11-12).** `assets/city/westvillage_small.glb` is a
  250 x 170 m crop (~10% of the area, 107 buildings) of the West Village map, built
  headless by `assets/blender/maps/build_small_city.py`, and dressed at import by
  `scripts/3d/city_import.gd` with two procedural shaders (no textures):
  `shader/city_building.gdshader` and `shader/city_ground.gdshader`. OSM has no
  doors/windows/shops, so the Blender script works out what each wall faces by
  stepping out from it and looking down for road surfaces: **main** street
  (shopfronts, signs, shutters), **street** (front doors, ~35% shops), **alley**,
  **back** (small windows, service doors), **party** wall (blank, sometimes a
  ghost-sign landmark). Floors come from the real OSM height, bays from wall
  length; ~26% of windows are lit at night. Consecutive wall faces turning less than ~20°
  (~50° for short curve pieces) share one facade layout, so bow fronts get
  continuous window rows. Roads get asphalt, cracks, lane lines (double yellow
  on the secondary road), manholes; footways get concrete slabs + curbs;
  footway faces lying on a road become zebra crosswalks. The map has almost no
  OSM service roads, so the "alley" ground is the bare ground plane: a baked
  distance-to-street mask (`westvillage_small_mask.png`) paves it near streets
  and turns it into backlot (cracked concrete, weeds, puddles) inside blocks.
  Flat layers were dropped from blosm's 0.3 m float to 2–4 cm so feet meet
  the asphalt. Test scene: `scenes/test/camera_test_v6_small_city.tscn` (v5 copy).
  Check: `test/test_city_dressing.gd`.
- **Manhattan test scene + tuning HUD (2026-09-16).** `scenes/test/camera_test_v5_manhattan.tscn`
  runs the first-person rig on `assets/city/manhattan_westvillage.glb` (755
  buildings, 788 × 540 m). Spawn moved onto a street at (8, 1, 12) — the copied
  Copenhagen spawn was inside Building_356, and at night an unlit street reads
  as a sealed room. `scripts/test/test_hud.gd` (`TuningHUD` CanvasLayer): GTA-style
  heading-up minimap (SubViewport + orthographic camera, ~30 m radius, own
  flat environment) and live sliders for mist, haze, ambient, moon, flashlight
  cone/edge/energy/range/fog shaft, and eye adaptation. **F** toggles the torch,
  **ESC** frees the mouse for sliders, **Tab** hides the panel. Eye adaptation
  is a driven `exposure_multiplier` (1× → 2× over 60 s, back in 2 s); Godot's
  auto exposure was tried and rejected (blows the night out to daylight).
  Model written up in `docs/superpowers/specs/2026-09-16-visibility-and-eye-adaptation.md`.
- **3D camera test scene (Brief 11).** Standalone measuring instrument for the
  one open question behind the 2D→3D move: *what FOV/height makes a real
  Copenhagen street read as a canyon you are inside rather than a map you are
  looking at?* `scenes/test/camera_test_3d.tscn` (run with F6; nothing else in
  the project references it) drops a capsule onto the
  `assets/city/copenhagen_greybox.glb` greybox under a `Camera3D` pitched a
  fixed −90° — straight down, never tilted. The lean-in that fills the frame
  with facade comes from FOV alone, not pitch.
  `scripts/test/camera_rig.gd` exposes five `@export_range` knobs re-read every
  frame, so they retune live from the remote inspector without a restart:
  `fov`, `height`, `player_screen_offset`, `camera_yaw`, `follow_smoothing`.
  Keys **1/2/3** hard-cut between 70°/28.6 m (splay 3.34×), 60°/34.6 m (2.37×)
  and 50°/42.9 m (1.87×) — all three show identical ground coverage (40 m along
  the view axis), so only the splay changes and the A/B is legible. A debug HUD
  prints coverage, ahead/behind split, and the splay factor live, and warns
  instead of printing a number once `height` drops below the 20 m rooftops.
  `scripts/test/test_player.gd` is a locomotion stand-in only: 5 m/s, gravity,
  WASD rotated by `camera_yaw` so W is always up-screen, mouse-cursor facing via
  an analytic ray/ground-plane intersection. New input actions `move_forward`
  (W) / `move_back` (S); existing 2D actions untouched. Nothing in the existing
  2D game is touched by any of this.
  Measured on the greybox, not assumed: the player spawns at (−70, −30), inside
  an 86 m corridor 10.8 m facade-to-facade — Købmagergade proper. The street
  bearing there is **95° from −Z**, so the rig ships at `camera_yaw = -95`,
  which projects the street exactly vertically on screen (verified: 0.0 px of
  horizontal drift over a 24 m span). The brief's ~21° figure is pre-glTF-axis-
  conversion and does not apply directly. Yaw is per-street, not global.
- **Round 1: preset 1 + GTA5 aim mode.** Playtest loop is now one view angle at
  a time, each shipped *with* aiming, rather than one scene of sliders. Round 1
  is preset 1 (70° / 28.6 m, splay 3.34×). Holding **RMB** switches control
  schemes (Brief 8.1, third option): hip-fire keeps the absolute world-space
  cursor and screen-relative WASD; aim mode captures the mouse, locks the
  reticle to screen centre, drives yaw from relative mouse X and vertical aim
  from mouse Y, turns body and camera together, and slows movement — awareness
  vs commitment. The camera drops from 28.6 m straight-down to an
  over-the-shoulder rig (`aim_height`/`aim_distance`/`aim_shoulder`/`aim_pitch`),
  blended over `aim_transition`. The brief's entry-jump gotcha does not apply:
  `aim_yaw` already tracks the cursor every frame while hip-firing, so entering
  aim just switches the input source. *Leaving* is the side that jumps — the OS
  cursor reappears wherever it was parked — so the cursor is warped onto the
  current aim point on release.
  Reticle follows Brief 8.2's two-part model: the **sphere** is the reticle
  volume (0.95 m hip → 0.28 m aimed, later driven by weapon/skill/stats), the
  **cone** is the bullet path from muzzle through it. In aim mode the sphere
  sits where the camera's centre ray actually meets the world, not at a fixed
  distance along it — the latter buries it underground the moment the camera
  pitches down.
  Two things the brief defers had to be built anyway, because aim mode is
  untestable without them, both behind exports and inert during hip-fire:
  **camera collision** (a 4.5 m pullback inside a 10.8 m street puts the camera
  through a facade constantly — it now pulls in toward a shoulder pivot) and
  **vertical aim** (without mouse Y the centre ray is pinned at the rest pitch
  and you can only aim at the ground).
- **Four view models, four scenes, one script.** V1 was worth keeping, so
  rather than mutate it the rig grew a `view_mode` enum and the scene was
  duplicated three ways — switch version by opening a different scene, and a
  fix to the shared aim layer lands in all four:
  | Scene | Default view | Aiming |
  |---|---|---|
  | `camera_test_3d.tscn` | V1 top-down 70°/28.6 m, street-locked | absolute cursor; RMB → over-the-shoulder |
  | `camera_test_v2_over_shoulder.tscn` | V2 over-the-shoulder always | relative mouse always; RMB pulls to 2.6 m + 45° FOV |
  | `camera_test_v3_hostile_process.tscn` | V3 top-down, **rig yaw IS the mouse** | no cursor; character locked facing up-screen; RMB drops the camera 8 m rather than tilting |
  | `camera_test_v4_first_person.tscn` | V4 eye height 1.65 m, capsule hidden | relative mouse; RMB → 45° iron sights |
  V2/V3/V4 capture the mouse on load — **ESC** frees it, left-click grabs it
  back. The reticle picks its anchor from the camera's actual pitch rather than
  from the mode, so it sits ahead of the player under a straight-down camera
  (where the centre ray would just point at the player's own feet) and hands
  over to the true screen-centre ray as the camera pitches toward the horizon —
  correct in all four modes and throughout V1's transition, with no per-mode
  special cases.
- **Fix — the spawn faced a dead end.** Both the player and V1's `camera_yaw`
  were oriented down the 6.2 m stub of Købmagergade rather than its 95 m open
  run; yaw is now +85° in all four scenes (verified: 95 m clear up-screen, 6.2 m
  behind, and the street still projects perfectly vertically at 0.0 px drift).
- **Covered structures, to see what each camera does when the player goes under
  a roof.** New `scenes/test/test_structures.tscn` (CSG, one combiner with
  collision) instanced into all four scenes so the versions stay comparable:
  an **overhang** bridging the alley — 8 x 6 m slab with 3.0 m clearance, the
  Copenhagen *gennemgang* — and an enclosed **room**, 6 x 6 m with a 3.0 m
  ceiling and a 2.2 m doorway facing the street. Both walkable end to end
  (verified by capsule sweep).
  The HUD gained a diagnostic line naming whatever sits between camera and
  player, so the effect is objective rather than a judgement call. Result:
  the top-down modes (V1, V3) lose the player **completely** — HUD reads
  `PLAYER HIDDEN — camera blocked by TestStructures (3.5 m above you)` — while
  V2 keeps him visible without any new code, because the shoulder camera's
  collision pullback already tucks it under the ceiling (clearance 0.51 inside
  the room). V4 is unaffected by definition. Nothing acts on the occlusion yet;
  occlusion handling stays the open question it was.
- **Fix — the camera-collision guard let the top-down camera be dragged down a
  ceiling.** The guard skipped collision only when *both* pitch endpoints were
  straight down, but V1's aim endpoint is a shallow over-the-shoulder pitch, so
  its hip pose was never actually exempt: stepping under the 3 m overhang pulled
  the camera from 28.6 m to 2.7 m and silently destroyed the geometry being
  measured. It now tests the pitch the camera is actually at this frame.
- **Fix — the spawn was never in a canyon.** The old spawn sat at the mouth of a
  10 m stub that opens immediately into a 45-60 m plaza, so the street-to-height
  ratio the whole brief turns on was not being tested at all. (The original
  corridor search measured "length" through open ground and scored a false
  positive.) All four scenes now spawn at (-54, -14) facing +Z on Købmagergade
  proper: a straight 28 m run that goes 8 m wide, pinches to a 4.5 m alley
  (1:4.4 against 20 m facades), then opens to 13 m — with the overhang over the
  pinch and the room off the wide end.
- **Playtest round 2 — five tuning changes.**
  1. **Top-down cameras moved in**, 28.6 -> 25.0 m. Note the cost: splay against
     a 20 m facade goes 3.33x -> 5.00x, and clearance over the map's tallest
     building (23.0 m) is down to 2.0 m, where its splay is 12.5x. 25 m is close
     to the floor for this map.
  2. **Top-down modes now swoop to over-the-shoulder under cover.** A
     straight-down camera loses the player completely under any roof, so V1/V3
     drop to the shoulder pose on entering the tunnel or room and rise back on
     the way out (~0.6 s each way, `cover_transition`). Cover is detected by a
     ray straight UP from the player, deliberately *not* camera-to-player: once
     the camera is under the ceiling a camera-to-player ray reads clear, which
     would swoop it back up and oscillate forever.
  3. **The aim no longer lands on the far side of walls.** Two causes, both
     fixed: the hip reticle was placed at a fixed 12 m with no regard for
     geometry, so indoors it sat outside the room — it now stops at the first
     thing hit. And the absolute cursor is only meaningful under a straight-down
     camera; once swooped, its ray meets the ground plane at a grazing angle.
     The control scheme now follows the camera, handing over to relative mouse
     during the swoop and warping the cursor back to the aim point on the way
     out. ESC still frees the mouse; a click takes it back.
  4. **Aim narrows slowly** instead of snapping: FOV over `aim_transition`
     (1.2 s), reticle volume over `reticle_settle` (2.0 s), so the shot tightens
     gradually and committing costs real time.
  5. **Over-the-shoulder pose pulled in** — 4.5 -> 3.2 m back, 2.4 -> 2.1 m up,
     0.8 -> 0.7 m across; RMB now closes to 2.0 m. Used by V2's resting pose and
     by V1/V3's swoop, so they all agree.
- **Fix — the swoop teleported instead of swooping.** The instant the camera was
  allowed off straight-down, the collision ray hit the ceiling and clamped it to
  head height in one frame, so it snapped down and only the rotation animated.
  The camera's own position is now eased (`camera_move_smoothing`), which also
  takes the pop out of ordinary collision pull-ins.
- **Playtest round 3 — the top-down cameras drop below the roofline.** V1 25 ->
  15 m, V3 25 -> 9 m. Both are now *under* the 20 m facades, which changes the
  kind of shot rather than just its scale: with the camera below the roofs,
  buildings never project a roof edge outward, so there are no roofs in frame at
  all and you read wall faces instead. The brief's splay figure divides by
  `h - H` and is undefined here, so the HUD stops quoting it and reports how far
  below the roofline you are instead. This is the "canyon you are inside" the
  brief asks for, arrived at by dropping under the roofs rather than by widening
  the lens.
  V3 also pushes the player down-screen: `player_screen_offset = 0.6`, which
  solves `(1 + o) / 2 = 0.80` to put **80% of the visible ground ahead** of the
  player and 20% behind (10.1 m / 2.5 m of a 12.6 m view). Verified: the
  player's feet land at 80.0% down the frame. Their head sits at 87.5% — a 1.8 m
  capsule is a big fraction of a 9 m camera height, so the body itself has real
  parallax; at the 5 m first tried, the head reached 96.9% and was falling off
  the bottom of the screen. V3's `ads_drop` rescaled 6.0 -> 2.5 m to stay
  proportional (RMB now leans in to 6.5 m).
- **Playtest round 4 — V1's aim is a lean, not a transplant.** RMB used to send
  V1 all the way to the over-the-shoulder pose: a 15 m drop plus an 80 degree
  rotation, and for as long as you held the button V1 simply *became* V2, which
  defeats the point of running four versions side by side. V1 now leans instead
  — 15 -> 8 m, pitch -90 -> -50, FOV 70 -> 55, its own `lean_*` exports — so it
  commits while staying recognisably top-down. (If it should instead keep zero
  pitch and commit purely by tightening, the way V3 does, that is a one-line
  change to `_aim_local`/`_aim_pitch_now`.)
- **The cover swoop now starts 1 m before the threshold** (`cover_lookahead`),
  so it is already under way as you cross it rather than beginning on it. The
  probe only follows actual movement, so standing near a doorway cannot make it
  flicker, and it only ever ADDS cover — leaving is still judged on your real
  position, so the camera stays down until you are genuinely out. Verified: the
  swoop fires at z=-5.00 against an overhang edge at z=-4.00.
- **Fix — a top-down camera with a screen offset could be pushed through a
  facade.** Collision was skipped outright for any straight-down pose, which was
  safe while the camera sat directly above the player but not once V3 gained
  `player_screen_offset = 0.6` and started sitting 3.8 m *forward* of them. The
  pullback now picks its pivot by pose: a straight-down camera retreats toward
  the point directly OVERHEAD (trimming only the offset, never the height under
  test), everything else toward the shoulder. Measured V3 pulling in to a
  clearance of 0.05 where the street tightens — i.e. it would have clipped.
- **Camera-clip audit across all four versions.** Swept the player over the
  street, the alley pinch, the overhang and the room; every combination of four
  facings, hip and aim, with the cover swoop settled — 96 samples per version,
  384 total. **Zero clips.** V4 additionally checked for near-plane poke: the
  closest wall ever gets to the eye is 0.45 m against a 0.05 m near plane, since
  the 0.3 m capsule radius keeps it off the wall.
- HUD no longer quotes the hip pose while the camera is leaned or swooped —
  reporting "height 15.0 m" with the camera at 8 m was worse than reporting
  nothing. It now switches to live FOV / pitch / yaw / camera offsets.
- **Fix — the cover swoop's head start was too small to see.** The 1 m
  lookahead fired correctly but bought nothing: at 5 m/s the 0.6 s swoop needs
  3 m of travel, so 1 m covered a third of it and the camera was still at ~11.6
  of 15 m as you crossed the threshold — indistinguishable from no lookahead at
  all. The probe is now TIME-based, reaching `speed * cover_transition +
  cover_lookahead_margin` (0.75 m): literally where you will be standing when
  the swoop finishes, so it shrinks automatically while aiming. It also steps
  along the path rather than testing only the far end, so a shallow porch
  between here and there is not stepped over. Applies to the top-down modes
  only; V2/V4 keep a literal "are you under something" readout.
  Measured, walking in under real input: V1 tunnel fires 3.67 m out and is
  **100% swooped at the threshold** (camera 2.45 m, was 26% / 11.6 m); V1 room
  through the 1.2 m doorway fires 3.42 m out, 100% at the door; V3 tunnel fires
  3.67 m out, 100% at the edge, with zero lateral drift.
  HUD now distinguishes `COVER x.x m AHEAD — swooping n%` from `UNDER COVER`.
- **RMB in both top-down modes now goes to the same over-the-shoulder pose the
  cover swoop uses.** V3's aim previously just lowered a straight-down camera,
  which cannot aim at anything: however close it gets, there is no forward view
  to place a shot in. V1's partial lean had the same problem in milder form.
  Aiming and being under a roof turn out to want the identical thing from the
  camera — a view along the ground — so both now resolve to one pose
  (`aim_height`/`aim_distance`/`aim_shoulder`/`aim_pitch`), which also means one
  set of numbers to tune instead of three. Verified: V1 15.0 -> 2.10 m and V3
  9.0 -> 2.10 m, both pitching to -10, reticle locked dead centre (50%, 50%) and
  landing on world geometry 8.7 m ahead; mouse-Y sweeps it from 5.8 m of ground
  out to a wall at 2.77 m. Retired the now-dead `lean_*` and `ads_drop`
  exports, and V3's aim FOV moved 60 -> 55 to match V1 now that they share a
  pose.
- **Night variants of all four test scenes, and the renderer moved to
  Forward+.** `project.godot` was still on `gl_compatibility` despite Brief 2
  saying the renderer is Forward+ and web export was dropped for it; volumetric
  fog does not exist on GL Compat, and the beam biting into fog is the entire
  point of the night look. Switched, then booted the existing 2D game to
  confirm nothing broke — menu, fog of war, zombie vision lights and HUD all
  render correctly, so the 2D layer is unaffected.
  Four clones (`*_night.tscn`) share the same two scripts, so every camera
  behaviour carries over and future fixes land in all eight. Night is switched
  on by exports that default to off, and the four daylight scenes were verified
  unchanged (`flash=false cone=true fog=false amb=0.30`).
  Per night scene: near-black ambient (0.08), a faint cold moon at 0.05 instead
  of a sun, volumetric fog at 0.028, and one dim sodium lamp at the far end of
  the 28 m run so the canyon reads in silhouette and there is somewhere to walk
  toward.
- **Flashlight, aimed at the reticle.** A `SpotLight3D` on the player pointed at
  `reticle_point`, so the lit spot IS the aim — one thing to read instead of
  two. Angle and colour ported from the 2D game's already-tuned
  `Balance.FOG_SHOOTER` (22 deg half-angle, warm 1.0/0.97/0.85) rather than
  invented, plus its dim bluish personal halo as an omni.
  `light_volumetric_fog_energy` is what turns the beam into a visible shaft.
  Reticle faded to 0.45 opacity and the bullet-path cone switched off at night,
  where a bright ball of colour is the only thing competing with the beam.
- **Walk / sprint / crouch / jump**, with movement driving the aim volume so
  crouch is a stance rather than a slow walk. Measured: walk 3.00 m/s (r 0.95),
  sprint 5.64 m/s (r 2.09), crouch 1.40 m/s with the capsule shrunk 1.80 ->
  1.00 m (r 0.48), standing still (r 0.70), jump apex 1.07 m. Crouch refuses to
  stand back up with something directly overhead. New actions `sprint` (Shift),
  `crouch` (C — Ctrl is already `focus_aim` in the 2D map) and `jump` (Space);
  no existing action was touched.
- **Fix — the jump was floaty because gravity was real.** Project gravity is
  9.8 m/s2, which is correct physics and wrong for a game. Scaled it 2.4x and
  raised `jump_velocity` 4.5 -> 7.0 to compensate, plus a 1.35x multiplier on
  the way DOWN only (falling faster than you rose is what actually reads as
  weight). Apex is unchanged at ~1.1 m; hang time went **0.92 s -> 0.58 s**.
  Applies to all eight scenes.
- **Night dimmed, hazed and made to shimmer.** Ambient 0.08 -> 0.04, moon
  0.05 -> 0.028, flashlight 9.0 -> 5.0, halo 0.5 -> 0.3, street lamp 2.6 -> 1.5.
  Air now carries a general haze rather than only lighting up where the beam
  hits: volumetric fog density 0.028 -> 0.05 with forward anisotropy 0.3 and
  ambient inject, plus a separate depth fog for distance falloff. The beam edge
  is feathered (`spot_angle_attenuation` 0.55) instead of a hard cutout.
  Both lights are alive: the flashlight wavers +/-12% like a torch in a hand
  (two sines at incommensurate rates, so it never lands on an obvious beat), and
  the street lamp gets `scripts/test/flicker_light.gd` — the same drift plus a
  rare short dip, phase-offset per instance so several fixtures never breathe
  in lockstep. Measured: flashlight 4.75-5.60 around a base of 5.0, lamp
  1.47-1.70.
- **3D conversion design spec.**
  `docs/superpowers/specs/2026-09-09-3d-conversion-design.md` — the shooter goes
  **first person** (closing the four-version camera trial), the commander stays
  top-down over the 3D world with buildings going ~90% transparent when a zombie
  is underneath, and every mechanic ports except headshots. Zombies get
  **per-part HP** (Head/Body/Arm L-R/Leg L-R): head or body to zero kills,
  limbs never kill and never bleed into the body pool, one leg gone hobbles and
  two crawls, arms slow the attack without ever making a zombie harmless. Sized
  against the real weapon damage, so a pistol headshot drops a standard zombie
  but a rifle cannot drop a fat one. Measured on the way: the 2D balance
  converts to metres at **≈35 px/m** and every value lands on a physically
  sensible number, so `balance.gd` converts rather than gets re-invented.
- **Fix — the spawn, tunnel and room were all inside an enclosed inner
  courtyard.** The "28 m run" at (−54, −14) is closed at both ends (z −18 and
  z +11) — a *baggård*, not Købmagergade — and with the room 3 m in front of
  the spawn there was nowhere to walk. Rasterised the greybox footprint
  (`-col` meshes plus the visual-only Illum) and the only real two-sided street
  in the collision patch is Købmagergade itself, between the block's east face
  and Illum: 10.7 m wide, straight for ~65 m, bearing 20° off +Z. All eight
  scenes now spawn at (−11.4, 1, −30) facing down it; `test_structures.tscn`
  is rotated to the street (children placed as across / along metres): the
  overhang spans wall to wall 18 m ahead (12.5 x 6 m, 3.0 m clearance), the
  room sits against the west facade 40 m ahead with its doorway on the street
  and 4.6 m of pavement past it; the night lamp is 54 m down the run. Illum
  has no collision in the asset, so `test_player.gd` gives it a trimesh at
  `_ready` (`_collide_illum`) — rename the object `Illum-col` on the next
  Blender export to make that permanent. A 1 m visual-only icosphere sits at
  the world origin, in the street 8 m short of the room.
- **Fix — the test room sat in the courtyard, not the street.** Measured the
  greybox floor plan by raycast rather than by eye: the street runs z −16 → +2
  (4-13 m wide, pinching to 4 m at z −2..0) and then opens into a **13 m-wide
  courtyard at z +4..+8** — where the room was, dead centre. Swept every 6x6
  footprint in the street and found only three that sit fully on open ground;
  the room moved to the best of them, **(−53, −8)**, as a pure translation
  (dx −6, dz −14) so the west-facing door and all tested dimensions survive.
  Verified walkable after the move: interior floor 0.00 / ceiling 3.00 m,
  doorway 2.20 m, passages 3 m west and 2 m east, overhang and pinch untouched.
  The overhang did **not** move — it was already over the 4 m street pinch.
  Also measured: the greybox is 208 x 602 m of *visual* geometry but carries
  **collision only in a ~85 x 120 m patch** at its southern end; the rest would
  drop a player through the floor.
- **Docs caught up to the 3D work.** `PROJECT.md` gained a *3D conversion*
  section (the eight test scenes, what each version is, controls, what is
  settled vs. still open) and its status heading now separates the shipping 2D
  game from the in-progress conversion; `ARCHITECTURE.md` documents the new
  input actions and `scripts/test/`; `docs/BACKLOG.md` gained section **D2**
  (3D conversion + the 3D asset library) and its phase table now calls Phase 10
  the 3D conversion rather than "Art v2".
- Added `CREDITS.md` — the greybox is OpenStreetMap data under **ODbL 1.0**,
  which requires attribution on distribution (an itch.io page counts). The
  `asset_*` glTF extras carrying that credit are intact on every building; do
  not strip them.

## Phase 9 — Concurrent games (director + server pool)
- **Ambient lighting & life: lightposts, burning dumpster, critters, cross-role
  flashlight fog, grass.** Three lightposts + three dumpsters now scatter with
  real placement rules (dumpster: sidewalk against a building or on the
  street; lightpost: sidewalk bordering the street, lamp head facing the
  road) via new `StaticLightSource` (`scripts/props/static_light_source.gd`) —
  a steady or flickering `Light2D` that also feeds `FogZombieController` as a
  permanent full-visibility source, so both roles can see through the fog near
  one. The burning dumpster additionally dampens nearby gunshots (~20% shorter
  effective alert radius, `world.gd`'s `emit_noise`) without attracting
  zombies itself. New mechanic: the zombie-commander can now sense the
  shooter's flashlight through their own fog — a transient cone reveal
  (`FogZombieController._reveal_cone`, never written to persistent memory)
  gives a dim ambient glow at range, jumping to full brightness the instant a
  zombie is caught in the beam (`FlashlightGlow.zombie_caught` +
  `zombie_controller.gd`'s `_update_flashlight_glow`) — a real risk for the
  shooter in shining a light at a cluster of zombies. Three critter types
  (`scripts/critters/critter_base.gd`): rats and bugs wander and flee the
  flashlight/gunshots, lightning bugs drift over grass and never flee (just a
  slight nudge aside). Grass tiles get a sparse dappled light-occluder scatter
  on the shooter's flashlight (`ShooterLighting.collect_grass_dapple_positions`)
  and slightly dim any character standing on them
  (`world.gd`'s `_apply_grass_dimming`). Everything ships as placeholder
  shapes — no new art yet, mechanics-first per plan.
- **HUD reskinned to the "v2" distressed blood/rust design system.** Ported
  the latest Figma Make HUD mockup (new palette, Special Elite display font,
  cut-corner panels) into the live game. `UIStyle` (single source of truth
  for HUD colors/fonts) now carries the rust/blood palette in place of the
  old cyberpunk green/cyan one, plus `BLOOD`/`RUST` tokens and `FONT_DISPLAY`.
  Two new custom `StyleBox` classes replicate CSS effects Godot has no
  built-in for: `CutCornerStyleBox` (the mockup's octagonal clip-path panels,
  now used on mode/merge/rally buttons) and `RoughFillStyleBox` (jagged
  leading-edge progress fill, now the HP bar's fill style). A new `Grunge`
  helper (`scripts/ui/grunge.gd`) provides procedurally-drawn/generated
  distress decorations — tileable noise grain, blood splats/stains/drips,
  crack lines, torn edges, hazard tape — with no new image assets, wired
  into the shooter bottom bar, the zombie-commander bottom bar + portraits,
  the minimap frame, and the main-menu title. The HP bar now drips blood
  below 30% HP, matching the mockup's rule.
- **Fix — zombies spawned too far from the master zombie; zombie vision
  lights blew out to white when zombies clustered.** Standard-zombie spawn
  offset tightened from a ±6-tile scatter to ±4 around the master's tile
  (`scenes/world/world.gd`). Zombie Controller vision lights now use
  `Light2D.BLEND_MODE_MIX` instead of the default additive blend
  (`scripts/zombie_lighting.gd`), so overlapping lights no longer stack into
  a blinding white blob when several zombies stand close together.
- **Fix — NPC follower jiggle.** Three interacting oscillators: (1) the
  formation threat was re-picked (nearest zombie) and its direction re-read
  every frame, so slots teleported/swept; now the threat is sticky (enter
  384px / exit 500px hysteresis, ≥1s between switches) and the formation
  axis eases over `form_dir_tau`. (2) NPCs were hard-solid vs each other
  *and* RVO-avoiding each other inside 80px — push-correct oscillation; the
  NPC↔NPC collision mask bit is gone, RVO owns spacing. (3) Full-speed
  approach into a 12px deadzone with per-frame re-pathing; now an arrive
  slowdown (`arrive_slow_px`), a 20px deadzone, and re-path only when the
  goal moves >`retarget_px`. Tunables in `Balance.NPC`.
- **Commander view no longer hides under the HUD.** The bottom command bar
  is fully opaque, the camera centers on the band *above* the bar
  (zoom-corrected `camera.offset`), edge-pan treats the bar's top edge as
  the screen bottom and ignores the mouse over UI, and full pan-down brings
  the map's last rows clear of the bar.
- **Rally + minimap orders moved to right-click.** After RALLY ALL \[G], the
  rally point is placed with *right* click (left cancels), matching move/
  attack orders. Right-clicking the minimap sends the current selection to
  the corresponding world position (armed rally: places the rally there);
  left click/drag still jumps the camera.
- **Fix — props never cast fog shadows (both fogs).** Only `prop_statue.tscn`
  was in the `occluders` group, so trees/cars/dumpsters/fences blocked neither
  the shooter flashlight nor the new zombie vision lights. All five prop
  scenes now share `scenes/props/prop_occluder.gd`, which builds a
  correctly-sized `LightOccluder2D` from the prop's visual footprint at
  runtime (inset 25% so the prop stays lit, `occluder_light_mask = 3` → casts
  for both fogs; rotates with cars). **Fences are special:** striped occluder
  segments with gaps, so light shines through in a picket/chain-link shadow
  pattern instead of blocking. The statue's stale `occluders` group tag was
  removed (the old 64px-square path is superseded). Tunables in
  `Balance.PROP_OCCLUDER`. Note: this hides a shooter behind a tree/car from
  the *commander's view*; AI zombie auto-detection is still distance-based
  (LOS-aware aggro would be a separate change).
- **Fix — fast zombies and NPCs were speed-capped at 100 px/s.** Nobody set
  `NavigationAgent2D.max_speed` (default 100), and the RVO avoidance solver
  clamps requested velocity to it: FAST's 220 and the NPC's 160 were silently
  squashed to ~100 while standard (85), fat (76.5) and master (60) fit under
  the cap — so fast zombies barely outpaced standards and follower NPCs lagged
  the shooter. All three agents now set `nav_agent.max_speed = speed` from
  their Balance stats. Balance values were always correct.
- **Fullscreen toggle.** F11 toggles fullscreen anywhere (handled by the
  `Settings` autoload), plus a "Fullscreen (F11)" row in the settings screen's
  toggle list. Persisted to `settings.cfg`; restored at boot on desktop only —
  browsers require a user gesture to enter fullscreen, so on the web build it
  applies when you press F11 or click the toggle. Pairs with itch's
  "click to launch in fullscreen" embed option.
- **NPC followers retrace your path and form up in combat.** The shooter
  records a server-side breadcrumb trail (`shooter.trail`, every 24 px, capped
  at 64 points); following NPCs walk the trail single-file at 1-tile spacing
  (`NpcFollow.trail_point`) instead of beelining to a point behind you — no
  more corner-cutting into your lap. When a zombie comes within
  `Balance.NPC.threat_radius_px` of the shooter, they switch to formation
  (`NpcFollow.formation_slot`): 1 armed NPC behind-and-to-a-side, 2 armed one
  per flank, unarmed in a column straight behind — never between you and the
  threat. Slot order is stable (armed first, then name). Pure math in
  `scripts/npc_follow.gd` + `test/test_npc_follow.gd`; knobs in `Balance.NPC`.
- **Zombie fog reworked to shooter-style lighting.** The ZC view now gets the
  same treatment as the shooter: `CanvasModulate` ambient darkness + a soft
  radial `PointLight2D` per zombie (radius = vision × 64 px) with real
  building/prop shadows (`ZombieLighting`, reusing `ShooterLighting` helpers).
  The 47×47 tile grid stays as the *explored memory*, now painting only
  unexplored tiles opaque black (`FOG_ZC.vis_explored/visible = 1.0`); tile
  reveal is LOS-honest via `FogZombieController.tile_line_clear` (Bresenham
  through building tiles), so rooms behind walls stay black until a zombie
  actually rounds the corner. Occluder masks: statics cast for both fogs
  (`occluder_light_mask = 3`), entities only for the shooter's flashlight —
  zombies never blot out vision (`shadow_item_cull_mask = 2`). Tunables in
  `Balance.FOG_ZC`; minimap tile states untouched.
- **Right-click attack targeting (zombie commander).** Right-clicking an NPC or
  shooter now snaps the selected zombies onto that target: a new
  `attack_target` state on `zombie.gd`/`master_zombie.gd` (set via
  `world.rpc_command_attack`) chases the target's live position and outranks
  stance/move orders. The lock holds only while *any* zombie still sees the
  target (`Targeting.visible_to_any`/`watchers_from`, vision × 64 px); on
  escape it degrades to a move order to the last-seen spot. Cleared by target
  death/conversion or any newer order. Attack orders ping **red** (move stays
  green), with a red minimap marker.
- Cleared the two editor warnings: hoisted the duplicate `var w` declaration in
  `bullet.gd _on_body_entered` (confusable-declaration), and annotated the
  intended integer division in `blood_canvas.gd setup` with `@warning_ignore`.
  No behavior change.
- **Client-authoritative shooter movement (Among Us model).** Your own shooter
  now integrates movement locally in `_physics_process` — zero perceived input
  lag — and reports its position in `_send_input` (now `pos, dir, aim, shoot,
  focus`). The server adopts the reported position speed-clamped (×1.5 headroom,
  ≤0.3s window) so a tampered client can't teleport, keeps `velocity`
  informational for NPC follow logic, and stays authoritative for ALL combat
  (shooting, damage, hp, ammo, pickups, merges). If the server's adopted
  position diverges past `Balance.NET.reclaim_dist_px` (240), the client snaps
  back — the hook that later tightens into full server prediction/reconciliation
  when rankings arrive. Replaces the own_smooth_rate elastic-band approach for
  the local player; remote entities keep NetSmooth interpolation.
- **Fix — single player showed the zombie view after any online session.**
  `GameState.shooter_peers` (set by `_assign_role_and_start` for online
  matches) was never cleared by `Net.leave()`, so a later single-player game
  spawned `Shooter_<old online id>` instead of `Shooter_1`; the local player
  (id 1 offline) never matched it, `_apply_role()` bailed, and the default
  ZCCamera showed the zombie view regardless of the chosen role. Fixed both
  layers: `leave()` clears `shooter_peers`, and `world._spawn_shooters` ignores
  `shooter_peers` entirely when `multiplayer_active` is false.
- **Tuning: split smoothing rate for own shooter vs watched entities.** Stops
  felt lingering (~0.2s coast) because one smooth_rate served everything. New
  `Balance.NET.own_smooth_rate` (28/s, ~0.1s settle) applies to the player's
  own shooter — responsiveness matters most there — while zombies/NPCs/remote
  shooters keep the softer 14/s look. NetSmooth helpers take an optional rate.
- **Online smoothness: client-side pose interpolation + local aim.** Entities
  jittered ("jumping all over") because synchronizers wrote raw
  `position`/`rotation` at whatever cadence packets arrived (bursty over
  TCP/TLS); merging zombies visibly bounced between converging positions, and
  the flashlight cone trailed the crosshair by a full round trip (rotation was
  server-computed and synced back). Replication configs now carry
  `sync_pos`/`sync_rot` vars (zombie/fast/fat/master, NPC, bullet, shooter);
  the server publishes them each frame and clients ease toward the pose
  (`NetSmooth` helper, tunables in `Balance.NET`: smooth_rate, snap_dist_px)
  with spawn-pose adoption in `_ready` so nothing flashes at (0,0). The owning
  shooter client now aims locally from the live mouse, so the light cone tracks
  the crosshair instantly; the server stays authoritative for shots and spread.
- **Fix — both players saw the zombie view in online matches.** Shooter
  multiplayer authority is set on the server (`world.gd`) but authority is NOT
  replicated by `MultiplayerSpawner`, so on clients every shooter arrived with
  authority 1: the human client never matched its own shooter, `_apply_role()`
  never ran, and the default-enabled ZCCamera showed the zombie commander view
  on both windows. `shooter.gd` now re-derives root authority from its
  `Shooter_<peer>` name in `_enter_tree()` on every peer, pins the
  `MultiplayerSynchronizer` back to server authority (simulation and state
  broadcast stay server-side), and `_muzzle_fx`/`_swing_fx` switched from
  `@rpc("authority")` to `any_peer` + explicit server-sender check (the server
  calls them, but the node's authority is now the owning player). Verified
  end-to-end through the director: both clients ready with correct roles,
  root auth = owning peer, sync auth = 1, zero script errors.
- **Fix — pool slot leak that broke online host ("server unreachable").** A host
  whose connection ended without cleanly emptying its room (abandoned in the
  lobby, a web client that just drops the socket) pinned its pool slot forever,
  because a hosted child was only released when the child process exited. After
  `MAX_GAMES` (5) such attempts the pool was permanently exhausted and every host
  was refused with a fast 502 — reproduced end-to-end in the Railway image.
  The director now `Kill`s a host's child when that host connection ends, so the
  pool reaps the slot and refills the warm buffer (joiner disconnects don't kill;
  this mirrors "host leaving closes the room"). See `proxy.go` + regression tests
  `TestProxy_HostChildKilledWhenConnectionEnds` / `...JoinerLeavingDoesNotKillChild`.
- The Railway container now runs **multiple matches at once** instead of one.
  Entry point is a new Go **director** (`server/director/`) that listens on
  `$PORT` and manages a pool of single-match headless Godot children
  (`--server --port=<n> --room=<CODE>`) on internal ports — one child per match,
  so no server-authoritative game code changed.
- Routing: each client's WebSocket connect URL carries `?host=1` (allocate a
  fresh child + room code) or `?join=CODE` (route to that child). The director is
  a raw TCP proxy — it reads the upgrade line, rewrites the request target to `/`
  so children see a byte-identical handshake (web/itch.io and native unaffected),
  and splices bytes. A **warm buffer** (`WARM_CHILDREN`, default 1) keeps a
  pre-booted child ready so hosting is instant; **dial-retry** covers a
  still-booting child (fixes the cold-start "server unreachable" on first host).
  Pool cap `MAX_GAMES` (default 5); a child exits when its room empties and the
  director reaps + refills.
- Godot child (`scripts/network.gd`): `start_dedicated_server` reads `--port=`/
  `--room=` (director-injected), `create_room` uses the injected code and no
  longer refuses a "second" game, and the process exits on room close
  (`_quit_child_if_dedicated`). Director-less local `--server`/`--host`/`--join`
  dev flow still works.
- Client + menu: `Host`/`Join` now open the intent-carrying connection themselves
  (`_connect_with_intent`) and fire the RPC on connect; the old separate "connect"
  step is gone. Connection-failure copy is intent-aware (bad code / busy server).
- Deploy: multi-stage `Dockerfile` (Go build stage → Debian+Godot+director);
  `CMD` runs the director. Design + tests in `server/director/`; spec in
  `docs/superpowers/specs/2026-07-09-concurrent-games-director-design.md`.

## Phase 8 — "ZOMBIE COMMAND" visual identity (in progress)
- Playtest corrections (July 8):
  - Menu back navigation: "‹ BACK" button on role select / multiplayer / lobby /
    join panels + ESC steps back one screen. Backing out of multiplayer or the
    lobby calls `Net.leave()` (lobby also RPCs `leave_room` first, like
    `leave_to_menu`), so the connection resets cleanly.
  - Giant bandage on the floor: pickup sprites are now normalized to ≤18 world
    px wide (`pickup.gd MAX_SPRITE_PX`) — bandage.png is 1600px wide vs
    Medipack.png's 16.
  - Give-weapon-to-NPC was unreachable: `interact_give_px` was 22px ("stand on
    top of the NPC") but followers hover 64±12px away and Phase 7's solid
    bodies stop you overlapping them — raised to 90px. Prompt reworded to
    "Press E to give {weapon} to NPC" and the offer now requires the special
    to actually be in hand (`equipped == held_special`).
  - Zombie command feedback: move/rally pings now render above the fog
    (z_index 150 vs the fog rect's 100) — clicking into unexplored fog shows
    the green ring. (Diagnosed via a synthetic in-game selfcheck: selection and
    move commands themselves work in solo; a single zombie commanded out of the
    middle of the packed spawn cluster can still RVO-gridlock — known quirk.)
  - Zombie commander bottom command bar (mockup screen 10): SELECTED [n]
    header, live type-colored unit portraits with HP micro-bars, group stats
    (count · avg HP), the stance toolbar (movement buttons now a 2-column
    grid) and MERGE OPS reparented in as sections. Clicks on the bar no longer
    leak into map selection (`_pointer_on_ui`).
Design source: Figma Make export (`~/Downloads/Game HUD for Zombie Strategy 2`),
condensed into `docs/design_system.md`. Brutalist military-horror: acid green
`#39ff14` on near-black, Share Tech Mono + Rajdhani, 0px corners, hairline
borders. In-game HUDs (shooter + zombie commander) are the remaining phases.
- Foundation: `scripts/ui_style.gd` (palette/border/font tokens + `hp_color`,
  `box()` stylebox builder — the UI counterpart of `balance.gd`); `UITheme`
  autoload (`scripts/ui_theme.gd`) builds the whole Theme in code and applies it
  to the root window (Button/LineEdit/ProgressBar/Panel styles + type
  variations `TitleLabel`/`HeadingLabel`/`MonoLabel`/`MicroLabel`/`BodyLabel`/
  `MenuItemButton`/`DangerButton`/`CardPanel`/`ModalPanel`); OFL fonts in
  `resources/fonts/`; reusable `GameBg` (grid + vignette) and `LogoLockup`
  (code-drawn biohazard trefoil — the ☣ glyph falls back to an untintable color
  emoji on macOS) in `scenes/ui/`.
- Main menu flow restyled in place (`main_menu.gd::_apply_zc_style` +
  `scenes/ui/menu_widgets.gd` builders) — logic and signal wiring untouched.
  Main menu = logo + SINGLE PLAYER / MULTIPLAYER / SETTINGS rows (the old
  PLAY → mode-select hop is gone; ModePanel is now unused); solo role select is
  cyan/green role cards; MP hub/lobby/join get breadcrumbs, mono status lines,
  styled code entry, and a primary START; lobby role buttons tint by
  claimed/taken state instead of `modulate` hacks.
- New loading screen (`scenes/ui/loading_screen.tscn` — now the **main scene**):
  logo, progress bar, init checklist, then hands off to the menu. Time-driven
  (a threaded world.tscn preload stalled mid-load — don't re-add without
  verifying); `--server`/`--host`/`--join`/`--role`/`--autojoin` launches skip
  it, so `run_local_mp.command` and the dedicated server are unaffected.
- New settings screen (`scenes/ui/settings_menu.gd`, code-built, no .tscn):
  CONTROLS (live from InputMap + static mouse bindings) / UI-HUD toggles /
  PROFILE placeholder. Opens full-screen from the menu's SETTINGS row and as an
  ESC-able overlay from the pause menu. Toggles persist via the new `Settings`
  autoload (`scripts/settings.gd`, `user://settings.cfg`); `hud.gd` already
  honors `show_debug_coords` + `show_pickup_toasts` (minimap/interact-prompt
  toggles wire up with the HUD phases).
- Pause menu restyled into the mockup's modal (PAUSED header, primary RESUME,
  SETTINGS, red EXIT TO MENU) — same wiring, plus the settings overlay hook.
- Shooter HUD (mockup screen 11): the scattered top-left labels are now a
  bottom bar (`hud.gd::_apply_zc_style`, nodes reparented in place) —
  HEALTH (bar + number recolored by the >60/30–60/<30% HP rule) | WEAPON
  (icon, mono readout, per-round ammo-block grid driven by `mag_size`) |
  THREAT (master-zombie compass). Toast is mono; debug coords stay top-right.
- Zombie commander HUD (mockup screen 10): stance toolbar buttons restyled
  with per-stance accent colors (aggressive red / hold blue / flee yellow /
  patrol purple) + PRIMARY STANCE / MOVEMENT BEHAVIOR headers; merge panel is
  now MERGE OPS (cyan "MERGE → FAST (2)", amber "MERGE → FAT (3)", red cancel);
  rally button gold-framed; minimap gets a hairline frame + MINIMAP header,
  zombie blips are uniform acid green (was dark red) and player shooters cyan
  (NPCs stay yellow). Game-over screen restyled into the shared modal
  (green message, primary PLAY AGAIN, red MAIN MENU).

## Phase 7 — RTS zombie experience (in progress)
- Interact prompts — a small "Press E to …" label now floats over the nearest
  interactable when a shooter is in reach (`shooter.gd`), so players know what E
  will do: *equip/pick up* a floor item, *open crate*, *arm NPC with {weapon}*,
  or *equip {weapon}* from an armed NPC. Client-side and controlling-player-only
  (built lazily, world-space `top_level` anchor so it ignores the shooter's
  rotation). Candidate resolution is now shared between the server-side action
  and the client-side hint (`_gather_interactables`), so the label always names
  exactly what pressing E would do.
- Online co-op — up to 5 players per match: **1 zombie commander (required) +
  1–4 shooters**. Generalizes the old 2-player (1 human + 1 zombie) stack:
  - Lobby now tracks one zombie slot + a list of shooter peers (`network.gd`,
    capacity 5). The **host** presses Start (valid once a zombie and ≥1 shooter
    are present); matches no longer auto-start. New role logic is a pure,
    unit-tested helper (`scripts/lobby_model.gd`); a refused role-claim keeps the
    player's current slot. Lobby UI shows a shooter roster and a host-only Start
    button.
  - `world.gd` spawns one shooter per peer, each with its own
    `set_multiplayer_authority(peer)`; `shooter.gd` gates input on
    `is_multiplayer_authority()` and the server validates the RPC sender so a
    client can only drive its own shooter. Shooters spawn on random walkable
    tiles kept clear of the zombie spawn (`Balance.SHOOTER.min_dist_from_zombie_px`)
    and spaced from each other. Zombies/NPCs target the nearest living shooter
    (`nearest_shooter()` + pure `scripts/shooter_select.gd`, unit-tested).
  - Death & win/lose: a dead shooter becomes a **spectator** (server hands its
    camera to a living ally via RPC; a non-pausing "YOU DIED — spectating"
    banner). The **zombie wins** when all shooters are dead; the **shooters win**
    when the master zombie dies. Mid-match disconnects are handled server-side.
  - **Friendly fire is on**: a player's bullet damages other shooters (never the
    firer); NPC bullets still never hit shooters.
  - Population scales with shooter count (`world.gd::_apply_population_scaling`,
    tuned in `Balance.WORLD`): normal zombies = `base_zombie_count +
    zombies_per_extra_shooter * (shooters - 1)` (15 / 20 / 25 / 30 for 1–4
    shooters, plus the master); NPCs = `npc_per_player * (shooters + 1)` — 5 per
    player counting the zombie commander (e.g. 3 shooters + zombie = 20 NPCs).
- Combat juice / effects (cosmetic, server-authored, replicated via `call_local`
  RPCs like `rpc_noise_event`; all tuning in `Balance.FX`):
  - Green blood bursts when the shooter hits a zombie (bullet or melee); red
    blood when a zombie bites the player/an NPC or when an NPC is shot; sparks
    when a bullet hits a wall or prop. One reusable `scenes/fx/hit_burst.tscn`
    (`CPUParticles2D`) covers all three via `FxPresets` presets; the world's
    `spawn_hit_fx()` spawns them under a non-replicated `Effects` node.
  - Permanent player bleed trail: once wounded, the player drips blood while
    moving (server emits a drop every `bleed_drip_px` of travel during a
    `bleed_seconds` window that refreshes on each hit). Drops bake into one
    world-sized `BloodCanvas` image (`scripts/blood_canvas.gd`, same technique
    as the fog texture) — never fades, one draw call. `DecalMath` maps world→
    pixel (unit-tested).
  - Per-shot muzzle flash + brief light pulse at the gun tip for the player and
    armed NPCs (`scenes/fx/muzzle_flash.tscn`; radial texture generated at
    runtime via `ShooterLighting`, no new asset).
- Spawn/camera fixes: the zombie-controller camera now starts centered on the
  master zombie (was pinned to map center). Standard zombies spawn on distinct,
  in-bounds, walkable tiles (`_find_clear_walkable_tile_near`, tracks used tiles)
  so they no longer stack on one tile and wedge inside each other's new solid
  bodies (the "stuck zombie" bug).
- Config + bodies: starting zombie count now lives in `Balance.WORLD.zombie_count`
  (NPC count was already `Balance.WORLD.npc_count`); `world.gd` spawns that many.
  Zombies, master, and NPCs now have solid collision bodies vs each other and vs
  the other type (`collision_mask` layers 2/4), so nothing passes through —
  zombie-vs-zombie is toggled off during a merge so units can still overlap to
  combine. (Zombie→NPC conversion still fires first: the convert zone (r20) is
  bigger than the bodies.)
- Fog fix: the zombie-view `ZCFogRect` had a shader material but no texture, so a
  TextureRect with nothing to draw never ran the shader — the fog was invisible in
  the world view (only the minimap, which reads the raw data, showed it). Gave the
  rect the fog texture + `z_index=100` so unexplored areas darken over the map.
- Minimap detail: now a discovered-world map. Cached terrain base (roads/sidewalks/
  grass/parking + buildings) dimmed by fog; discovered static features drawn where
  explored — trees (green) + other props (grey, new `props` group on the 5 prop
  scenes) and loot boxes (gold). Moved to bottom-left; stance toolbar shifted right
  of it. Added a Rally All button + `G` hotkey (arm → click map → whole horde moves
  there, selection untouched). New `MinimapMath.terrain_color` (unit-tested).
- Fix: merging broke after the RTS layer landed — RVO avoidance held zombies
  ~32px apart (> `touch_distance` 30px) and the default Aggressive stance pulled
  them off the merge midpoint. Added a dedicated `Zombie.set_merging()` mode that
  bypasses both the stance machine and avoidance so merging zombies overlap and
  lock in; `MergeManager` now drives merges through it.
- Toolbar gating: stance commands are turned on one at a time for testing via
  `ZombieController.ENABLED_STANCES` (currently Aggressive + Hold); other stance
  buttons are hidden.
- Phase H: docs (ARCHITECTURE/PROJECT) updated for the RTS layer; the existing
  two-layer zombie fog is reused unchanged (the minimap reads its `tile_states`).
  In-engine fog/feature verification pending an owner playtest.
- Phase G: world-view feedback + sound aggro. A subtle world-space ripple
  (`scripts/noise_ripple.gd`) spawns near a gunshot only when the zombie camera is
  close; Aggressive zombies within `AGGRO.alert_radius_px` get pulled toward the
  shot for `AGGRO.alert_seconds` (Hold/flee/patrol stances ignore it). Tunables in
  `Balance.AGGRO`.
- Phase F: minimap (`scripts/minimap.gd`, runtime child of `ZCOverlay`) — explored
  terrain from the existing fog `tile_states`, own-zombie blips always, enemy blips
  only on currently-visible tiles, fading last-known ghost blips, AoE-style red
  under-attack pulse (driven by `took_damage`), subtle gunshot ripple at a fuzzed
  position, and click/drag-to-jump camera. Shared "noise event" infra: the shooter
  calls `World.emit_noise` on each shot → `rpc_noise_event` → `noise_event` signal.
  Helpers `MinimapMath` (mapping + fuzz) unit-tested. Tunables in `Balance.MINIMAP`.
- Phase E: per-zombie health bars (`scripts/health_bar.gd`) above zombies and the
  master, shown only when damaged or selected, kept upright as units rotate, and
  driven by the already-replicated `hp` so they render on every peer.
- Phase D: stance toolbar (`StancePanel` in `ZCOverlay`) with click-to-place
  patrol (2 points) / flee (1 point) targets; patrol-line & flee-marker preview
  in the selection drawer; per-zombie stance glyph under selected units; RTS
  control groups (Ctrl+1-9 save, 1-9 recall). Note: stance/patrol/flee state is
  server-side, so the preview/glyph render correctly for a host zombie player or
  in single-player; client-side preview would need stance replication (follow-up).
- Phase C: per-zombie stance state machine (`Stance` enum: aggressive / hold /
  patrol-attack / patrol-flee / skittish / flee-point) with nearest-visible-enemy
  targeting (`Targeting` + `StanceLogic` helpers, `_acquire_enemy` scanning the
  `shooter` + `npcs` groups). Right-click move still overrides a stance until it
  arrives. Tunables in `Balance.STANCE`.
- Phase B: unit separation via `NavigationAgent2D` RVO avoidance — zombies, the
  master zombie, and NPCs now flow around each other instead of stacking or
  passing through. Movement routed through `set_velocity` →
  `_on_velocity_computed`. Tunables in `Balance.SEPARATION`.
- Phase A: zombies and the master zombie now hit on a cooldown for discrete
  damage (`Balance.<variant>.damage_per_hit` / `attack_interval`) instead of
  draining the shooter continuously. New `CombatMath.can_attack` helper; zombies
  emit a `took_damage(zombie, amount)` signal and do a brief lunge on each hit.

## Phase 6 — Loot boxes
- `scenes/loot_box/loot_box.gd` + `loot_box.tscn`: closed crate scene replicated
  via `MultiplayerSynchronizer`; server rolls 1–3 items on `open()` and bursts
  them as `Pickup` nodes within `burst_radius_px` of the box on validated walkable
  ground, keeping items `burst_min_sep_px` apart and clear of props/bodies.
- `world.gd`: replaced `_spawn_items()` with `_spawn_loot_boxes()` (8 crates on
  walkable tiles, ≥96 px apart); added `loot_landing_spot(center, placed)` and
  `_is_loot_tile(world_pos)` helpers; `_find_item_spawn` kept for internal reuse.
- `world.tscn`: `loot_box.tscn` registered in `MultiplayerSpawner._spawnable_scenes`.
- All tuning (box count, item counts, weights, burst dimensions) in `Balance.LOOT`.

## Phase 5 — Weapon visuals + flashlight fog
- Gun sprite on armed NPCs, synced across the network.
- Weapon icon in the HUD.
- Weapon PNGs shown on floor pickups.
- Equipped gun sprite on the player.
- `WeaponVisuals` texture map (id → PNG) + imported weapon PNGs.
- In progress: sprite fixes (`8877b33`).
- Shooter fog-of-war rebuilt on Godot 2D lighting: dark `CanvasModulate` fog,
  hard-edged flashlight cone + personal halo (each a `PointLight2D` parented to
  the shooter), real straight-line shadows from buildings, props, zombies, and
  NPCs (`LightOccluder2D` on all moving entities). New file:
  `scripts/shooter_lighting.gd` (`ShooterLighting`), assembled from
  `world.gd::_setup_fog()` for the HUMAN role only. Tunables in
  `Balance.FOG_SHOOTER` (ambient darkness, beam range/angle/energy/color, halo
  radius/energy/color, shadow toggles). Removed: `FogShooter`
  (`scripts/fog_shooter.gd`), `shader/fog_of_war.gdshader`, the `ShooterFogRect`
  overlay node, and the per-frame fog-texture update in `world.gd`. The
  zombie-controller fog (`FogZombieController` / `fog_zc.gdshader`) is unchanged.

## Phase 4 — Inventory, machine gun & melee
**4a — inventory + machine gun**
- 3-slot inventory selection: `1` pistol / `2` heavy / `3` melee.
- Full-auto machine gun (heavy slot) with pickup + world spawn.

**4b — melee**
- `MELEE` weapon data + `Balance.MELEE` tuning.
- `Melee.forward_strike` cone + recent-hit/fatigue math (unit-tested).
- Swing + fatigue + drop + HUD readout; aim ring hidden for melee (dot only).
- Melee pickup + world spawn.
- Bullet tweaks: 2× faster, ~2px tiny bullets. Fixes to bullets, NPC shooting,
  melee and gun slots.

## Phase 3 — Armed NPC shooting
- `Balance.NPC` accuracy + engagement knobs.
- `NpcAim` debuff + recoil math (unit-tested).
- Engagement latch + spread + recoil + 1.5 shots/sec cap.

## Phase 2 — Headshots
- `AimModel.is_headshot` ray-distance + unit test.
- Center-mass crit damage on zombies (4×, range-scaled).
- "HEADSHOT!" toast on player crits.

## Phase 1 (shooting) — Player aiming core
- `AimModel` spread/falloff math + headless unit test.
- Weapon aiming, per-weapon spread + range fields/values.
- `focus_aim` (Ctrl) input action.
- Bullet range→damage falloff + max-range despawn.
- Visible custom aim cursor (cone radius = spread, opacity = range fade, focus
  tint); server-synced aim state (running/injured/recoil debuffs + focus).

## Multiplayer
- Local multiplayer working; dedicated server deploy (Railway, first attempt).
- Room logic + codes; sequential room reuse so games run one after another.
- Weapon swap by dropping the held weapon; stopped tracking screen recordings.

## Phase 1–2 (foundation) — Core game
- Initial zombie game; first playable map + HUD; win/lose conditions.
- New map; props/scenery scatter (cars, fences, etc.).
- Shooter fog-of-war; zombie controller + visuals.
- Zombie merging (standard/fast/fat/master variants); NPCs; start menu +
  selection; special weapons.
