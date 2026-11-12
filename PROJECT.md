# Project

## What it is
A top-down 2D zombie survival game built in **Godot 4.6.3**. Asymmetric
multiplayer for up to **5 players**: **1–4 co-op shooters** (with AI survivor NPCs
that can be armed and recruited) versus **1 zombie commander** (with merging
mechanics and variants). Built solo, iteratively, in numbered phases — each phase
has a design spec + implementation plan in `docs/`.

## Current status (2D game: Phase 9 · 3D conversion: Phase 10, in progress)
Single-player and **local multiplayer** both work; a dedicated server can be run
headless and deployed (see `DEPLOY.md` / Railway). The Railway deployment runs
**multiple concurrent matches** via the Go director (`server/director/`, Phase 9;
see `ARCHITECTURE.md` → *Server topology*). Implemented:

- ✅ Core loop: map, HUD, win/lose, props/scenery.
- ✅ Zombie control + merging + variants (standard / fast / fat / master).
- ✅ NPC survivors: hide, follow, shoot when armed, convert on contact.
- ✅ Multiplayer: rooms, lobby, role select, sequential rematch reuse. Online
  co-op for up to 5 players (1 zombie + 1–4 shooters): host-controlled start,
  per-shooter authority, friendly fire, random shooter spawns clear of the
  zombie, dead-shooter spectate, and last-man / master-death win conditions
  (Phase 7; owner multi-window playtest pending).
- ✅ "ZOMBIE COMMAND" visual identity (Phase 8, code-complete): code-built theme
  (`UITheme` autoload + `UIStyle` tokens, `docs/design_system.md`), restyled
  main-menu flow (logo, role cards, lobby/join), new loading screen (now the
  main scene) and settings screen (controls/HUD toggles/profile, persisted via
  the `Settings` autoload), restyled pause modal, shooter HUD bottom bar
  (health / weapon + ammo blocks / threat compass), zombie-commander overlay
  (stance colors, MERGE OPS, gold rally, framed minimap with green blips),
  game-over modal. Owner playtest pending.
- ✅ Shooting model: per-weapon spread, focus aim, range→damage falloff, visible
  aim cursor.
- ✅ Headshots: center-mass crit zone, 4× range-scaled damage.
- ✅ Inventory: 3-slot selection (1/2/3), full-auto machine gun.
- ✅ Melee weapon: swing, fatigue, drop, HUD readout.
- ✅ Weapon visuals: PNG sprites on player, NPCs, floor pickups, and HUD icon.
- ✅ Shooter fog-of-war: 2D-lighting flashlight cone + personal halo with real
  straight-line shadows from buildings, props, and moving entities
  (`ShooterLighting`). Tunables in `Balance.FOG_SHOOTER`.
- ✅ Zombie-commander fog: same lighting treatment — ambient darkness +
  per-zombie LOS vision lights (`ZombieLighting`), with the tile grid kept as
  unexplored-black explored memory (LOS-honest reveal). Tunables in
  `Balance.FOG_ZC`. Right-click **attack targeting** (red ping, chase while
  seen) and NPC breadcrumb-follow + combat formation (`NpcFollow`) landed
  2026-07-10 — owner playtest pending.
- ✅ Loot boxes: 8 closed crates scatter on walkable ground; `E` to open; 1–3
  items burst out onto validated tiles; sprite swaps to opened; fully replicated.
- ✅ RTS zombie experience (Phase 7): discrete cooldown attacks (zombies *hit*),
  unit separation (RVO avoidance), per-zombie stance state machine + nearest-enemy
  auto-attack, stance toolbar + control groups, health bars, a populating minimap
  (fog-aware enemy blips, ghost blips, under-attack pulse, gunshot ripple,
  click-to-jump), world-view gunshot ripple, and sound aggro. Tunables in
  `Balance.SEPARATION/STANCE/MINIMAP/AGGRO` and per-variant
  `damage_per_hit`/`attack_interval`. Owner playtest verification pending.

See [CHANGELOG.md](CHANGELOG.md) for the full phase history.

## 3D conversion (Phase 10, in progress)
The game is moving from top-down 2D to a **3D world**. Nothing in the shipping
2D game has been changed by this work yet — the only project-wide change is the
renderer (`gl_compatibility` → **Forward+**, needed for volumetric fog; the 2D
game was booted and verified unaffected).

What exists today is a **measuring instrument, not the game**: eight standalone
camera/aim test scenes in `scenes/test/`, run with **F6**, referenced by nothing
else in the project. They exist to settle the one question the conversion turns
on — *what camera makes a real Copenhagen street read as a canyon you are inside
rather than a map you are looking at?*

| Scene | View | Aim (RMB) |
|---|---|---|
| `camera_test_3d.tscn` (V1) | top-down 70° at 15 m, street-locked yaw | over-the-shoulder |
| `camera_test_v2_over_shoulder.tscn` (V2) | over-the-shoulder always | pulls to 2.0 m + 45° FOV |
| `camera_test_v3_hostile_process.tscn` (V3) | top-down at 9 m, rig yaw **is** the mouse, 80% forward view | over-the-shoulder |
| `camera_test_v4_first_person.tscn` (V4) | first person, eye height 1.65 m | 45° iron sights |

Each has a `*_night.tscn` twin (volumetric fog, moonlight, flashlight aimed at
the reticle, flickering sodium lamp). All eight share `scripts/test/camera_rig.gd`
+ `scripts/test/test_player.gd`, so a fix lands in all of them.
`scenes/test/test_structures.tscn` (an overhang and an enclosed room) is
instanced into all eight to test what each camera does under a roof.

The world is `assets/city/copenhagen_greybox.glb` — real OpenStreetMap geometry
via Blender/blosm, **ODbL 1.0, attribution required on distribution** (see
[CREDITS.md](CREDITS.md); do not strip the `asset_*` glTF extras).

**Test-scene controls:** WASD move · Shift sprint · C crouch · Space jump ·
RMB aim · ESC free mouse · LMB recapture · 1/2/3 preset cuts (V1 only).

**The trial is settled: the shooter ships in first person (V4).** The other
three scenes are kept as the record of how that was decided, and their camera
collision / occlusion work feeds the zombie-commander rig rather than the
shooter. Also settled on the way: the camera drops *below* the roofline rather
than widening the lens, and aiming and being under a roof want the same pose.

**Small dressed city (current test map):** `scenes/test/camera_test_v6_small_city.tscn`
runs the first-person rig on `assets/city/westvillage_small.glb`, a 250 x 170 m
crop with procedural facades (doors, windows, shopfronts, lit windows) and road /
sidewalk / crosswalk / backlot surfaces. Rebuild it from the source .blend with
`/Applications/Blender.app/Contents/MacOS/Blender -b assets/blender/maps/manhattan_westvillage.blend --python assets/blender/maps/build_small_city.py`
(the crop rect and all classification constants are at the top of the script),
then reimport. Look tuning lives in the shader uniforms (`lit_windows`,
`window_glow`, `shop_chance`, ...).

The full design — first-person shooter, top-down commander over the 3D world
with buildings going ~90% transparent when a zombie is underneath, per-part
zombie HP replacing the old headshot model, and an 11-stage plan — is
**[docs/superpowers/specs/2026-09-09-3d-conversion-design.md](docs/superpowers/specs/2026-09-09-3d-conversion-design.md)**.
Read it before starting any conversion work. See
[CHANGELOG.md](CHANGELOG.md) → Phase 10 for the full measured history.

## How to run
- **In editor:** open the project in Godot 4.6.3 and press Play (main scene is
  `scenes/ui/main_menu.tscn`). With an MCP session live, use `project_run` /
  `editor_screenshot`.
- **Local multiplayer:** `./run_local_mp.command` launches host + client locally.
- **Dedicated server:** run headless with `--server`; see `DEPLOY.md` (Dockerfile
  + Railway) for hosted play.
- **3D camera tests:** open any scene in `scenes/test/` and press **F6** (run
  current scene). They do not go through the menu and do not touch game state.

## Tests
Headless unit tests live in `test/` (`test_aim_model`, `test_melee`,
`test_npc_aim`, `test_weapon_visuals`, `test_lobby_model`, `test_shooter_select`)
covering the pure-logic helpers. Run via the godot-ai MCP `test_run`, or headless
with the editor closed. Run them after touching aim, melee, NPC accuracy,
weapon-visual, or lobby/shooter-selection logic.

## Tooling notes
- The **godot-ai MCP** plugin (`addons/godot_ai/`) is installed for AI-driven
  editing against the live editor — not part of the shipped game.
- `.claude/settings.local.json` holds local Claude Code settings.

## Next / backlog
**The organized open-work list lives in [docs/BACKLOG.md](docs/BACKLOG.md)** —
keep that file current. Status notes below:

Phase 8 visual identity is code-complete across
menus, loading, settings, pause, shooter HUD, zombie-commander overlay, and
game over (owner playtest pending — flows should behave exactly as before;
only visuals changed. Verify: solo both roles, host→lobby→start, join-by-code,
ESC pause→settings→back, merge/stance/rally buttons still clickable, game-over
buttons). Design ideas not yet built (from the mockup): selected-unit portraits
with HP micro-bars + group stats in a ZC bottom panel, control-group slot bar,
placement banner for patrol/flee point picking, shooter inventory slot cards. Phase 7 RTS zombie experience landed (code-complete,
clean boot). **Owner playtest pending** to confirm behavior: discrete-hit damage
chunks, no unit overlap, stance behaviors (hold ignores fire, patrol loops,
skittish flees on sight), health bars on both views, minimap terrain/blips/ripples,
and sound aggro. Known follow-up: stance/patrol/flee state is server-side, so the
selection-drawer preview + stance glyph render correctly for a host zombie player
or in single-player; client-side preview would need those fields replicated.

**Online 5-player co-op (Phase 7) is code-complete with a clean boot; a
multi-window owner playtest is pending** to confirm: lobby roster + host Start,
each shooter driving only its own body, random spawns clear of the zombie,
friendly fire, dead-shooter spectate (non-pausing banner + camera follows a
living ally), and the win/lose conditions (zombie wins on wipe, shooters win on
master death). Known visual follow-up: a spectator sees the match through the
fog set up for their own (dead) shooter, not the ally they're watching.
