# Design: 5-player online (4 shooters + 1 zombie)

**Date:** 2026-07-07
**Status:** Approved (brainstorm) — pending implementation plan

## Goal

Let up to **5 players** play online at once: **1–4 shooters** (co-op survivors)
versus **1 zombie** commander who controls the horde via the existing RTS layer.
Today the whole stack is hardcoded to exactly 2 players (one `_human_peer`, one
`_zombie_peer`, a single `shooter` in the world). This work generalizes the
"1 human" assumption into "N shooters" while keeping the existing
authoritative-server architecture unchanged.

## Locked-in rules

- **Start:** host-controlled. The host presses **Start**; valid only when the
  zombie slot is filled **and** at least one shooter is present.
- **Roster:** exactly 1 zombie (required), 1–4 shooters. Room capacity 5.
- **Death:** a dead shooter becomes a **spectator** (camera follows the nearest
  living shooter). No respawns.
- **Zombie wins** when **all shooters are dead**.
- **Shooters win** when the **master zombie dies** (today's condition,
  generalized to broadcast to every shooter).
- **Friendly fire: ON.** Shooter bullets damage other shooters (not the firer).
- **Spawns:** each shooter spawns at a **random walkable tile**, kept a minimum
  distance from the zombie/master spawn and spaced from other shooters.
- **Mid-match shooter disconnect** counts as **dead** toward the zombie's win.

## Approach

Keep the authoritative-server model exactly as-is (server simulates everything;
clients send input and render replicated state). Generalize the single-shooter
assumption in six areas. No client-side prediction, no new team abstraction —
minimal generalization for a 5-player co-op game the server already fully
simulates.

**Transport is unchanged:** WebSocket, single active room, dedicated headless
server on Railway. Only the member cap changes (2 → 5).

## Components / changes

### 1. Lobby & roles — `scripts/network.gd`

- Replace `_human_peer: int` + `_zombie_peer: int` with:
  - `_zombie_peer: int` (single slot, 0 = free)
  - `_shooter_peers: Array[int]` (max 4)
- `_members` cap: 2 → 5. `join_room` refuses when `_members.size() >= 5`.
- `claim_role(role)`:
  - `HUMAN` → append sender to `_shooter_peers` if not present and size < 4;
    otherwise ignore.
  - `ZOMBIE` → take the zombie slot if free.
  - Claiming releases whatever slot the sender previously held (allows switching).
- **Remove auto-start.** Add `start_match()` RPC:
  - callable only by the host (`_members[0]`),
  - valid only when `_zombie_peer != 0` **and** `_shooter_peers` is non-empty.
- `lobby_updated` signal changes shape:
  `lobby_updated(zombie_peer: int, shooter_peers: Array, host_peer: int)`
  so the UI can render every slot and show Start to the host only.
- `_start_match` sends `_assign_role_and_start` to the zombie and each shooter,
  and hands the world the **ordered list of shooter peer ids** so the server can
  spawn one shooter per peer with the correct multiplayer authority. Mechanism:
  store the shooter-peer list on `GameState` (see §7) before the scene change so
  `world.gd` can read it on the server.
- Disconnect handling (`_handle_member_left`):
  - **shooter leaves mid-match** → remove from `_shooter_peers`; the world kills
    / despawns that shooter (counts as dead). Match continues.
  - **zombie leaves**, or **host leaves in lobby** → close the room as today.
- Rematch: same players and roles.

### 2. Per-shooter ownership — `scenes/shooter/shooter.gd`

- Each shooter node gets `set_multiplayer_authority(peer_id)` at spawn.
- Input send switches from the role/`controls_enabled` flag to
  **`is_multiplayer_authority()`** — each client's `_process` drives only its own
  shooter. `controls_enabled` remains for the death/spectate gate.
- Server-side `_send_input` (and the discrete `_action_*` RPCs) validate
  `get_remote_sender_id() == get_multiplayer_authority()` so a client cannot
  puppet another player's shooter.

### 3. World: spawn & targeting — `scenes/world/world.gd`

- Replace the single `shooter` var with **`shooters: Array`** (server-side
  authoritative list). Add `nearest_shooter(pos) -> Node` that ignores
  dead/spectating shooters (returns `null` when none alive).
- `_spawn_shooter()` → **`_spawn_shooters()`**: iterate the shooter-peer list; for
  each, pick a **random walkable tile** (validated clear of buildings/props, as
  the existing NPC spawn loop does) that is:
  - at least `Balance.SHOOTER.min_dist_from_zombie_px` from the master/zombie
    spawn point, and
  - spaced from already-placed shooters (reuse the NPC min-separation check).
  Instantiate, `set_multiplayer_authority(peer_id)`, add via the spawner, connect
  `player_died`.
- **Targeting** — master zombie, standard zombies, and NPCs must retarget to the
  **nearest alive shooter** each scan instead of holding a fixed `shooter`
  reference:
  - `master_zombie.set_target(...)` / `z.set_target(...)` / `npc.shooter = ...`
    become dynamic. Simplest fit with existing code: their target-selection reads
    the `shooter` group (or `world.nearest_shooter()`); the `Targeting` helper
    already scans groups, so extend those call sites to pick nearest alive shooter.
- Per-client setup in `_apply_role` / `_on_entity_spawned`: attach camera + fog +
  controls only to the shooter whose authority == local peer id. The zombie
  client keeps today's RTS camera. Non-owned shooters are just replicated bodies.

### 4. Death, spectate & win/lose — `scenes/world/world.gd`, `shooter.gd`

- Server tracks alive shooters (derive from `shooters` + each shooter's
  `is_dead`).
- `_on_player_died(shooter)`:
  - mark that shooter dead; tell its owning client to enter **spectator mode**
    (disable controls, camera follows `nearest_shooter()` of the living;
    "You died — spectating" overlay).
  - if **no shooters remain alive** → `_game_over` with zombie = WIN,
    shooters = LOSE.
- `_on_master_zombie_died()` → `_game_over` with shooters = WIN, zombie = LOSE
  (existing path; ensure it broadcasts to all shooter peers).
- `_game_over` message is rendered per role on each client (shooters see one
  result, the zombie the opposite), as today.

### 5. Friendly fire — `scenes/bullet/bullet.gd`

- Current `_on_body_entered` returns early for any `shooter`-group body. Change:
  - if `body == shooter_ref` (the firer) → ignore (avoids barrel self-hits).
  - else if body is a shooter → apply `_damage_for_hit()` (range falloff) via
    `take_damage`, spawn the shooter blood FX, `queue_free()`.
- Headshot crit on shooters: **not applied** (keep friendly fire simple; only
  falloff damage). Revisit only if desired later.

### 6. Lobby UI — `scenes/ui/main_menu.gd` (+ lobby scene nodes)

- Roster shows the **zombie slot + 4 shooter slots** and which peer holds each,
  driven by the new `lobby_updated(zombie_peer, shooter_peers, host_peer)` signal.
- Buttons: **Claim Shooter** / **Claim Zombie**.
- **Start** button visible to the host only, enabled when start is valid
  (zombie filled + ≥1 shooter).

### 7. State plumbing — `scripts/game_state.gd`

- Add a field to carry the assigned shooter-peer list from `Net._start_match`
  into `world.gd` on the server, e.g. `var shooter_peers: Array[int] = []`.
  Keep the `Role { HUMAN, ZOMBIE }` enum: a peer is either a shooter (HUMAN) or
  the zombie commander (ZOMBIE).

### 8. Balance — `scripts/balance.gd`

- Add `SHOOTER.min_dist_from_zombie_px` (spawn clearance from the zombie).
- Reuse the existing NPC min-separation constant for shooter spacing, or add a
  sibling `SHOOTER.min_dist_from_shooter_px` if the NPC value doesn't fit.

## Testing

Follow the `test/` conventions (pure logic in `RefCounted` helpers, referenced
via `load("res://...")`, headless `SceneTree` runners, editor closed):

- **`LobbyModel`** (new RefCounted helper): claim / switch / full / start-validity
  rules extracted from `network.gd` so they're unit-testable without a peer.
  Tests: claiming fills slots, switching releases the old slot, 5th shooter is
  refused, start invalid without a zombie or without a shooter.
- **`nearest_shooter` selection**: pure nearest-alive-among-candidates helper
  (mirror the existing `Targeting`/`MinimapMath` style) with tests for
  nearest-wins and dead-shooter exclusion.
- Boot test: `project_run` + `logs_read` shows **zero `SCRIPT ERROR`**.
- Live playtest by the owner (host + multiple clients) for camera/fog/spectate
  behaviour, since MCP game-capture is flaky (see CLAUDE.md gotchas).

## Out of scope / no change

- Transport and the Railway dedicated server (only member cap changes).
- The zombie RTS command layer (stances, minimap, control groups).
- Fog systems (shooter flashlight fog; zombie explored-map fog).
- Respawns, AI-filled slots, match timers, shooter-to-zombie conversion on death
  (all explicitly ruled out during brainstorming).
