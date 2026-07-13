# Project

## What it is
A top-down 2D zombie survival game built in **Godot 4.6.3**. Asymmetric
multiplayer for up to **5 players**: **1–4 co-op shooters** (with AI survivor NPCs
that can be armed and recruited) versus **1 zombie commander** (with merging
mechanics and variants). Built solo, iteratively, in numbered phases — each phase
has a design spec + implementation plan in `docs/`.

## Current status (as of Phase 5)
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

## How to run
- **In editor:** open the project in Godot 4.6.3 and press Play (main scene is
  `scenes/ui/main_menu.tscn`). With an MCP session live, use `project_run` /
  `editor_screenshot`.
- **Local multiplayer:** `./run_local_mp.command` launches host + client locally.
- **Dedicated server:** run headless with `--server`; see `DEPLOY.md` (Dockerfile
  + Railway) for hosted play.

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
