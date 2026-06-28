# Architecture

Top-down 2D survival game in **Godot 4.6.3** (GL Compatibility renderer).
Authoritative-server multiplayer: one peer (or a dedicated headless server) runs
the simulation; clients send input and render replicated state.

> `addons/godot_ai/` is the godot-ai MCP plugin — **tooling, not game code.**
> Ignore it when reasoning about the game.

## Boot flow
`project.godot` → main scene `scenes/ui/main_menu.tscn`. The menu sets
`GameState` (role, multiplayer flags, world seed) and asks `Net` to host/join.
When a match starts, `scenes/world/world.tscn` (`world.gd`) loads and spawns the
shooter, zombies, NPCs and items, then runs the authoritative loop.

## Autoloads (singletons)
Defined in `project.godot [autoload]`:
- **GameState** (`scripts/game_state.gd`) — cross-scene state: `role`
  (HUMAN/ZOMBIE), `multiplayer_active`, `is_dedicated_server`, `world_seed`.
  Set by the menu, read by `world.gd` at match start.
- **Net** (`scripts/network.gd`) — multiplayer transport: rooms, lobby, role
  claiming, rematch, dedicated `--server` mode. Emits `connected_to_server`,
  `room_joined`, `lobby_updated`, `room_closed`, etc.
- **Balance** (`scripts/balance.gd`) — **single source of truth for all gameplay
  tuning** (player, zombie variants, NPC, weapons, melee, headshots, merging,
  fog, aim). Read as e.g. `Balance.ZOMBIE.speed`, `Balance.PISTOL.damage`.
- **_mcp_game_helper** — part of the MCP plugin; ignore.

## Directory map
```
scenes/            # Game scenes, each .tscn paired with its .gd
  world/           # world.gd — authoritative spawn + match orchestration; fog draw
  shooter/         # shooter.gd — player (CharacterBody2D): movement, inventory,
                   #   shooting, reload, melee swing, focus/recoil aim, HP/death
  zombie/          # zombie.gd + master_zombie.gd; variants: zombie/fast/fat/master.tscn
  npc/             # npc_human.gd — AI survivors: hide, follow, shoot, convert
  bullet/          # bullet.gd — projectile w/ range→damage falloff, headshot crit
  pickup/          # pickup.gd — floor weapon/ammo/heal pickups (show weapon PNGs)
  loot_box/        # loot_box.gd — crate that bursts 1-3 items on interact; replicated
  props/           # static scatter props (car, dumpster, fence, statue, tree)
  ui/              # main_menu, pause_menu, game_over, hud, aim_cursor
scripts/           # Shared logic, autoloads, RefCounted helpers (see below)
  loot_table.gd    # LootTable — pure roll helpers (roll_item_count, roll_kind); headless-safe
  interact_pick.gd # Interact — choose_nearest() contextual interact resolver
shader/            # fog_zc.gdshader (zombie-controller fog; fog_of_war.gdshader removed)
resources/         # city_tileset.tres
sprites/           # weapon + entity PNG art
textures/          # generated tiles
test/              # headless unit tests (test_aim_model, test_melee, test_npc_aim,
                   #   test_weapon_visuals, test_loot_table, test_interact_pick)
docs/              # per-phase design specs + implementation plans
addons/godot_ai/   # MCP plugin — IGNORE
```

## scripts/ — shared logic
- **balance.gd** — all tuning constants (see Autoloads). Includes `LOOT` block
  for loot box tuning (box count, item-count chances, per-kind weights, heal
  amounts, burst geometry, interact radii).
- **loot_table.gd** (`class_name LootTable`, RefCounted) — pure, headless-safe
  loot math: `roll_item_count(r, chance_two, chance_three) -> int`,
  `roll_kind(r, weights: Dictionary) -> Variant`. No Pickup or Balance references.
- **interact_pick.gd** (`class_name Interact`, RefCounted) — `choose_nearest(
  origin, candidates) -> int` contextual interact resolver (nearest-wins, per-type
  radius). Pure; unit-tested in `test/test_interact_pick.gd`.
- **weapons.gd** (`class_name Weapons`, RefCounted) — weapon catalogue
  (`get_data(id)`) + the shared `fire()` that spawns pellets with spread.
  Used by both shooter and armed NPCs so spread math lives in one place. Runs
  server-side; bullets replicate via the spawner.
- **weapon_data.gd** (`class_name WeaponData`, Resource) — per-weapon stat
  struct (damage, cooldown, mag_size, pellets, bullet_speed, aim_base/max,
  range fields, `is_special`, `is_melee`).
- **aim_model.gd** (`AimModel`) — spread/falloff/headshot math (`random_in_disk`,
  range→damage, `is_headshot`). Pure functions, unit-tested.
- **npc_aim.gd** (`NpcAim`) — armed-NPC accuracy: debuffs, recoil, fire cap.
- **melee.gd** (`class_name Melee`, RefCounted) — `forward_strike` cone + recent-hit
  fatigue math. Unit-tested.
- **weapon_visuals.gd** — weapon id → PNG texture map (Phase 5 visuals).
- **merge_manager.gd / zombie_controller.gd** — zombie-side control & merging.
- **shooter_lighting.gd** (`ShooterLighting`) — HUMAN-role fog of war built on
  Godot 2D lighting: generates a hard-edged cone flashlight texture and a soft
  radial halo texture, builds `LightOccluder2D`s from building/edge tiles and
  props, and exposes `setup(shooter, world, ...)` which assembles a dark
  `CanvasModulate` + a cone `PointLight2D` + a halo `PointLight2D` (both
  parented to the shooter so the beam tracks aim with no per-frame code) +
  static occluders. Called from `world.gd::_setup_fog()` on the HUMAN role only.
- **fog_zombie_controller.gd** (`FogZombieController`) — zombie-side explored-map
  fog, driving `fog_zc.gdshader`. Unchanged.
- **prop_scatter.gd** — seeded scenery placement (seed from GameState so both
  peers match). **ping_visual.gd** — command ping marker.

## Core systems
- **Loot boxes:** 8 closed crates (`LootBox`, `scenes/loot_box/`) scatter on
  walkable tiles at match start. Pressing `E` near a crate calls `b.open()` on the
  server, which rolls 1–3 items (via `LootTable`) and bursts them as `Pickup`
  nodes within `burst_radius_px` of the box — each landing on a validated walkable,
  prop-free tile. The crate sprite swaps to opened and replicates via
  `MultiplayerSynchronizer` (`ON_CHANGE`). All tuning in `Balance.LOOT`.
- **Inventory (3 slots):** `1`=pistol, `2`=heavy/special, `3`=melee
  (`select_pistol/heavy/melee` actions). `Q` swaps, `X` drops, `E` gives the
  special to a following NPC. Weapons: Pistol, Rifle, Shotgun, Machine Gun
  (full-auto), Melee — all stats in `Balance`.
- **Aiming:** the on-screen aim ring radius and the real bullet spread read the
  **same** Balance numbers, so they stay coupled. Held `focus_aim` (Ctrl)
  shrinks spread over time; moving/being hurt/recoil widen it. Range → damage
  falloff is mirrored by cursor opacity.
- **Headshots:** center-mass crit zone on zombies (`Balance.HEADSHOT`), 4×
  range-scaled damage, "HEADSHOT!" toast.
- **NPCs:** survivors hide, can follow the shooter, shoot zombies when armed, and
  get converted to zombies on contact over `convert_duration`.
- **Fog of war:** two independent systems. **Shooter (HUMAN role):** a dark
  `CanvasModulate` fog is pierced by a hard-edged flashlight cone and a soft
  personal halo, both `PointLight2D`s parented to the shooter and casting
  real straight-line shadows through Godot's 2D shadow system; static
  `LightOccluder2D`s are built from building/edge tiles and props, dynamic ones
  sit on zombies/NPCs/master. Lives in `scripts/shooter_lighting.gd`
  (`ShooterLighting`), assembled by `world.gd::_setup_fog()`. Tunables:
  `Balance.FOG_SHOOTER` (ambient darkness, beam range/angle/energy, halo
  radius/energy, shadow toggles). **Zombie-controller fog:** explored-map AoE2
  style, `FogZombieController` / `fog_zc.gdshader` — unchanged. Both systems
  toggleable; `Balance.WORLD.fog_enabled` default off.

## Conventions
- **All tuning goes in `balance.gd`.** Never hardcode gameplay numbers in scenes.
- **Authoritative server:** gameplay mutations happen server-side; clients send
  input. Spawners replicate bullets/entities. Check `multiplayer.is_server()`
  patterns before adding state changes.
- **Physics layers:** 1 player, 2 zombie, 3 bullet, 4 npc.
- **Groups:** `zombies`, `shooter`, `fast_zombie`, `npcs`, `pickups`, `loot_boxes`.
- **Pure math in RefCounted helpers** (`AimModel`, `Melee`, `NpcAim`, `Weapons`,
  `LootTable`, `Interact`) so it can be headless-unit-tested in `test/`.
- **Testing gotcha:** the `test/` `SceneTree` scripts run via
  `Godot --headless --path . --script test/x.gd`, but that runner can't resolve
  `class_name` globals that extend scene types (`Pickup`, sometimes
  `AimModel`/`Weapons`) — reference helpers via `load("res://...")` in tests, and
  keep testable logic in RefCounted helpers. **Do not run these headless commands
  while the editor is open** — concurrent Godot processes can wipe `.godot/`
  ("Project data folder missing"; just Restart, it's cache). See CLAUDE.md Gotchas.

## Input map (`project.godot [input]`)
WASD move · `Q` swap weapon · `E` **interact** (contextual: open nearest crate /
grab nearest dropped item / give weapon to an adjacent following NPC at tight
radius / take a weapon back from an armed NPC — nearest-wins via `Interact`) ·
`X` drop · `1/2/3` select slot · `Ctrl` focus aim · `F1` toggle debug · arrows
pan camera · toggle view.
