# Changelog

Phase-organized history (newest first), reconstructed from git. Append a line
here as part of finishing any meaningful change.

## Phase 9 — Concurrent games (director + server pool)
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
