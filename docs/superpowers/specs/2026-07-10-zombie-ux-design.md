# Zombie commander UX & NPC follow — design

Date: 2026-07-10. Approved by Mads. Three independent features, built in this
order (smallest first, each playtestable on its own):

1. Right-click attack targeting
2. Zombie fog rework (shooter-style lighting + explored memory)
3. NPC follow: breadcrumbs + combat formation

## 1. Right-click attack targeting

**Problem:** Right-click only issues a move order (`rpc_command_move` →
`zombie.set_command(pos)`). Clicking on an NPC or shooter walks zombies to the
spot but never locks onto the target — no "snap".

**Design:**
- In `zombie_controller.gd` right-click handling: hit-test `shooter` and `npcs`
  group members within ~20 px of the click (same radius as
  `_get_zombie_at_position`). Enemy found → send new
  `rpc_command_attack(zombie_names, target_name)`; otherwise fall through to
  the existing move command.
- `world.gd`: `rpc_command_attack` resolves the target node under `Entities/`
  and calls `zombie.set_attack_target(node)` (server-side, mirroring
  `rpc_command_move`).
- `zombie.gd`: new `attack_target` state, checked in `_physics_process`
  *before* `command_mode` (an explicit attack outranks a stale move order).
  While set, the zombie repathes to the target's live position each frame and
  bites via the existing `_check_contact_damage` cooldown attack
  (`target = attack_target`).
- **Visibility rule (only-while-visible):** each frame the server clears the
  lock if the target is not within vision range (`vision_range * 64` px,
  circular approximation of the fog diamond) of *any* zombie. On losing
  sight, the order degrades to a move order to the target's last-seen
  position, after which the zombie reverts to its stance.
- Lock also clears when the target dies, converts, or any new order (move,
  stance, movement mode, merge) arrives — all those setters already clear
  `command_mode` and will clear `attack_target` the same way.
- **Feedback:** attack orders show a **red** ping (existing `_show_ping`
  color parameter) at the target instead of the green move ping.

**Testing:** pure visibility/last-seen logic goes through `Targeting` /
a small static helper so it stays headless-testable. Behavior verified in the
live editor (solo zombie role) + MP smoke test.

## 2. Zombie fog rework

**Problem:** Zombie fog is a 47×47 tile mask with 3 states rendered by a
fullscreen shader — blocky, nothing like the shooter's smooth 2D-lighting fog.

**Design — hybrid (lights for "now", tile mask for "memory"):**
- **Current vision** = real lighting. A `CanvasModulate` darkens the world
  (same mechanism as shooter fog); every zombie gets a soft radial
  `PointLight2D` (radius = its `vision_range * 64` px, one shared texture from
  `ShooterLighting.make_radial_texture`) with `shadow_enabled = true`. Static
  occluders reuse `ShooterLighting.collect_static_occluder_positions` /
  `build_static_occluders` — buildings and props cast real vision shadows.
- **Role gating:** lights + modulate exist only on the zombie-commander view
  (set up where the ZC role activates, exactly as `ShooterLighting.setup` runs
  only for the HUMAN role). Lights attach on zombie spawn and die with the
  zombie (MP: on the ZC client, driven by the replicated zombie nodes).
- **Explored memory** = the existing `FogZombieController` grid, repurposed:
  unexplored tiles render **opaque black**; explored tiles render fully
  transparent (the CanvasModulate darkness is the "explored, unwatched" dim).
  The `vis_explored`/`vis_visible` distinction in the shader collapses to
  transparent.
- **LOS-honest memory:** tile reveal adds a Bresenham line check from the
  zombie's tile to each candidate tile, blocked by building tiles, so areas
  behind walls aren't marked explored until actually seen. Grid is 47×47 and
  vision is ~2 tiles — cost is trivial.
- **Tunables:** `Balance.FOG_ZC` gains `ambient_darkness`, `light_energy`,
  `light_tex_size`; existing `vis_*` keys reduce to the unexplored mask.
- **Information rules unchanged:** enemy visibility/minimap blips behave as
  today; only rendering changes.
- **Perf fallback:** if per-light shadows are heavy with a large horde,
  disable `shadow_enabled` on lights beyond the N zombies nearest the camera
  (knob in `Balance.FOG_ZC`).

**Testing:** LOS/Bresenham helper is pure logic → headless test. Visual result
verified by owner playtest + `editor_screenshot`.

## 3. NPC follow: breadcrumbs + formation

**Problem:** Following NPCs navigate straight to a single point 1 tile behind
the shooter — they cut corners, take different routes than the player, and
stand between the shooter and zombies.

**Design — trail + threat-aware formation, two modes:**
- **Breadcrumb trail:** the shooter records a breadcrumb every ~24 px of
  movement into a capped ring buffer (~64 points, server-side; the server has
  the replicated shooter position under client-auth movement).
- **Travel mode** (no zombie within threat range of the shooter): each
  following NPC targets a point *on the trail*, spaced by slot — 1st NPC ~1
  tile of trail arc-length behind the shooter, 2nd ~2 tiles, etc. Single-file
  retracing of the player's actual route. Existing `FOLLOW_DEADZONE` keeps
  them from jittering when the shooter idles.
- **Combat mode** (a zombie within threat range, e.g. `NPC_VISION_PX` of the
  shooter): formation slots. Threat direction = shooter → nearest visible
  zombie. Unarmed NPCs take slots directly behind the shooter (opposite the
  threat). 1 armed NPC → behind the player, offset to one side; 2 armed →
  one on each side of the player; further NPCs stack behind. NPCs never
  occupy the shooter→threat line.
- **Stable slots:** slot assignment sorts NPCs (armed first, then by node
  name) so slots don't reshuffle every frame.
- **Structure:** trail sampling + slot math in a new pure static helper
  `scripts/npc_follow.gd` (`extends RefCounted`, like `StanceLogic`/`NpcAim`),
  consumed by `npc_human.gd` `_process_following`. All distances/thresholds in
  `Balance.NPC` (breadcrumb spacing, trail cap, slot spacing, threat radius,
  side offsets).

**Testing:** `test/test_npc_follow.gd` headless test for the helper (trail
arc-length lookup, slot positions for 0/1/2 armed NPCs, threat-line
avoidance). Live-editor playtest for feel.

## Out of scope
- Order menu (`E` → stay/equip/goto/hold/hide), NPC flee-on-sight, zombie
  follow-another-zombie formations, minimap click-to-send — all stay in
  `docs/BACKLOG.md`.
- The "order arrow above fog" backlog item was already fixed (ping renders at
  z 150 above fog z 100) — checked off.

## MP / netcode notes
- All new orders flow client → `rpc_id(1, …)` → server state, like existing
  commands; zombies/NPCs remain server-simulated, positions replicated via
  `sync_pos` + NetSmooth. No changes to the client-auth shooter movement.
- Fog lights are purely client-side cosmetics on the ZC peer; no replication.
