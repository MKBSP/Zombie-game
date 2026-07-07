# 5-Player Online (4 Shooters + 1 Zombie) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let up to 5 players play one online match — 1–4 co-op shooters versus 1 zombie commander — by generalizing the current hardcoded 2-player (1 human + 1 zombie) stack.

**Architecture:** Keep the existing authoritative-server model (server simulates everything; clients send input and render replicated state). Replace the single `_human_peer`/`shooter` assumptions with a list of shooter peers, each owning its own replicated shooter node via `set_multiplayer_authority`. The host explicitly starts the match. Zombie targeting is already group-based, so most AI needs no change.

**Tech Stack:** Godot 4.6.3 (GL Compatibility, 2D), GDScript, WebSocketMultiplayerPeer, MultiplayerSpawner/MultiplayerSynchronizer, dedicated headless server on Railway.

## Global Constraints

- **Godot 4.6.3**, GL Compatibility renderer. Main scene `scenes/ui/main_menu.tscn`.
- **All game-file edits go through the godot-ai MCP** (`script_patch`, `script_create`, `node_*`, `scene_*`, `filesystem_manage`) so the live editor stays in sync. Never edit game files by a path the editor won't see.
- **Never `git push`.** Commit only when Mads asks — the `git commit` steps below are provided for when he does; do not run them unprompted.
- **All gameplay numbers live in `scripts/balance.gd`.** Never hardcode tuning in scenes or scripts.
- **Do NOT run headless `Godot --script test/x.gd` or `--import` while the live editor is open** — concurrent processes can wipe `.godot/`. Close the editor first, or run tests in a throwaway copy.
- **Headless `test/` runners cannot resolve `class_name` globals that extend scene types.** Keep pure logic in `extends RefCounted` helpers and reference them via `load("res://...")` in tests.
- **Authoritative server:** all state mutations happen server-side (`multiplayer.is_server()`), clients send input via RPC. Bullets/entities replicate via the spawner.
- Roles: `GameState.Role { HUMAN, ZOMBIE }` — HUMAN = a shooter, ZOMBIE = the horde commander.
- Physics layers: 1 player, 2 zombie, 3 bullet, 4 npc. Groups: `zombies`, `shooter`, `master_zombie`, `fast_zombie`, `npcs`, `pickups`, `loot_boxes`.
- **Networked/authority behavior cannot be unit-tested headless.** Those tasks are verified by a clean boot (`project_run` + `logs_read` shows zero `SCRIPT ERROR`) plus an owner playtest with multiple windows. Pure helpers (`LobbyModel`, `ShooterSelect`) ARE unit-tested.

---

## Locked-in rules (from the approved spec)

- Host presses Start; valid only when the zombie slot is filled AND ≥1 shooter present.
- Exactly 1 zombie (required), 1–4 shooters, room capacity 5.
- Dead shooter → spectator (camera follows nearest living shooter); no respawn.
- Zombie wins when all shooters dead. Shooters win when the master zombie dies.
- Friendly fire ON (a bullet damages any shooter except its own firer).
- Shooters spawn on random walkable tiles, min distance from the zombie/master spawn, spaced from each other.
- Mid-match shooter disconnect counts as dead.

## File structure

- **Create** `scripts/lobby_model.gd` — pure `LobbyModel` (RefCounted): claim/switch/full/start-validity rules. Unit-tested.
- **Create** `scripts/shooter_select.gd` — pure `ShooterSelect` (RefCounted): nearest-alive selection. Unit-tested.
- **Create** `test/test_lobby_model.gd`, `test/test_shooter_select.gd` — headless runners.
- **Modify** `scripts/game_state.gd` — add `shooter_peers: Array[int]`.
- **Modify** `scripts/balance.gd` — add `SHOOTER.min_dist_from_zombie_px`, `SHOOTER.min_dist_from_shooter_px`.
- **Modify** `scripts/network.gd` — lobby refactor (zombie + shooter list), host `start_match`, capacity 5, new `lobby_updated` shape, disconnect handling.
- **Modify** `scenes/ui/main_menu.gd` — new lobby signal, Start button, shooter-count roster.
- **Modify** `scenes/shooter/shooter.gd` — authority-based input + server-side sender validation + spectate entry.
- **Modify** `scenes/world/world.gd` — `shooters` array, `_spawn_shooters`, `nearest_shooter`, per-client view, initial NPC/zombie target, death/spectate, win/lose.
- **Modify** `scenes/bullet/bullet.gd` — friendly fire.

---

## Task 1: State + Balance plumbing

**Files:**
- Modify: `scripts/game_state.gd`
- Modify: `scripts/balance.gd`

**Interfaces:**
- Produces: `GameState.shooter_peers: Array[int]` (server writes before scene change; world reads). `Balance.SHOOTER.min_dist_from_zombie_px: float`, `Balance.SHOOTER.min_dist_from_shooter_px: float`.

- [ ] **Step 1: Add `shooter_peers` to GameState**

In `scripts/game_state.gd`, after the `world_seed` line, add:

```gdscript
## Peer ids assigned to the shooter role for the current match, set by Net on
## the server just before the world loads. Read by world.gd to spawn one shooter
## per peer with the correct multiplayer authority.
var shooter_peers: Array[int] = []
```

- [ ] **Step 2: Add spawn-clearance constants to Balance**

In `scripts/balance.gd`, inside the existing `SHOOTER` dictionary, add two entries (match the file's existing dict style):

```gdscript
	# Multiplayer spawn placement: keep shooters away from the zombie spawn and
	# from each other (pixels; 64px = 1 tile).
	"min_dist_from_zombie_px": 768.0,
	"min_dist_from_shooter_px": 256.0,
```

- [ ] **Step 3: Verify clean boot**

Via MCP with the editor open: `project_run`, then `logs_read source=all`.
Expected: zero `SCRIPT ERROR`. (No behavior change yet — this just confirms the constants parse.)

- [ ] **Step 4: Commit (only if Mads asks)**

```bash
git add scripts/game_state.gd scripts/balance.gd
git commit -m "feat(mp): add shooter_peers state + shooter spawn-clearance balance"
```

---

## Task 2: LobbyModel pure helper (TDD)

**Files:**
- Create: `scripts/lobby_model.gd`
- Test: `test/test_lobby_model.gd`

**Interfaces:**
- Produces (`class_name LobbyModel`, RefCounted), all static, operating on a plain state dict `{ "zombie": int, "shooters": Array }`:
  - `LobbyModel.claim(state: Dictionary, peer: int, role: int, max_shooters: int) -> Dictionary` — returns the new state. `role` matches `GameState.Role` (0 = HUMAN/shooter, 1 = ZOMBIE). Releases any slot `peer` already holds, then grants the requested slot if available.
  - `LobbyModel.remove(state: Dictionary, peer: int) -> Dictionary` — frees whatever slot `peer` held.
  - `LobbyModel.can_start(state: Dictionary) -> bool` — true when `zombie != 0` and `shooters` non-empty.

Note: use role int literals (0 HUMAN, 1 ZOMBIE) in the helper so it stays headless (no `GameState` dependency); the test asserts these literals.

- [ ] **Step 1: Write the failing test**

Create `test/test_lobby_model.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var LM = load("res://scripts/lobby_model.gd")
	var fail := 0

	# start state
	var s := { "zombie": 0, "shooters": [] as Array }

	# claim zombie
	s = LM.claim(s, 10, 1, 4)  # peer 10 -> ZOMBIE
	if s["zombie"] != 10: push_error("zombie not claimed"); fail += 1

	# claim two shooters
	s = LM.claim(s, 20, 0, 4)  # HUMAN
	s = LM.claim(s, 30, 0, 4)
	if s["shooters"] != [20, 30]: push_error("shooters wrong: %s" % [s["shooters"]]); fail += 1

	# can_start now true
	if not LM.can_start(s): push_error("should be startable"); fail += 1

	# switching: peer 20 takes zombie -> releases its shooter slot, replaces zombie holder? No: zombie taken.
	# zombie is held by 10, so 20's ZOMBIE claim is refused; 20 keeps shooter.
	var s2 := LM.claim(s, 20, 1, 4)
	if s2["zombie"] != 10 or 20 not in s2["shooters"]: push_error("occupied zombie should refuse, keep shooter"); fail += 1

	# switching: shooter 30 switches to zombie after zombie freed
	var s3 := LM.remove(s, 10)              # free zombie
	s3 = LM.claim(s3, 30, 1, 4)             # 30 -> ZOMBIE, drops shooter slot
	if s3["zombie"] != 30 or 30 in s3["shooters"]: push_error("switch to zombie failed"); fail += 1

	# capacity: 5th shooter refused
	var s4 := { "zombie": 1, "shooters": [2, 3, 4, 5] as Array }
	s4 = LM.claim(s4, 6, 0, 4)
	if s4["shooters"].size() != 4: push_error("5th shooter should be refused"); fail += 1

	# can_start false without zombie / without shooters
	if LM.can_start({ "zombie": 0, "shooters": [2] as Array }): push_error("no zombie -> not startable"); fail += 1
	if LM.can_start({ "zombie": 1, "shooters": [] as Array }): push_error("no shooters -> not startable"); fail += 1

	# duplicate claim is idempotent
	var s5 := LM.claim({ "zombie": 0, "shooters": [7] as Array }, 7, 0, 4)
	if s5["shooters"] != [7]: push_error("duplicate shooter claim should be idempotent"); fail += 1

	if fail == 0: print("test_lobby_model: OK")
	quit(fail)
```

- [ ] **Step 2: Run the test to verify it fails**

Close the editor first (see Global Constraints). Run:

```bash
cd ~/Desktop/zombie-game && godot --headless --path . --script test/test_lobby_model.gd
```

Expected: non-zero exit / `Parse Error` — `lobby_model.gd` doesn't exist yet.

- [ ] **Step 3: Implement LobbyModel**

Create `scripts/lobby_model.gd`:

```gdscript
extends RefCounted
class_name LobbyModel

## Pure lobby role logic — no GameState / networking, so it is headless-testable.
## State is a dict: { "zombie": int, "shooters": Array }  (0 = free slot).
## role ints match GameState.Role: 0 = HUMAN (shooter), 1 = ZOMBIE.

const ROLE_HUMAN := 0
const ROLE_ZOMBIE := 1

static func _copy(state: Dictionary) -> Dictionary:
	return { "zombie": state.get("zombie", 0), "shooters": (state.get("shooters", []) as Array).duplicate() }

## Free whatever slot `peer` currently holds.
static func remove(state: Dictionary, peer: int) -> Dictionary:
	var s := _copy(state)
	if s["zombie"] == peer:
		s["zombie"] = 0
	s["shooters"].erase(peer)
	return s

## Grant the requested role if available, releasing whatever slot `peer` already
## held. A refused claim (role taken / shooters full) is a no-op: the player
## keeps its current slot rather than being dropped. (Corrected during execution —
## the original release-first-always version dropped players on a refused claim.)
static func claim(state: Dictionary, peer: int, role: int, max_shooters: int) -> Dictionary:
	if role == ROLE_ZOMBIE:
		if state.get("zombie", 0) == peer:
			return _copy(state)  # already zombie — idempotent
		if int(state.get("zombie", 0)) != 0:
			return _copy(state)  # taken by someone else — refuse, keep current slot
		var s := remove(state, peer)  # release old shooter slot, take zombie
		s["zombie"] = peer
		return s
	else:  # ROLE_HUMAN / shooter
		if peer in (state.get("shooters", []) as Array):
			return _copy(state)  # already a shooter — idempotent
		if (state.get("shooters", []) as Array).size() >= max_shooters:
			return _copy(state)  # full — refuse, keep current slot
		var s := remove(state, peer)  # release old zombie slot, take shooter
		s["shooters"].append(peer)
		return s

## The host may start only with a zombie and at least one shooter.
static func can_start(state: Dictionary) -> bool:
	return int(state.get("zombie", 0)) != 0 and not (state.get("shooters", []) as Array).is_empty()
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ~/Desktop/zombie-game && godot --headless --path . --script test/test_lobby_model.gd
```

Expected: prints `test_lobby_model: OK`, exit 0.

- [ ] **Step 5: Commit (only if Mads asks)**

```bash
git add scripts/lobby_model.gd test/test_lobby_model.gd
git commit -m "feat(mp): LobbyModel pure role logic + unit tests"
```

---

## Task 3: Network lobby refactor (zombie + shooter list, host start)

**Files:**
- Modify: `scripts/network.gd`

**Interfaces:**
- Consumes: `LobbyModel` (Task 2), `GameState.shooter_peers` (Task 1).
- Produces:
  - New signal `lobby_updated(zombie_peer: int, shooter_peers: Array, host_peer: int)` (replaces the 2-arg version).
  - Client API `Net.request_start()` → server RPC `start_match()`.
  - Server state `_zombie_peer: int`, `_shooter_peers: Array[int]`, `_members: Array[int]` (cap 5).

- [ ] **Step 1: Replace room-state vars and constants**

In `scripts/network.gd`, change the max-members assumptions. Replace the two role vars:

```gdscript
# was: var _human_peer: int = 0 / var _zombie_peer: int = 0
var _zombie_peer: int = 0
var _shooter_peers: Array[int] = []
const MAX_SHOOTERS := 4
const MAX_MEMBERS := 5
```

Update the `lobby_updated` signal declaration:

```gdscript
## Lobby roster changed: the zombie peer (0 = free), the array of shooter peers,
## and the host peer (members[0]) so only the host shows the Start button.
signal lobby_updated(zombie_peer: int, shooter_peers: Array, host_peer: int)
```

- [ ] **Step 2: Update room lifecycle to use the new state**

Replace `create_room`, `join_room`, `claim_role`, `_broadcast_lobby`, and remove auto-start. New bodies:

```gdscript
@rpc("any_peer", "reliable")
func create_room() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _room_code != "":
		_room_error.rpc_id(sender, "A game is already running. Try Join instead.")
		return
	_room_code = _gen_code()
	_members = [sender]
	_zombie_peer = 0
	_shooter_peers = []
	_match_started = false
	_match_over = false
	print("[server] room created: %s (host=%d)" % [_room_code, sender])
	_room_joined.rpc_id(sender, _room_code)
	_broadcast_lobby()


@rpc("any_peer", "reliable")
func join_room(code: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var c := code.strip_edges().to_upper()
	if _room_code == "":
		_room_error.rpc_id(sender, "No game is being hosted. Click Host to start one.")
		return
	if c != _room_code:
		_room_error.rpc_id(sender, "No game found with code %s." % c)
		return
	if sender not in _members and _members.size() >= MAX_MEMBERS:
		_room_error.rpc_id(sender, "That game is full.")
		return
	if sender not in _members:
		_members.append(sender)
	print("[server] peer %d joined room %s (%d/%d)" % [sender, _room_code, _members.size(), MAX_MEMBERS])
	_room_joined.rpc_id(sender, _room_code)
	_broadcast_lobby()


@rpc("any_peer", "reliable")
func claim_role(role: int) -> void:
	if not multiplayer.is_server() or _match_started or _match_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in _members:
		return
	var state := LobbyModel.claim(_lobby_state(), sender, role, MAX_SHOOTERS)
	_apply_lobby_state(state)
	_broadcast_lobby()


func _lobby_state() -> Dictionary:
	return { "zombie": _zombie_peer, "shooters": _shooter_peers.duplicate() }


func _apply_lobby_state(state: Dictionary) -> void:
	_zombie_peer = state["zombie"]
	var arr: Array[int] = []
	for p in state["shooters"]:
		arr.append(int(p))
	_shooter_peers = arr


func _broadcast_lobby() -> void:
	var host := _members[0] if not _members.is_empty() else 0
	for m in _members:
		_update_lobby.rpc_id(m, _zombie_peer, _shooter_peers, host)
```

- [ ] **Step 3: Add the host-only start RPC**

Add near `rematch`:

```gdscript
## Client -> server: the host starts the match. Requires a zombie + ≥1 shooter.
@rpc("any_peer", "reliable")
func start_match() -> void:
	if not multiplayer.is_server() or _match_started or _match_over:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _members.is_empty() or sender != _members[0]:
		return  # only the host may start
	if not LobbyModel.can_start(_lobby_state()):
		return
	_start_match()
```

- [ ] **Step 4: Update `_start_match` to assign every player**

Replace `_start_match`:

```gdscript
func _start_match() -> void:
	_match_started = true
	_match_over = false
	GameState.world_seed = randi()
	GameState.multiplayer_active = true
	GameState.shooter_peers = _shooter_peers.duplicate()
	print("[server] starting match (zombie=%d shooters=%s seed=%d)" % [_zombie_peer, str(_shooter_peers), GameState.world_seed])
	_assign_role_and_start.rpc_id(_zombie_peer, GameState.Role.ZOMBIE, GameState.world_seed, _shooter_peers)
	for sp in _shooter_peers:
		_assign_role_and_start.rpc_id(sp, GameState.Role.HUMAN, GameState.world_seed, _shooter_peers)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
```

- [ ] **Step 5: Update the client-side assign RPC to carry the shooter list**

Replace `_assign_role_and_start`:

```gdscript
@rpc("authority", "reliable")
func _assign_role_and_start(role: int, world_seed: int, shooter_peers: Array) -> void:
	GameState.role = role
	GameState.world_seed = world_seed
	GameState.multiplayer_active = true
	var arr: Array[int] = []
	for p in shooter_peers:
		arr.append(int(p))
	GameState.shooter_peers = arr
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
```

- [ ] **Step 6: Update the client lobby-receive RPC and disconnect/rematch/leave**

Replace `_update_lobby`:

```gdscript
@rpc("authority", "reliable")
func _update_lobby(zombie_peer: int, shooter_peers: Array, host_peer: int) -> void:
	lobby_updated.emit(zombie_peer, shooter_peers, host_peer)
```

Update `_handle_member_left` to use the new state (a shooter leaving frees its slot; zombie/host leaving during lobby closes as before; any departure mid-match closes the room — the world handles the "counts as dead" case in Task 9 for graceful in-match drops, this path is the hard-disconnect fallback):

```gdscript
func _handle_member_left(id: int) -> void:
	if id not in _members:
		return
	var was_host := _members[0] == id
	_members.erase(id)
	_apply_lobby_state(LobbyModel.remove(_lobby_state(), id))
	if _members.is_empty():
		_close_room()
		return
	if _match_started or _match_over or was_host or id == _zombie_peer:
		var remaining := _members.duplicate()
		_close_room()
		for m in remaining:
			_room_closed.rpc_id(m, "The game ended (a required player left).")
	else:
		_broadcast_lobby()
```

Update `rematch` guard (needs zombie + shooters instead of both single roles):

```gdscript
@rpc("any_peer", "reliable")
func rematch() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in _members:
		return
	if _match_started:
		return
	if not LobbyModel.can_start(_lobby_state()):
		return
	_start_match()
```

Update `_close_room` and `leave` to reset the new vars — replace every `_human_peer = 0` / `_zombie_peer = 0` pair with:

```gdscript
	_zombie_peer = 0
	_shooter_peers = []
```

- [ ] **Step 7: Add the client `request_start` wrapper**

Add near `request_rematch`:

```gdscript
## Client -> server: host starts the match.
func request_start() -> void:
	start_match.rpc_id(1)
```

- [ ] **Step 8: Verify clean boot**

Via MCP (editor open): `project_run` + `logs_read source=all`. Expected: zero `SCRIPT ERROR`. (Main menu still loads; lobby UI is fixed in Task 4.)

- [ ] **Step 9: Commit (only if Mads asks)**

```bash
git add scripts/network.gd
git commit -m "feat(mp): lobby supports 1 zombie + up to 4 shooters, host-start"
```

---

## Task 4: Lobby UI (roster + Start button)

**Files:**
- Modify: `scenes/ui/main_menu.gd`

**Interfaces:**
- Consumes: `lobby_updated(zombie_peer, shooter_peers, host_peer)`, `Net.request_start()`.

Reuses existing nodes: `lobby_human_button` (relabel "Join as Shooter"), `lobby_zombie_button`, `start_button`, `lobby_status`.

- [ ] **Step 1: Wire the Start button and update the lobby signal handler**

In `_ready`, after the existing `lobby_zombie_button.pressed.connect(...)` line, add:

```gdscript
	start_button.pressed.connect(func(): Net.request_start())
```

Leave `start_button.visible = false` as the default; `_on_lobby_updated` will reveal it for the host.

- [ ] **Step 2: Replace `_on_lobby_updated` with the multi-shooter version**

Replace the whole function:

```gdscript
func _on_lobby_updated(zombie_peer: int, shooter_peers: Array, host_peer: int) -> void:
	var me := multiplayer.get_unique_id()
	# The shooter button represents claiming a shooter slot (many can hold it).
	var i_am_shooter := me in shooter_peers
	_style_shooter_button(lobby_human_button, shooter_peers.size(), i_am_shooter)
	_style_role_button(lobby_zombie_button, "ZOMBIE", zombie_peer, me)

	var can_start := zombie_peer != 0 and not shooter_peers.is_empty()
	var is_host := me == host_peer
	start_button.visible = is_host
	start_button.disabled = not can_start

	var zlabel := "zombie ✓" if zombie_peer != 0 else "no zombie"
	lobby_status.text = "Code %s  —  shooters %d/4, %s.%s" % [
		_room_code, shooter_peers.size(), zlabel,
		("  Host: press Start." if is_host and can_start else "  Waiting for host…" if not is_host else "")
	]
```

- [ ] **Step 3: Add the shooter-button styler**

Add next to `_style_role_button`:

```gdscript
## The shooter slot is shared (up to 4). Show count and whether you hold one.
func _style_shooter_button(btn: Button, count: int, mine: bool) -> void:
	if mine:
		btn.text = "SHOOTER  ✓ (you)  %d/4" % count
		btn.modulate = Color(0.5, 1.5, 0.5)
	else:
		btn.text = "Join as SHOOTER  %d/4" % count
		btn.modulate = Color.WHITE
	btn.disabled = (not mine) and count >= 4
```

- [ ] **Step 4: Verify in the live editor (multi-window playtest)**

Close nothing; via MCP `project_run` for the host, and launch joiners with the existing flags (see `network.gd` header): a second instance with `--autojoin --join=CODE --role=human`, a third `--role=zombie`. Confirm: the shooter count increments, the zombie slot fills, only the host sees Start, and Start is disabled until zombie + ≥1 shooter. Then verify boot logs are clean.

- [ ] **Step 5: Commit (only if Mads asks)**

```bash
git add scenes/ui/main_menu.gd
git commit -m "feat(mp): lobby UI shows shooter roster + host Start button"
```

---

## Task 5: ShooterSelect pure helper (TDD)

**Files:**
- Create: `scripts/shooter_select.gd`
- Test: `test/test_shooter_select.gd`

**Interfaces:**
- Produces (`class_name ShooterSelect`, RefCounted):
  - `ShooterSelect.nearest_alive_index(from: Vector2, candidates: Array) -> int` — candidate = `{ "pos": Vector2, "alive": bool }`; returns the index of the nearest alive candidate, or -1.

- [ ] **Step 1: Write the failing test**

Create `test/test_shooter_select.gd`:

```gdscript
extends SceneTree

func _init() -> void:
	var SS = load("res://scripts/shooter_select.gd")
	var fail := 0

	var cands := [
		{ "pos": Vector2(100, 0), "alive": true },
		{ "pos": Vector2(10, 0),  "alive": false },  # closest but dead
		{ "pos": Vector2(50, 0),  "alive": true },
	]
	var idx := SS.nearest_alive_index(Vector2.ZERO, cands)
	if idx != 2: push_error("expected nearest alive index 2, got %d" % idx); fail += 1

	# all dead -> -1
	if SS.nearest_alive_index(Vector2.ZERO, [{ "pos": Vector2(1, 1), "alive": false }]) != -1:
		push_error("all dead should be -1"); fail += 1

	# empty -> -1
	if SS.nearest_alive_index(Vector2.ZERO, []) != -1:
		push_error("empty should be -1"); fail += 1

	if fail == 0: print("test_shooter_select: OK")
	quit(fail)
```

- [ ] **Step 2: Run to verify it fails**

Editor closed. Run:

```bash
cd ~/Desktop/zombie-game && godot --headless --path . --script test/test_shooter_select.gd
```

Expected: `Parse Error` / non-zero — helper missing.

- [ ] **Step 3: Implement ShooterSelect**

Create `scripts/shooter_select.gd`:

```gdscript
extends RefCounted
class_name ShooterSelect

## Pure nearest-alive selection. candidate = { "pos": Vector2, "alive": bool }.
static func nearest_alive_index(from: Vector2, candidates: Array) -> int:
	var best_i := -1
	var best_d := INF
	for i in range(candidates.size()):
		var c: Dictionary = candidates[i]
		if not c.get("alive", false):
			continue
		var d: float = from.distance_to(c["pos"])
		if d < best_d:
			best_d = d
			best_i = i
	return best_i
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd ~/Desktop/zombie-game && godot --headless --path . --script test/test_shooter_select.gd
```

Expected: `test_shooter_select: OK`, exit 0.

- [ ] **Step 5: Commit (only if Mads asks)**

```bash
git add scripts/shooter_select.gd test/test_shooter_select.gd
git commit -m "feat(mp): ShooterSelect nearest-alive helper + unit tests"
```

---

## Task 6: Per-shooter authority + input (shooter.gd)

**Files:**
- Modify: `scenes/shooter/shooter.gd`

**Interfaces:**
- Consumes: each shooter node has `set_multiplayer_authority(peer_id)` set by the world (Task 7).
- Produces: `enter_spectator()` method (called by world in Task 9); input only sent by the owning client; server rejects spoofed input.

- [ ] **Step 1: Gate input send on authority instead of the role flag**

In `_process` (currently starts `if not controls_enabled or is_dead: return`), change the guard so only the owning client sends input:

```gdscript
func _process(_delta: float) -> void:
	if not is_multiplayer_authority() or not controls_enabled or is_dead:
		return
```

(The rest of `_process` — reading Input and `rpc_id(1, ...)` — is unchanged.)

- [ ] **Step 2: Validate the sender on the server**

In `_send_input`, replace the early guard so the server accepts input only from this shooter's owner:

```gdscript
@rpc("any_peer", "call_local", "unreliable_ordered")
func _send_input(dir: Vector2, aim_target: Vector2, shooting: bool, focus: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return  # ignore input aimed at a shooter this peer doesn't own
	_net_dir = dir.limit_length(1.0)
	_net_aim_target = aim_target
	_net_shooting = shooting
	_net_focus = focus
```

Apply the same sender check to `_action_select`, `_action_drop`, and `_action_interact` — add after their `if multiplayer.is_server():` line (wrap the body):

```gdscript
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
```

(For `call_local` self-calls on the host, `get_remote_sender_id()` returns the host's own id, which equals the authority for the host's own shooter — so host-as-shooter still works.)

- [ ] **Step 3: Add spectator entry**

Add a method (used by the world when this shooter dies on its owning client):

```gdscript
## Owning client only: stop driving this body and hand the view to a spectator cam.
func enter_spectator() -> void:
	controls_enabled = false
```

(Camera hand-off lives in world.gd Task 9; this just ensures no further input.)

- [ ] **Step 4: Verify clean boot**

Via MCP: `project_run` + `logs_read`. Expected: zero `SCRIPT ERROR`. Solo play still works (host is authority over the single shooter).

- [ ] **Step 5: Commit (only if Mads asks)**

```bash
git add scenes/shooter/shooter.gd
git commit -m "feat(mp): per-shooter authority + server-side input validation"
```

---

## Task 7: World spawns N shooters + per-client view (world.gd)

**Files:**
- Modify: `scenes/world/world.gd`

**Interfaces:**
- Consumes: `GameState.shooter_peers`, `Balance.SHOOTER.min_dist_from_zombie_px/min_dist_from_shooter_px`, `ShooterSelect`, `set_multiplayer_authority` (Task 6).
- Produces: `shooters: Array` (server), `nearest_shooter(pos) -> Node`, `local_shooter()` helper. `master_zombie_spawn_pos: Vector2`.

- [ ] **Step 1: Replace the single-shooter field and add helpers**

Near the existing `var shooter: CharacterBody2D = null`, replace with:

```gdscript
var shooter: CharacterBody2D = null           # this client's own shooter (owning peer)
var shooters: Array[Node] = []                 # server: all shooter nodes
var master_zombie_spawn_pos: Vector2 = Vector2.ZERO


## Server: nearest living shooter to a point, or null if all dead.
func nearest_shooter(from: Vector2) -> Node:
	var cands: Array = []
	for s in shooters:
		if is_instance_valid(s):
			cands.append({ "pos": s.global_position, "alive": not s.is_dead })
		else:
			cands.append({ "pos": Vector2.INF, "alive": false })
	var idx := ShooterSelect.nearest_alive_index(from, cands)
	return shooters[idx] if idx >= 0 else null
```

- [ ] **Step 2: Replace `_spawn_shooter()` with `_spawn_shooters()`**

Replace the function and its call site in `_ready` (`_spawn_shooter()` → `_spawn_shooters()`). Note ordering: the master zombie spawn sets `master_zombie_spawn_pos`, so shooters must spawn AFTER the master. Reorder `_ready`'s server block to: `_spawn_master_zombie()`, `_spawn_shooters()`, `_spawn_standard_zombies()`, `_spawn_npcs()`, `_spawn_loot_boxes()`.

```gdscript
func _spawn_shooters() -> void:
	shooters.clear()
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	var peers: Array[int] = GameState.shooter_peers.duplicate()
	# Solo / single-player fallback: no assigned peers -> one local shooter (id 1).
	if peers.is_empty():
		peers = [1]
	for peer in peers:
		var pos := _random_shooter_spawn(walkable)
		var s := shooter_scene.instantiate()
		s.global_position = pos
		s.name = "Shooter_%d" % peer
		s.set_multiplayer_authority(peer)
		entities.add_child(s, true)
		s.player_died.connect(_on_player_died.bind(s))
		shooters.append(s)
	# This client's own shooter (server-as-host or dedicated: authority == unique id).
	for s in shooters:
		if s.get_multiplayer_authority() == multiplayer.get_unique_id():
			shooter = s
			break


## Pick a random walkable tile clear of buildings, away from the zombie spawn and
## other shooters. Falls back to any walkable after enough attempts.
func _random_shooter_spawn(walkable: Array[String]) -> Vector2:
	var min_z: float = Balance.SHOOTER.min_dist_from_zombie_px
	var min_s: float = Balance.SHOOTER.min_dist_from_shooter_px
	var fallback := Vector2(300, 2700)
	var attempts := 0
	while attempts < 400:
		attempts += 1
		var relaxed := attempts > 300  # drop spacing constraints if the map is tight
		var candidate := Vector2i(randi_range(1, 45), randi_range(1, 45))
		var td: TileData = ground_layer.get_cell_tile_data(candidate)
		if td == null or not td.get_custom_data("tile_type") in walkable:
			continue
		if building_layer.get_cell_tile_data(candidate) != null:
			continue
		var world_pos: Vector2 = ground_layer.map_to_local(candidate)
		if not relaxed:
			if world_pos.distance_to(master_zombie_spawn_pos) < min_z:
				continue
			var clash := false
			for s in shooters:
				if is_instance_valid(s) and world_pos.distance_to(s.global_position) < min_s:
					clash = true
					break
			if clash:
				continue
		return world_pos
	return fallback
```

- [ ] **Step 3: Record the master zombie spawn position**

In `_spawn_master_zombie()`, after `master_zombie.global_position = spawn_pos`, add:

```gdscript
	master_zombie_spawn_pos = spawn_pos
```

- [ ] **Step 4: Fix references that assumed a single shooter at spawn**

- In `_spawn_master_zombie()` the line `master_zombie.set_target(shooter)` runs before shooters exist now — replace with a nearest-shooter target set at the end of `_spawn_shooters()`. Add to the end of `_spawn_shooters()`:

```gdscript
	if is_instance_valid(master_zombie) and not shooters.is_empty():
		master_zombie.set_target(shooters[0])
```

- In `_spawn_standard_zombies()` replace `z.set_target(shooter)` with:

```gdscript
		z.set_target(nearest_shooter(z.global_position))
```

- In `_spawn_npcs()` replace `npc.shooter = shooter` with the nearest shooter (NPCs re-bind to whichever shooter recruits them on contact anyway):

```gdscript
		npc.shooter = nearest_shooter(world_pos)
```

  and in the same function's min-distance check, replace the single-shooter clause `if shooter and world_pos.distance_to(shooter.global_position) < 320.0:` with:

```gdscript
		for s in shooters:
			if is_instance_valid(s) and world_pos.distance_to(s.global_position) < 320.0:
				too_close = true
				break
```

- [ ] **Step 5: Per-client view — identify and set up only the owned shooter**

In `_on_entity_spawned` (client path), the `if node.is_in_group("shooter"):` branch currently assigns any shooter to `shooter`. Restrict it to the client's own shooter:

```gdscript
	if node.is_in_group("shooter"):
		if node.get_multiplayer_authority() == multiplayer.get_unique_id():
			shooter = node
```

(The zombie client owns no shooter, so `shooter` stays null there — Task 8 makes `_apply_role`/fog tolerate that.)

- [ ] **Step 6: Update the dedicated-server no-view block**

In `_ready`, the dedicated-server branch does `shooter.controls_enabled = false`. With N shooters and no local player, replace with:

```gdscript
		if GameState.is_dedicated_server:
			for s in shooters:
				s.controls_enabled = false
			zc_node.deactivate()
```

- [ ] **Step 7: Verify clean boot + solo play**

Via MCP: `project_run` + `logs_read` (zero `SCRIPT ERROR`). Solo (single-player) should still spawn one shooter and play normally.

- [ ] **Step 8: Commit (only if Mads asks)**

```bash
git add scenes/world/world.gd
git commit -m "feat(mp): spawn one shooter per peer (random, clear of zombie); nearest-shooter targeting"
```

---

## Task 8: Per-role/per-client setup with N shooters (world.gd)

**Files:**
- Modify: `scenes/world/world.gd`

**Interfaces:**
- Consumes: `shooter` (this client's own, may be null for the zombie), `hud`, `_setup_fog`, `_apply_role`.

- [ ] **Step 1: Make host server setup use the owned shooter**

In `_ready`'s non-dedicated server branch (`hud.setup(shooter, master_zombie)` / `_setup_fog()` / `_apply_role()`), this now runs for the host who may be a shooter OR the zombie. Guard HUD/fog on having an owned shooter:

```gdscript
		else:
			if shooter != null:
				hud.setup(shooter, master_zombie)
			_setup_fog()
			_apply_role()
```

- [ ] **Step 2: Make the client-ready gate not require a shooter (zombie client owns none)**

In `_on_entity_spawned`, the readiness gate is `if not _client_ready and shooter != null:`. The zombie client never gets a `shooter`, so gate on role instead:

```gdscript
	var ready_now := (GameState.role == GameState.Role.ZOMBIE and master_zombie != null) \
		or (GameState.role == GameState.Role.HUMAN and shooter != null)
	if not _client_ready and ready_now:
		_client_ready = true
		if shooter != null:
			hud.setup(shooter, master_zombie)
		_setup_fog()
		_apply_role()
		print("[net] client ready - role=", GameState.role, " has_shooter=", shooter != null)
```

- [ ] **Step 3: Guard `_apply_role` and `_setup_fog` against a null shooter**

In `_apply_role`, the first line `var shooter_cam := shooter.get_node("Camera2D")` crashes for the zombie. Restructure:

```gdscript
func _apply_role() -> void:
	if GameState.role == GameState.Role.HUMAN:
		if shooter == null:
			return
		var shooter_cam: Camera2D = shooter.get_node("Camera2D")
		shooter.controls_enabled = true
		shooter_cam.enabled = true
		shooter_cam.make_current()
		zc_node.deactivate()
		aim_cursor.setup(shooter)
	else:
		# Zombie commander: no owned shooter; drive the RTS camera.
		hud.visible = false
		zc_node.activate()
		zc_camera.make_current()
		if is_instance_valid(master_zombie):
			zc_camera.global_position = master_zombie.global_position
		aim_cursor.teardown()
```

`_setup_fog` already returns early unless `GameState.role == HUMAN`; add a null guard at that point:

```gdscript
	if GameState.role != GameState.Role.HUMAN or shooter == null:
		return
```

- [ ] **Step 4: Verify — two-window playtest (host shooter + zombie join)**

Via MCP `project_run` (host) and a joiner window `--autojoin --join=CODE --role=zombie`, host claims shooter, host presses Start. Confirm both windows load the world, the shooter has camera+fog+HUD, the zombie has the RTS camera, and logs show zero `SCRIPT ERROR`.

- [ ] **Step 5: Commit (only if Mads asks)**

```bash
git add scenes/world/world.gd
git commit -m "feat(mp): per-client view setup tolerates N shooters + zombie-only client"
```

---

## Task 9: Death, spectate, and co-op win/lose (world.gd)

**Files:**
- Modify: `scenes/world/world.gd`

**Interfaces:**
- Consumes: `shooters`, `nearest_shooter`, `shooter.enter_spectator()` (Task 6), `_game_over` (existing).
- Produces: `_spectate_target: Node`; updated `_on_player_died(dead_shooter)`.

- [ ] **Step 1: `_on_player_died` handles per-shooter death + last-man rule**

Replace `_on_player_died` (now takes the dead shooter, bound at connect time in Task 7):

```gdscript
func _on_player_died(dead_shooter: Node) -> void:
	if not multiplayer.is_server():
		return
	# Tell the owning client to switch to spectator (its own shooter died).
	var owner_id := dead_shooter.get_multiplayer_authority()
	_enter_spectator.rpc_id(owner_id)
	# Last-man rule: zombie wins when no shooter is still alive.
	var any_alive := false
	for s in shooters:
		if is_instance_valid(s) and not s.is_dead:
			any_alive = true
			break
	if not any_alive:
		_game_over.rpc(false)  # false = a shooter/all-shooters died -> zombie wins
```

- [ ] **Step 2: Add the spectator RPC (owning client)**

Add:

```gdscript
var _spectate_target: Node = null

## Server -> the dead shooter's owner: enter spectator mode, follow a living ally.
@rpc("authority", "call_local", "reliable")
func _enter_spectator() -> void:
	if shooter != null:
		shooter.enter_spectator()
	_spectate_target = _pick_spectate_target()
	if _spectate_target != null and _spectate_target.has_node("Camera2D"):
		(_spectate_target.get_node("Camera2D") as Camera2D).make_current()
	_show_game_over("YOU DIED — spectating")


## Client-side: any living shooter node to watch.
func _pick_spectate_target() -> Node:
	for s in get_tree().get_nodes_in_group("shooter"):
		if is_instance_valid(s) and not s.is_dead and s != shooter:
			return s
	return null
```

Note: `_show_game_over` currently swaps in the game-over screen; for a spectator we want the message without ending the match. If `game_over_screen.show_message` blocks input/pauses, add a lightweight label instead. Verify behavior in Step 5 and, if it pauses, replace this line with a HUD toast (`hud` has message helpers used elsewhere) — keep the match running.

- [ ] **Step 3: Confirm the master-death win path broadcasts to all shooters**

`_on_master_zombie_died` already calls `_game_over.rpc(true)`; `_game_over` is `@rpc(... "call_local" ...)` so every peer (all shooters + zombie) receives it. The per-role message in `_game_over` already renders WIN for HUMAN and LOSE for ZOMBIE on `master_died == true`. No change needed — just confirm in playtest.

- [ ] **Step 4: Keep the spectator camera following living allies as they die**

If the watched ally later dies, re-pick. Add to `_enter_spectator`'s peers and also re-run when another death arrives: simplest — in `_enter_spectator`, if this client is already spectating (`shooter.is_dead`), just re-pick the target. The existing call already fires per death (each `_on_player_died` RPCs only the newly-dead owner), so also broadcast a target refresh:

Change `_on_player_died` Step 1 to additionally refresh spectators when anyone dies — after computing `any_alive` and before the game-over check, add:

```gdscript
	_refresh_spectators.rpc()
```

And add:

```gdscript
## Server -> all: dead shooters re-pick a living ally to follow.
@rpc("authority", "call_local", "reliable")
func _refresh_spectators() -> void:
	if shooter == null or not shooter.is_dead:
		return
	var t := _pick_spectate_target()
	if t != null and t.has_node("Camera2D"):
		(t.get_node("Camera2D") as Camera2D).make_current()
```

- [ ] **Step 5: Verify — 3-window playtest (2 shooters + zombie)**

Host + 2 joiners (`--role=human`, `--role=zombie`; a third `--role=human`). Start. Let the zombie kill one shooter: that player should switch to spectating a living ally and see "YOU DIED — spectating" while the match continues. Kill the last shooter: all see the zombie-win/shooter-lose result. Separately, kill the master zombie: shooters WIN, zombie LOSE. Logs: zero `SCRIPT ERROR`.

- [ ] **Step 6: Commit (only if Mads asks)**

```bash
git add scenes/world/world.gd
git commit -m "feat(mp): dead shooters spectate; zombie wins on wipe, shooters win on master death"
```

---

## Task 10: Friendly fire (bullet.gd)

**Files:**
- Modify: `scenes/bullet/bullet.gd`

**Interfaces:**
- Consumes: `shooter_ref` (the firer), `_damage_for_hit()`, world `spawn_hit_fx`.

- [ ] **Step 1: Damage other shooters, ignore the firer**

In `_on_body_entered`, replace the early `if body.is_in_group("shooter"): return` block with:

```gdscript
	if body.is_in_group("shooter"):
		# Never hit the firer (bullets spawn near its body); other shooters take
		# friendly-fire damage.
		if body == shooter_ref:
			return
		var w := get_tree().current_scene
		if body.has_method("take_damage"):
			body.take_damage(_damage_for_hit())
		if w.has_method("spawn_hit_fx"):
			w.spawn_hit_fx(FxPresets.RED_BLOOD, global_position, direction)
		queue_free()
		return
```

(Uses `FxPresets.RED_BLOOD` — the human/red blood preset. If that enum name differs, use the same preset the shooter's own `take_damage` blood trail uses; grep `FxPresets` in `scripts/fx_presets.gd` to confirm the red/human constant.)

- [ ] **Step 2: Verify — 2-shooter friendly-fire playtest**

Host + 1 shooter joiner. One shooter shoots the other: the target loses HP and shows red blood FX; shooting at one's own feet does nothing. Logs: zero `SCRIPT ERROR`.

- [ ] **Step 3: Commit (only if Mads asks)**

```bash
git add scenes/bullet/bullet.gd
git commit -m "feat(mp): friendly fire — bullets damage other shooters, not the firer"
```

---

## Task 11: Docs update

**Files:**
- Modify: `CHANGELOG.md`, `ARCHITECTURE.md`, `PROJECT.md`

- [ ] **Step 1: Update CHANGELOG.md**

Add an entry summarizing: online play now supports 1 zombie + up to 4 co-op shooters, host-controlled start, per-shooter authority, friendly fire, random shooter spawns, dead-shooter spectate, last-man/master-death win conditions.

- [ ] **Step 2: Update ARCHITECTURE.md**

In the multiplayer/`Net` and `world.gd` sections, replace "2 players (1 human + 1 zombie)" descriptions with the new model: `_zombie_peer` + `_shooter_peers[]`, host start, `shooters[]` + `nearest_shooter`, `LobbyModel`/`ShooterSelect` helpers, friendly fire, spectate.

- [ ] **Step 3: Update PROJECT.md**

Update the status/how-to-run notes for up-to-5-player matches and the host Start flow.

- [ ] **Step 4: Commit (only if Mads asks)**

```bash
git add CHANGELOG.md ARCHITECTURE.md PROJECT.md
git commit -m "docs: 5-player online (4 shooters + 1 zombie)"
```

---

## Self-review notes

- **Spec coverage:** lobby/host-start (T3/T4), zombie-required + 1–4 shooters + cap 5 (T2/T3), per-shooter authority (T6), random spawns clear of zombie (T7), nearest-shooter targeting (T5/T7), per-client view incl. zombie-only client (T8), spectate + last-man + master-death win (T9), friendly fire (T10), balance/state plumbing (T1), tests for pure helpers (T2/T5), docs (T11). All spec sections mapped.
- **Networked behavior** is verified by clean-boot + multi-window playtest, not headless unit tests (Godot RPC/authority can't be exercised headless) — matches CLAUDE.md conventions.
- **Type consistency:** `LobbyModel` state dict `{zombie:int, shooters:Array}` and role ints (0 HUMAN, 1 ZOMBIE) are used identically in T2/T3; `nearest_shooter`/`nearest_alive_index` candidate shape `{pos,alive}` consistent T5/T7; `enter_spectator()` defined T6, called T9; `lobby_updated(zombie_peer, shooter_peers, host_peer)` consistent T3/T4.
- **Open verification flag:** T9 Step 2 — confirm `_show_game_over` for a spectator doesn't pause/end the match; fall back to a HUD toast if it does.
