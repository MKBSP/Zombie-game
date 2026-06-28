# Project

## What it is
A top-down 2D zombie survival game built in **Godot 4.6.3**. Asymmetric
multiplayer: one side plays the **human shooter** (with AI survivor NPCs that can
be armed and recruited), the other controls **zombies** (with merging mechanics
and variants). Built solo, iteratively, in numbered phases — each phase has a
design spec + implementation plan in `docs/`.

## Current status (as of Phase 5)
Single-player and **local multiplayer** both work; a dedicated server can be run
headless and deployed (see `DEPLOY.md` / Railway). Implemented:

- ✅ Core loop: map, HUD, win/lose, props/scenery.
- ✅ Zombie control + merging + variants (standard / fast / fat / master).
- ✅ NPC survivors: hide, follow, shoot when armed, convert on contact.
- ✅ Multiplayer: rooms, lobby, role select, sequential rematch reuse.
- ✅ Shooting model: per-weapon spread, focus aim, range→damage falloff, visible
  aim cursor.
- ✅ Headshots: center-mass crit zone, 4× range-scaled damage.
- ✅ Inventory: 3-slot selection (1/2/3), full-auto machine gun.
- ✅ Melee weapon: swing, fatigue, drop, HUD readout.
- ✅ Weapon visuals: PNG sprites on player, NPCs, floor pickups, and HUD icon.
- ✅ Shooter fog-of-war: 2D-lighting flashlight cone + personal halo with real
  straight-line shadows from buildings, props, and moving entities
  (`ShooterLighting`). Zombie-controller fog unchanged. Tunables in
  `Balance.FOG_SHOOTER`.
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
`test_npc_aim`, `test_weapon_visuals`) covering the pure-math helpers. Run via the
godot-ai MCP `test_run`. Run them after touching aim, melee, NPC accuracy, or
weapon-visual logic.

## Tooling notes
- The **godot-ai MCP** plugin (`addons/godot_ai/`) is installed for AI-driven
  editing against the live editor — not part of the shipped game.
- `.claude/settings.local.json` holds local Claude Code settings.

## Next / backlog
(Keep this list current.) Phase 7 RTS zombie experience landed (code-complete,
clean boot). **Owner playtest pending** to confirm behavior: discrete-hit damage
chunks, no unit overlap, stance behaviors (hold ignores fire, patrol loops,
skittish flees on sight), health bars on both views, minimap terrain/blips/ripples,
and sound aggro. Known follow-up: stance/patrol/flee state is server-side, so the
selection-drawer preview + stance glyph render correctly for a host zombie player
or in single-player; client-side preview would need those fields replicated.
