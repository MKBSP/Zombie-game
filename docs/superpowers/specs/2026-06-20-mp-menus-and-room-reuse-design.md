# Multiplayer menus + room reuse — design

Date: 2026-06-20
Status: approved, pre-implementation

## Problem

1. **Server stuck on one game.** After a match ends, the server never frees its
   single room. `network.gd` resets room state only in `_close_room()`, which
   fires solely when *all* members disconnect. The dedicated server also stays
   inside `world.tscn` forever. Result: hosting a second game is silently
   refused ("A game is already running") or half-broken.
2. **No game-over controls.** `game_over.gd` only listens for the `R` key. No
   buttons, no clear "play again" / "main menu" choice.
3. **No in-game menu.** No way to pause/leave mid-match.

## Goals

- One active room at a time (keep current single-room model), but the server
  cleanly returns to idle after every match so games can be hosted
  back-to-back indefinitely.
- Game-over screen with **Play Again** (true rematch) and **Quit to Main Menu**
  buttons.
- Esc in-game overlay with **Resume** and **Quit to Main Menu**.

Non-goals: concurrent rooms, matchmaking, mid-match heartbeat/staleness
detection (see Known limitations).

## Design

### A. Room lifecycle (`scripts/network.gd`)

Track the host explicitly: the room owner is `_members[0]` (set in
`create_room`).

**Match end** — triggered from `world.gd._game_over` on the server:
- New `Net.server_on_match_ended()`: set `_match_started = false` but **keep**
  `_room_code`, `_members`, and the two role assignments so a rematch can reuse
  them. On the dedicated server, `change_scene_to_file("main_menu.tscn")` to
  drop the finished world and sit idle.

**Play Again (rematch)** — new client→server RPC `request_rematch()`:
- Guard: caller is a member, `_match_started == false`, both roles still filled.
- If valid, call existing `_start_match()` again (new seed, re-send
  `_assign_role_and_start` to both, reload `world.tscn` on the server). The
  `_match_started` guard makes a duplicate request from the second player a
  no-op.

**Quit to Main Menu** — new client→server RPC `leave_room()` plus client helper
`request_leave_room()` (sends the RPC, then `leave()`):
- Server removes the sender from `_members`, frees any role they hold.
- Resolution by phase:
  - **Lobby (not started), non-host leaves:** keep room open, `_broadcast_lobby`
    (host keeps waiting for a new joiner).
  - **Lobby, host leaves / match started / match ended:** `_close_room()` and
    notify any remaining member with new server→client RPC
    `_room_closed(reason)`.
- `_room_closed` on the client: brief status, `Net.leave()`, return to
  main menu (reuse `_back_to_menu`).

**Disconnect** — `_on_server_peer_disconnected` uses the same phase logic as
`leave_room` (a dropped peer is treated as that peer leaving). This also makes
mid-match rage-quits/disconnects free the room.

**Server idempotency** — `start_dedicated_server()` returns early if already
serving (so re-entering `main_menu._ready()` with `--server` after a match does
not recreate the peer / drop connections). `main_menu._ready()` keeps calling
it (now safe).

### B. Game-over screen (`scenes/ui/game_over.tscn` + `.gd`)

- Add `PlayAgainButton` and `MainMenuButton` to the existing VBox. Remove the
  `R`-key-only flow.
- **Play Again:**
  - Single-player: `get_tree().paused = false`, `reload_current_scene()`.
  - Multiplayer: `Net.request_rematch()` and wait — the server's
    `_assign_role_and_start` reloads `world.tscn` on this client.
- **Quit to Main Menu:**
  - Single-player: unpause, change to `main_menu.tscn`.
  - Multiplayer: `Net.request_leave_room()`, unpause, change to `main_menu.tscn`.
- `_assign_role_and_start` sets `get_tree().paused = false` before the scene
  change so a rematch never loads paused.
- If the opponent leaves first, this client receives `_room_closed` and is sent
  to the menu (Play Again is moot).

### C. In-game Esc menu

- New `scenes/ui/pause_menu.tscn` + `pause_menu.gd`, added to world under
  `HUDLayer` as `PauseMenu` (hidden by default, `process_mode = ALWAYS`,
  drawn above the HUD).
- Owns its own input: Esc toggles visibility. Buttons: **Resume**,
  **Quit to Main Menu**.
- Single-player: opening sets `get_tree().paused = true`; Resume/close unpauses.
- Multiplayer: does **not** pause (shared sim runs on the server); overlay only.
- Quit to Main Menu: same paths as the game-over screen's quit.
- Guard against the dedicated server (no input there anyway): skip all setup if
  `GameState.is_dedicated_server`.

## Data flow (rematch)

```
client: PlayAgain -> Net.request_rematch() --RPC--> server.request_rematch()
server: _start_match() -> new seed
        -> _assign_role_and_start.rpc_id(human/zombie)  (clients reload world)
        -> change_scene_to_file(world.tscn)             (server reloads world)
```

## Testing

- Local two-window flow via `run_local_mp.command`: host + join, finish a match,
  Play Again restarts both; Quit returns both to menu; then host a brand-new
  game successfully (the core regression).
- Single-player: Esc pauses + resumes; game-over Play Again reloads; Quit exits.
- Disconnect: kill one client mid-match; the other lands on the menu and the
  room frees for a new host.

## Known limitations

- Web browser refresh **mid-match** may not deliver a clean WebSocket close, so
  a ghost connection could briefly hold the room until the socket times out.
  The match-end reset and explicit `leave_room` cover all intentional exits and
  the normal end-of-game path (the reported bug). A heartbeat-based staleness
  sweep is deferred.
- Either player can trigger the rematch; the other is pulled into the new match.
  Acceptable for a 2-player game between friends.
