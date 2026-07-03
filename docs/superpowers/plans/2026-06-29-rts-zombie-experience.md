# RTS Zombie Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the zombie-controller side into an Age-of-Empires-style RTS: discrete attacks, stances, smarter auto-attack, health bars, a populating minimap, sound/combat feedback, and proper unit separation.

**Architecture:** Server-authoritative AI/combat (unchanged ownership model). Each zombie runs a small stance state machine (movement pattern × on-sight reaction). Pure decision logic lives in `extends RefCounted` helpers (headless-testable); scene behavior is verified in the live editor. The existing two-layer fog (`FogZombieController`) is reused — the minimap reads its `tile_states`. A single "noise event" broadcast on each shot drives both the minimap ripple and the world-view wobble + sound aggro.

**Tech Stack:** Godot 4.6.3, GDScript, GL Compatibility 2D. `NavigationAgent2D` RVO avoidance for separation. `MultiplayerSpawner` + `MultiplayerSynchronizer` (already in place) for replication.

## Global Constraints

- **Engine:** Godot 4.6.3. All tunables go in `scripts/balance.gd` — never hard-code gameplay numbers in scenes/scripts.
- **Authority:** AI, combat, targeting, stance evaluation run on the server only (`multiplayer.is_server()`); clients render replicated state.
- **Testing — headless limitation:** headless `test/` runners cannot resolve `class_name` globals that extend scene types. Keep pure logic in `extends RefCounted` static helpers and reference them in tests via `load("res://...")`, never the bare `class_name`. Scene/visual behavior is verified in the live editor (MCP `project_run` + `logs_read source=all`; zero `SCRIPT ERROR` = clean boot) plus an owner playtest.
- **NEVER** run headless `Godot --import` / `--script` while the live editor is open on this project (`.godot` cache-wipe risk). Run `test/` scripts only with the editor closed, or via MCP `test_run`.
- **Commits:** work on a branch `feat/rts-zombie-experience` (branch before the first commit; do not work on `main`). Commit at the end of each task. **No `Co-Authored-By` / Claude attribution in commit messages.**
- **Docs:** after each phase, add a CHANGELOG.md line; update ARCHITECTURE.md / PROJECT.md if structure or status changed.
- **Replication note:** `hp`, `position`, `rotation`, `visible`, `merge_progress` are already replicated on `zombie.tscn` and `master_zombie.tscn`. New synced fields must be added to the `SceneReplicationConfig` in those scenes.

---

## Phase A — Discrete combat

### Task 1: Combat math helper + balance fields

**Files:**
- Create: `scripts/combat_math.gd`
- Test: `test/test_combat_math.gd`
- Modify: `scripts/balance.gd` (add `damage_per_hit` / `attack_interval` to `ZOMBIE`, `FAST`, `FAT`, `MASTER`)

**Interfaces:**
- Produces: `CombatMath.can_attack(distance: float, contact_px: float, cooldown_remaining: float) -> bool`

- [ ] **Step 1: Write the failing test**

```gdscript
# test/test_combat_math.gd
extends SceneTree

func _init() -> void:
	var CombatMath = load("res://scripts/combat_math.gd")
	var failed := 0

	# In range, cooldown ready -> can attack
	if CombatMath.can_attack(30.0, 38.0, 0.0) != true:
		push_error("expected true for in-range, ready"); failed += 1
	# In range, cooldown not ready -> cannot
	if CombatMath.can_attack(30.0, 38.0, 0.4) != false:
		push_error("expected false for cooldown remaining"); failed += 1
	# Out of range, cooldown ready -> cannot
	if CombatMath.can_attack(50.0, 38.0, 0.0) != false:
		push_error("expected false for out of range"); failed += 1
	# Exactly at range boundary -> in range (<=)
	if CombatMath.can_attack(38.0, 38.0, 0.0) != true:
		push_error("expected true at boundary"); failed += 1

	if failed == 0:
		print("test_combat_math: PASS")
		quit(0)
	else:
		print("test_combat_math: FAIL (%d)" % failed)
		quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run (editor closed): `Godot --headless --path . --script test/test_combat_math.gd`
Expected: FAIL — `combat_math.gd` does not exist / parse error.

- [ ] **Step 3: Write the helper**

```gdscript
# scripts/combat_math.gd
extends RefCounted
class_name CombatMath

## Pure attack-gating math, shared by zombie.gd and master_zombie.gd.

static func can_attack(distance: float, contact_px: float, cooldown_remaining: float) -> bool:
	return distance <= contact_px and cooldown_remaining <= 0.0
```

- [ ] **Step 4: Add balance fields**

In `scripts/balance.gd`, extend each zombie variant dict with `damage_per_hit` and `attack_interval` (keep existing `contact_dps` for now):

```gdscript
const ZOMBIE := { speed = 85.0,  max_hp = 150, contact_dps = 12.0, vision = 2, contact_px = 38.0, scale = 1.0, damage_per_hit = 15, attack_interval = 1.0 }
const FAST   := { speed = 220.0, max_hp = 150, contact_dps = 18.0, vision = 2, contact_px = 38.0, scale = 1.0, damage_per_hit = 12, attack_interval = 0.7 }
const FAT    := { speed = 76.5,  max_hp = 750, contact_dps = 60.0, vision = 2, contact_px = 38.0, scale = 1.5, damage_per_hit = 45, attack_interval = 1.3 }
const MASTER := { speed = 60.0,  max_hp = 450, contact_dps = 12.0, vision = 3, contact_px = 48.0, scale = 1.8, damage_per_hit = 20, attack_interval = 1.2 }
```

- [ ] **Step 5: Run test to verify it passes**

Run (editor closed): `Godot --headless --path . --script test/test_combat_math.gd`
Expected: `test_combat_math: PASS`, exit 0.

- [ ] **Step 6: Commit**

```bash
git checkout -b feat/rts-zombie-experience   # only if not already on the branch
git add scripts/combat_math.gd test/test_combat_math.gd scripts/balance.gd
git commit -m "feat(combat): add CombatMath.can_attack helper + per-variant hit/interval balance"
```

---

### Task 2: Discrete attack on standard zombies

**Files:**
- Modify: `scenes/zombie/zombie.gd` (replace `_check_contact_damage`, add cooldown + `took_damage` signal)

**Interfaces:**
- Consumes: `CombatMath.can_attack`, `Balance.<variant>.damage_per_hit/attack_interval`
- Produces: signal `took_damage(zombie: Node2D, amount: int)` (used by Phase E health bars and Phase F under-attack pulse); var `_attack_cooldown: float`

- [ ] **Step 1: Add fields and signal**

In `zombie.gd`, add near the other vars:

```gdscript
var damage_per_hit: int
var attack_interval: float
var _attack_cooldown: float = 0.0

signal took_damage(zombie: Node2D, amount: int)
```

In `_ready()`, after the existing stat assignments (`contact_dps = stats.contact_dps`), add:

```gdscript
	damage_per_hit = stats.damage_per_hit
	attack_interval = stats.attack_interval
```

- [ ] **Step 2: Replace continuous drain with discrete hits**

Replace `_check_contact_damage(delta)` body with cooldown-gated hits, and tick the cooldown in `_physics_process`. New function:

```gdscript
func _check_contact_damage(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if target == null or not is_instance_valid(target):
		return
	var distance := global_position.distance_to(target.global_position)
	if CombatMath.can_attack(distance, _contact_px, _attack_cooldown):
		if target.has_method("take_damage"):
			target.take_damage(damage_per_hit)
		_attack_cooldown = attack_interval
		_lunge_toward(target.global_position)
```

Add a small lunge nudge (visual only, server-safe since it just sets position slightly; movement already replicated):

```gdscript
func _lunge_toward(point: Vector2) -> void:
	var dir := (point - global_position).normalized()
	var tween := create_tween()
	tween.tween_property(self, "position", position + dir * 6.0, 0.05)
	tween.tween_property(self, "position", position, 0.05)
```

- [ ] **Step 3: Ensure cooldown ticks even when idle**

`_check_contact_damage(delta)` is only called at the end of the movement branch today. Move its call so the cooldown always decrements: ensure `_check_contact_damage(delta)` is invoked every `_physics_process` frame (including the idle `return` path). Restructure the idle branch:

```gdscript
	if target != null and _target_in_range():
		nav_agent.target_position = target.global_position
	else:
		_check_contact_damage(delta)  # still tick cooldown / hit if touching
		return
```
and keep the existing `_check_contact_damage(delta)` call at the end of the moving path.

- [ ] **Step 4: Emit took_damage**

In `take_damage(amount)`, after `hp -= amount`, add:

```gdscript
	took_damage.emit(self, int(amount))
```

- [ ] **Step 5: Verify in editor**

With the live editor open, MCP `project_run`, then `logs_read source=all`.
Expected: clean boot, zero `SCRIPT ERROR`. Owner playtest: stand next to a zombie — shooter HP now drops in discrete chunks (~15 every second) instead of a smooth slide, and the zombie does a tiny lunge on each hit.

- [ ] **Step 6: Commit**

```bash
git add scenes/zombie/zombie.gd
git commit -m "feat(combat): zombies hit on a cooldown with discrete damage + lunge; took_damage signal"
```

---

### Task 3: Discrete attack on master zombie

**Files:**
- Modify: `scenes/zombie/master_zombie.gd`

**Interfaces:**
- Consumes: `CombatMath.can_attack`, `Balance.MASTER.damage_per_hit/attack_interval`
- Produces: signal `took_damage(zombie: Node2D, amount: int)` (mirror of Task 2)

- [ ] **Step 1: Mirror the zombie changes**

Add the same fields/signal to `master_zombie.gd`:

```gdscript
var damage_per_hit: int
var attack_interval: float
var _attack_cooldown: float = 0.0
signal took_damage(zombie: Node2D, amount: int)
```

In `_ready()` (after `_contact_px = Balance.MASTER.contact_px`):

```gdscript
	damage_per_hit = Balance.MASTER.damage_per_hit
	attack_interval = Balance.MASTER.attack_interval
```

Replace `_check_contact_damage(delta)`:

```gdscript
func _check_contact_damage(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if target == null or not is_instance_valid(target):
		return
	var distance := global_position.distance_to(target.global_position)
	if CombatMath.can_attack(distance, _contact_px, _attack_cooldown):
		if target.has_method("take_damage"):
			target.take_damage(damage_per_hit)
		_attack_cooldown = attack_interval
```

In the master's `take_damage`, emit `took_damage.emit(self, int(amount))` after the hp decrement.

- [ ] **Step 2: Verify in editor**

MCP `project_run` + `logs_read source=all` → clean boot. Owner playtest: master zombie also deals chunked damage.

- [ ] **Step 3: Commit + changelog**

```bash
git add scenes/zombie/master_zombie.gd CHANGELOG.md
git commit -m "feat(combat): master zombie discrete-hit attack; close Phase A"
```
Add a CHANGELOG.md line: `Phase A (RTS): zombies now hit on a cooldown for discrete damage instead of draining the shooter continuously.`

---

## Phase B — Unit separation

### Task 4: NavAgent avoidance on zombies and NPCs

**Files:**
- Modify: `scenes/zombie/zombie.gd`, `scenes/zombie/master_zombie.gd`, `scenes/npc/npc_human.gd`
- Modify: `scenes/zombie/zombie.tscn`, `scenes/zombie/master_zombie.tscn`, `scenes/npc/npc_human.tscn` (NavigationAgent2D avoidance flags)
- Modify: `scripts/balance.gd` (`SEPARATION` block)

**Interfaces:**
- Produces: each agent applies an RVO-corrected velocity via the `velocity_computed` signal.

- [ ] **Step 1: Add the balance block**

```gdscript
# --- Unit separation (RVO avoidance) ---------------------------------------
const SEPARATION := {
	agent_radius = 16.0,       # px, ~body radius; agents keep this much apart
	neighbor_distance = 80.0,  # px, how far an agent looks for neighbors
	max_neighbors = 10,
	time_horizon = 1.0,        # s, how far ahead RVO predicts collisions
}
```

- [ ] **Step 2: Enable avoidance on the scenes**

On each `NavigationAgent2D` (in `zombie.tscn`, `master_zombie.tscn`, `npc_human.tscn`) set:
`avoidance_enabled = true`, `radius = 16.0`, `neighbor_distance = 80.0`, `max_neighbors = 10`, `time_horizon_agents = 1.0`. (Use the editor/MCP `node_set_property`; values are overwritten from `Balance.SEPARATION` at runtime in Step 3 so the scene values are just sane defaults.)

- [ ] **Step 3: Route velocity through the avoidance callback (zombie.gd)**

In `zombie.gd` `_ready()` (server only), configure the agent from balance and connect the callback:

```gdscript
	var sep: Dictionary = Balance.SEPARATION
	nav_agent.avoidance_enabled = true
	nav_agent.radius = sep.agent_radius
	nav_agent.neighbor_distance = sep.neighbor_distance
	nav_agent.max_neighbors = sep.max_neighbors
	nav_agent.time_horizon_agents = sep.time_horizon
	nav_agent.velocity_computed.connect(_on_velocity_computed)
```

Change the movement code: instead of `velocity = direction * speed; move_and_slide()`, submit the desired velocity to the agent and move with the safe velocity:

```gdscript
	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	nav_agent.set_velocity(direction * speed)
	# move_and_slide() now happens in _on_velocity_computed
```

Add:

```gdscript
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()
	if velocity.length() > 0:
		rotation = velocity.angle()
```

(Remove the now-duplicated `rotation = velocity.angle()` from the old path.)

- [ ] **Step 4: Mirror on master_zombie.gd and npc_human.gd**

Apply the same `_ready()` avoidance config + `velocity_computed` → `move_and_slide()` pattern in `master_zombie.gd` and `npc_human.gd`. For the NPC, keep its existing follow/hide velocity calculation but route the final velocity through `set_velocity` / the callback instead of calling `move_and_slide()` directly.

- [ ] **Step 5: Verify in editor**

MCP `project_run` + `logs_read source=all` → clean boot, no avoidance/nav warnings. Owner playtest: right-click a large selection onto one point — zombies pack in densely **without overlapping sprites** and **without freezing**; NPCs no longer stack on each other or pass through zombies.

- [ ] **Step 6: Commit + changelog**

```bash
git add scenes/zombie/zombie.gd scenes/zombie/master_zombie.gd scenes/npc/npc_human.gd \
        scenes/zombie/zombie.tscn scenes/zombie/master_zombie.tscn scenes/npc/npc_human.tscn \
        scripts/balance.gd CHANGELOG.md
git commit -m "feat(units): RVO avoidance so zombies and NPCs no longer overlap or pass through; close Phase B"
```
CHANGELOG line: `Phase B (RTS): unit separation via NavigationAgent2D avoidance — zombies and NPCs flow around each other instead of stacking.`

---

## Phase C — Stance state machine + auto-attack targeting

### Task 5: Targeting helper

**Files:**
- Create: `scripts/targeting.gd`
- Test: `test/test_targeting.gd`

**Interfaces:**
- Produces: `Targeting.nearest_index(from: Vector2, candidates: Array, vision_px: float) -> int`
  where each candidate is `{ "pos": Vector2, "eligible": bool }`; returns the index of the nearest eligible candidate within `vision_px`, else `-1`.

- [ ] **Step 1: Write the failing test**

```gdscript
# test/test_targeting.gd
extends SceneTree

func _init() -> void:
	var T = load("res://scripts/targeting.gd")
	var failed := 0
	var from := Vector2.ZERO

	var cands := [
		{ "pos": Vector2(200, 0), "eligible": true },
		{ "pos": Vector2(50, 0),  "eligible": true },
		{ "pos": Vector2(10, 0),  "eligible": false },  # closest but ineligible
	]
	# Nearest eligible within 300 is index 1 (50px), not the ineligible 10px one.
	if T.nearest_index(from, cands, 300.0) != 1:
		push_error("expected index 1"); failed += 1
	# Vision too short to reach anyone eligible -> -1
	if T.nearest_index(from, cands, 30.0) != -1:
		push_error("expected -1 for short vision"); failed += 1
	# Empty list -> -1
	if T.nearest_index(from, [], 300.0) != -1:
		push_error("expected -1 for empty"); failed += 1

	if failed == 0:
		print("test_targeting: PASS"); quit(0)
	else:
		print("test_targeting: FAIL (%d)" % failed); quit(1)
```

- [ ] **Step 2: Run to verify it fails**

`Godot --headless --path . --script test/test_targeting.gd` → FAIL (no file).

- [ ] **Step 3: Write the helper**

```gdscript
# scripts/targeting.gd
extends RefCounted
class_name Targeting

## Returns the index of the nearest eligible candidate within vision_px, or -1.
## candidate = { "pos": Vector2, "eligible": bool }
static func nearest_index(from: Vector2, candidates: Array, vision_px: float) -> int:
	var best_i := -1
	var best_d := vision_px
	for i in range(candidates.size()):
		var c: Dictionary = candidates[i]
		if not c.get("eligible", false):
			continue
		var d: float = from.distance_to(c["pos"])
		if d <= best_d:
			best_d = d
			best_i = i
	return best_i
```

- [ ] **Step 4: Run to verify it passes**

`Godot --headless --path . --script test/test_targeting.gd` → `test_targeting: PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/targeting.gd test/test_targeting.gd
git commit -m "feat(ai): Targeting.nearest_index nearest-eligible-enemy helper"
```

---

### Task 6: Stance logic helper

**Files:**
- Create: `scripts/stance_logic.gd`
- Test: `test/test_stance_logic.gd`

**Interfaces:**
- Produces:
  - `StanceLogic.flip_leg(current_leg: int) -> int` (0↔1, for patrol A/B)
  - `StanceLogic.arrived(distance: float, arrive_px: float) -> bool`

- [ ] **Step 1: Write the failing test**

```gdscript
# test/test_stance_logic.gd
extends SceneTree

func _init() -> void:
	var S = load("res://scripts/stance_logic.gd")
	var failed := 0
	if S.flip_leg(0) != 1: push_error("0->1"); failed += 1
	if S.flip_leg(1) != 0: push_error("1->0"); failed += 1
	if S.arrived(5.0, 8.0) != true: push_error("arrived true"); failed += 1
	if S.arrived(20.0, 8.0) != false: push_error("arrived false"); failed += 1
	if failed == 0:
		print("test_stance_logic: PASS"); quit(0)
	else:
		print("test_stance_logic: FAIL (%d)" % failed); quit(1)
```

- [ ] **Step 2: Run to verify it fails**

`Godot --headless --path . --script test/test_stance_logic.gd` → FAIL.

- [ ] **Step 3: Write the helper**

```gdscript
# scripts/stance_logic.gd
extends RefCounted
class_name StanceLogic

static func flip_leg(current_leg: int) -> int:
	return 1 - current_leg

static func arrived(distance: float, arrive_px: float) -> bool:
	return distance <= arrive_px
```

- [ ] **Step 4: Run to verify it passes**

`Godot --headless --path . --script test/test_stance_logic.gd` → PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/stance_logic.gd test/test_stance_logic.gd
git commit -m "feat(ai): StanceLogic patrol-leg + arrival helpers"
```

---

### Task 7: Stance state machine in zombie.gd

**Files:**
- Modify: `scenes/zombie/zombie.gd`
- Modify: `scripts/balance.gd` (`STANCE` block)

**Interfaces:**
- Consumes: `Targeting.nearest_index`, `StanceLogic.flip_leg/arrived`
- Produces: enum `Stance { AGGRESSIVE, HOLD, PATROL_ATTACK, PATROL_FLEE, SKITTISH, FLEE_POINT }`; method `set_stance(stance: int, p1: Vector2, p2: Vector2) -> void`

- [ ] **Step 1: Add the balance block**

```gdscript
# --- Stances ----------------------------------------------------------------
const STANCE := {
	arrive_px = 8.0,          # how close counts as "reached the point"
	flee_safe_seconds = 2.0,  # PATROL_FLEE: seconds with no enemy seen before resuming patrol
}
```

- [ ] **Step 2: Add stance state to zombie.gd**

```gdscript
enum Stance { AGGRESSIVE, HOLD, PATROL_ATTACK, PATROL_FLEE, SKITTISH, FLEE_POINT }
var stance: int = Stance.AGGRESSIVE
var patrol_a: Vector2 = Vector2.ZERO
var patrol_b: Vector2 = Vector2.ZERO
var flee_point: Vector2 = Vector2.ZERO
var _patrol_leg: int = 0
var _no_enemy_timer: float = 0.0
```

Add the public setter (called via RPC in Task 8):

```gdscript
func set_stance(new_stance: int, p1: Vector2 = Vector2.ZERO, p2: Vector2 = Vector2.ZERO) -> void:
	stance = new_stance
	command_mode = false
	match new_stance:
		Stance.PATROL_ATTACK, Stance.PATROL_FLEE:
			patrol_a = p1
			patrol_b = p2
			_patrol_leg = 0
		Stance.FLEE_POINT, Stance.SKITTISH:
			flee_point = p1
```

- [ ] **Step 3: Add the enemy-scan helper**

```gdscript
## Server-side: nearest visible enemy (shooter or NPC), or null.
func _acquire_enemy() -> Node2D:
	var nodes: Array = []
	var cands: Array = []
	for grp in ["shooter", "npcs"]:
		for n in get_tree().get_nodes_in_group(grp):
			if n is Node2D and is_instance_valid(n):
				var eligible := true
				if "is_dead" in n and n.is_dead:
					eligible = false
				if n.is_in_group("npcs") and "state" in n and "State" in n and n.state == n.State.CONVERTING:
					eligible = false
				nodes.append(n)
				cands.append({ "pos": n.global_position, "eligible": eligible })
	var idx := Targeting.nearest_index(global_position, cands, vision_range * 64.0)
	return nodes[idx] if idx >= 0 else null
```

- [ ] **Step 4: Replace the movement branch with a stance evaluation**

Replace the body of `_physics_process` (the `command_mode` / `target` block) with a `match stance` dispatch that sets `nav_agent.target_position`, then falls through to the shared move + `_check_contact_damage`. Move/contact stays as in Tasks 2/4.

```gdscript
func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_check_contact_damage(delta)  # ticks cooldown; hits if already touching

	# One-shot right-click move overrides the stance until it arrives.
	if command_mode:
		nav_agent.target_position = command_target
		if nav_agent.is_navigation_finished():
			command_mode = false
		_move_along_path()
		return

	match stance:
		Stance.HOLD:
			return  # rooted; ignore fire, never chase
		Stance.AGGRESSIVE:
			var e := _acquire_enemy()
			if e: nav_agent.target_position = e.global_position
			else: return
		Stance.PATROL_ATTACK:
			var e := _acquire_enemy()
			if e:
				nav_agent.target_position = e.global_position
			else:
				_advance_patrol()
		Stance.PATROL_FLEE:
			var e := _acquire_enemy()
			if e:
				_no_enemy_timer = Balance.STANCE.flee_safe_seconds
				nav_agent.target_position = flee_point
			else:
				if _no_enemy_timer > 0.0:
					_no_enemy_timer -= delta
					nav_agent.target_position = flee_point
				else:
					_advance_patrol()
		Stance.SKITTISH:
			var e := _acquire_enemy()
			if e: nav_agent.target_position = flee_point
			else: return
		Stance.FLEE_POINT:
			nav_agent.target_position = flee_point

	_move_along_path()
```

Add `_advance_patrol` and refactor the shared movement into `_move_along_path`:

```gdscript
func _advance_patrol() -> void:
	var dest := patrol_a if _patrol_leg == 0 else patrol_b
	nav_agent.target_position = dest
	if StanceLogic.arrived(global_position.distance_to(dest), Balance.STANCE.arrive_px):
		_patrol_leg = StanceLogic.flip_leg(_patrol_leg)

func _move_along_path() -> void:
	if nav_agent.is_navigation_finished():
		nav_agent.set_velocity(Vector2.ZERO)
		return
	var next_point := nav_agent.get_next_path_position()
	var direction := (next_point - global_position).normalized()
	nav_agent.set_velocity(direction * speed)
```

(Keep `_on_velocity_computed` from Task 4. Remove the obsolete inline move code and the old `_target_in_range`-based branch; `target` is no longer the driver — `_acquire_enemy` is. The `_check_contact_damage` still uses `target`, so set `target = e` whenever an enemy is acquired in AGGRESSIVE / PATROL_ATTACK, and clear it otherwise so it only bites what it's chasing.)

Concretely, in AGGRESSIVE and PATROL_ATTACK set `target = e` (and `target = null` when `e == null`); in flee/hold/skittish set `target = null` so a fleeing zombie doesn't bite.

- [ ] **Step 5: Verify in editor**

MCP `project_run` + `logs_read source=all` → clean boot. Owner playtest with a temporary debug binding (or default-stance check): default Aggressive zombies chase the nearest of shooter/NPCs and convert NPCs on contact. (Other stances are exercised once the UI lands in Task 9 — for now confirm no regressions and Aggressive works.)

- [ ] **Step 6: Commit + changelog**

```bash
git add scenes/zombie/zombie.gd scripts/balance.gd CHANGELOG.md
git commit -m "feat(ai): per-zombie stance state machine + nearest-enemy auto-attack; close Phase C"
```
CHANGELOG line: `Phase C (RTS): zombie stance state machine (aggressive/hold/patrol-attack/patrol-flee/skittish/flee) with nearest-visible-enemy targeting.`

---

## Phase D — Stance toolbar UI

### Task 8: Stance command RPC

**Files:**
- Modify: `scenes/world/world.gd` (add `rpc_set_stance`)

**Interfaces:**
- Consumes: `zombie.set_stance(stance, p1, p2)` (Task 7)
- Produces: `World.rpc_set_stance(zombie_names: Array, stance: int, p1: Vector2, p2: Vector2)` — server-applied, mirrors `rpc_command_move`.

- [ ] **Step 1: Add the RPC**

In `world.gd`, next to `rpc_command_move`:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func rpc_set_stance(zombie_names: Array, stance: int, p1: Vector2, p2: Vector2) -> void:
	if not multiplayer.is_server():
		return
	for n in zombie_names:
		var z := entities.get_node_or_null(NodePath(String(n)))
		if z and z.has_method("set_stance"):
			z.set_stance(stance, p1, p2)
```

- [ ] **Step 2: Verify in editor**

MCP `project_run` + `logs_read` → clean boot (the RPC is exercised by Task 9).

- [ ] **Step 3: Commit**

```bash
git add scenes/world/world.gd
git commit -m "feat(ui): rpc_set_stance server command for zombie stances"
```

---

### Task 9: Stance toolbar + placement mode

**Files:**
- Modify: `scenes/world/world.tscn` (add a `StancePanel` VBox with 6 buttons under `ZombieControllerNode/ZCOverlay`, mirroring `MergePanel`)
- Modify: `scripts/zombie_controller.gd` (button wiring, placement state, send `rpc_set_stance`)

**Interfaces:**
- Consumes: `World.rpc_set_stance`, `zombie_controller.selected_zombies`
- Produces: placement state `_pending_stance: int`, `_pending_points: Array[Vector2]`

- [ ] **Step 1: Add the panel + buttons in world.tscn**

Under `ZombieControllerNode/ZCOverlay`, add `StancePanel` (VBoxContainer) with buttons: `AggressiveButton`, `HoldButton`, `PatrolAttackButton`, `PatrolFleeButton`, `SkittishButton`, `FleePointButton`. Position it opposite the MergePanel so they don't overlap. Export each from `ZombieController` (add `@export var stance_buttons` references or fetch by path in `_ready`).

- [ ] **Step 2: Wire buttons and placement state in zombie_controller.gd**

Add state and constants:

```gdscript
const Stance = preload("res://scenes/zombie/zombie.gd").Stance
var _pending_stance: int = -1
var _pending_points: Array[Vector2] = []
var _points_needed: int = 0
```

In `_ready()`, connect each button to a handler that begins placement (or applies immediately for Aggressive/Hold which need 0 points):

```gdscript
func _begin_stance(stance: int, points_needed: int) -> void:
	if selected_zombies.is_empty():
		return
	if points_needed == 0:
		_send_stance(stance, Vector2.ZERO, Vector2.ZERO)
		return
	_pending_stance = stance
	_points_needed = points_needed
	_pending_points.clear()
```

Handlers: Aggressive→`_begin_stance(Stance.AGGRESSIVE,0)`, Hold→`_begin_stance(Stance.HOLD,0)`, PatrolAttack→`_begin_stance(Stance.PATROL_ATTACK,2)`, PatrolFlee→`_begin_stance(Stance.PATROL_FLEE,2)`, Skittish→`_begin_stance(Stance.SKITTISH,1)`, FleePoint→`_begin_stance(Stance.FLEE_POINT,1)`.

- [ ] **Step 3: Capture placement clicks**

In `_input`, before the normal left-click selection logic, intercept clicks while placement is pending:

```gdscript
	if _pending_stance >= 0 and event is InputEventMouseButton \
		and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var wp := _screen_to_world(event.position)
		_pending_points.append(wp)
		if _pending_points.size() >= _points_needed:
			var p1: Vector2 = _pending_points[0]
			var p2: Vector2 = _pending_points[1] if _pending_points.size() > 1 else Vector2.ZERO
			_send_stance(_pending_stance, p1, p2)
			_pending_stance = -1
			_pending_points.clear()
		return  # consume click; don't select/deselect during placement
```

Add the sender:

```gdscript
func _send_stance(stance: int, p1: Vector2, p2: Vector2) -> void:
	var names: Array = []
	for z in selected_zombies:
		if is_instance_valid(z):
			names.append(String(z.name))
	if names.is_empty():
		return
	get_tree().current_scene.rpc_set_stance.rpc_id(1, names, stance, p1, p2)
```

Show the stance panel only when zombies are selected (extend `_update_merge_buttons` or add `_update_stance_buttons`).

- [ ] **Step 4: Verify in editor**

MCP `project_run` + `logs_read` → clean boot. Owner playtest: select zombies → click each stance button → for patrol, click 2 points and watch them loop; for skittish/flee, click 1 point; Hold roots them even under fire; Aggressive chases nearest enemy.

- [ ] **Step 5: Commit**

```bash
git add scenes/world/world.tscn scripts/zombie_controller.gd
git commit -m "feat(ui): stance toolbar with click-to-place patrol/flee points"
```

---

### Task 10: Patrol/flee preview + stance glyphs

**Files:**
- Modify: `scenes/world/selectrion_drawer.gd` (or add `scripts/stance_overlay.gd` sibling drawer)
- Modify: `scripts/zombie_controller.gd` (feed selected zombies' stance data to the drawer)

**Interfaces:**
- Consumes: `selected_zombies`, each zombie's `stance`/`patrol_a`/`patrol_b`/`flee_point`

- [ ] **Step 1: Draw patrol lines / flee markers**

Extend the overlay's `_draw` to iterate `selected_zombies` and, in world→screen space, draw:
- PATROL_ATTACK / PATROL_FLEE: a line `patrol_a`↔`patrol_b` plus small circles at each end.
- FLEE_POINT / SKITTISH: a marker at `flee_point`.

```gdscript
func _draw() -> void:
	# ... existing selection rect draw ...
	if controller == null: return
	var xform := get_viewport().get_canvas_transform()
	for z in controller.selected_zombies:
		if not is_instance_valid(z): continue
		match z.stance:
			z.Stance.PATROL_ATTACK, z.Stance.PATROL_FLEE:
				var a := xform * z.patrol_a
				var b := xform * z.patrol_b
				draw_line(a, b, Color(1, 1, 0, 0.5), 2.0)
				draw_circle(a, 5.0, Color.YELLOW)
				draw_circle(b, 5.0, Color.YELLOW)
			z.Stance.FLEE_POINT, z.Stance.SKITTISH:
				draw_circle(xform * z.flee_point, 6.0, Color(0.4, 0.7, 1.0, 0.7))
	queue_redraw()
```

(Wire a `controller` reference to the drawer in `world.gd`/`_ready` if not already present.)

- [ ] **Step 2: Stance glyph under selected zombies**

In `zombie.gd` `_draw()` (already used for the selection ring), when `is_selected`, draw a tiny colored dot/letter below the body indicating stance (e.g. color-coded per stance). Keep it cheap.

- [ ] **Step 3: Verify in editor**

Owner playtest: selecting a patrol unit shows its A↔B line; flee/skittish show the safe-point marker; a small stance glyph appears under selected zombies.

- [ ] **Step 4: Commit**

```bash
git add scenes/world/selectrion_drawer.gd scripts/zombie_controller.gd scenes/zombie/zombie.gd
git commit -m "feat(ui): patrol/flee path preview + per-zombie stance glyph"
```

---

### Task 11: Control groups (Ctrl+1–9)

**Files:**
- Modify: `scripts/zombie_controller.gd`

**Interfaces:**
- Produces: `_control_groups: Dictionary` (int → Array of zombie node names)

- [ ] **Step 1: Add save/recall**

```gdscript
var _control_groups: Dictionary = {}

func _save_group(num: int) -> void:
	var names: Array = []
	for z in selected_zombies:
		if is_instance_valid(z):
			names.append(String(z.name))
	_control_groups[num] = names

func _recall_group(num: int) -> void:
	if not _control_groups.has(num):
		return
	_deselect_all()
	for n in _control_groups[num]:
		var z := get_tree().current_scene.get_node_or_null(NodePath("Entities/" + String(n)))
		if z and z.is_in_group("zombies"):
			selected_zombies.append(z)
			if z.has_method("set_selected"):
				z.set_selected(true)
```

- [ ] **Step 2: Bind keys in _input**

```gdscript
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var num := event.keycode - KEY_0
			if event.ctrl_pressed:
				_save_group(num)
			else:
				_recall_group(num)
			return
```

- [ ] **Step 3: Verify in editor**

Owner playtest: select units, Ctrl+1 to save, click empty ground to deselect, press 1 to recall the same group.

- [ ] **Step 4: Commit + changelog**

```bash
git add scripts/zombie_controller.gd CHANGELOG.md
git commit -m "feat(ui): RTS control groups (Ctrl+1-9); close Phase D"
```
CHANGELOG line: `Phase D (RTS): stance toolbar, patrol/flee placement & preview, stance glyphs, control groups.`

---

## Phase E — Zombie health bars

### Task 12: Reusable health bar above units

**Files:**
- Create: `scripts/health_bar.gd`
- Modify: `scenes/zombie/zombie.gd`, `scenes/zombie/master_zombie.gd` (attach + show/hide)

**Interfaces:**
- Consumes: replicated `hp` / `max_hp`, `is_selected`, signal `took_damage`
- Produces: `HealthBar` Node2D with `set_fraction(f: float)` and `visible` toggling

- [ ] **Step 1: Write the health bar component**

```gdscript
# scripts/health_bar.gd
extends Node2D
class_name HealthBar

const WIDTH := 26.0
const HEIGHT := 4.0
var fraction: float = 1.0

func set_fraction(f: float) -> void:
	fraction = clampf(f, 0.0, 1.0)
	queue_redraw()

func _process(_delta: float) -> void:
	# Stay upright even though the parent rotates to face travel.
	global_rotation = 0.0

func _draw() -> void:
	var origin := Vector2(-WIDTH * 0.5, 0.0)
	draw_rect(Rect2(origin, Vector2(WIDTH, HEIGHT)), Color(0, 0, 0, 0.6))
	var col := Color(0.2, 0.9, 0.2).lerp(Color(0.9, 0.2, 0.2), 1.0 - fraction)
	draw_rect(Rect2(origin, Vector2(WIDTH * fraction, HEIGHT)), col)
```

- [ ] **Step 2: Attach + drive it from zombie.gd**

In `_ready()`:

```gdscript
	_health_bar = HealthBar.new()
	_health_bar.position = Vector2(0, -28)
	_health_bar.z_index = 20
	add_child(_health_bar)
	_health_bar.visible = false
```

Add `var _health_bar: HealthBar`. Update visibility/fill on damage, heal, and selection. In `take_damage` (after emitting `took_damage`) and in `set_selected`, call:

```gdscript
func _refresh_health_bar() -> void:
	if _health_bar == null: return
	var frac := float(hp) / float(max_hp)
	_health_bar.set_fraction(frac)
	_health_bar.visible = is_selected or frac < 1.0
```

Call `_refresh_health_bar()` from `take_damage`, `set_selected`, and once at end of `_ready`. For clients (where `take_damage` doesn't run), also refresh when the replicated `hp` changes — add a light check in `_process`:

```gdscript
	if _health_bar and hp != _last_hp_seen:
		_last_hp_seen = hp
		_refresh_health_bar()
```
with `var _last_hp_seen: int = -1`.

- [ ] **Step 3: Mirror on master_zombie.gd**

Same attach + `_refresh_health_bar` + `_process` hp-watch in `master_zombie.gd` (position the bar a bit higher to clear its larger sprite, e.g. `Vector2(0, -42)`).

- [ ] **Step 4: Verify in editor**

MCP `project_run` + `logs_read` → clean boot. Owner playtest (and a 2-window local MP run via `./run_local_mp.command`): a zombie that takes a bullet shows a depleting bar above it on **both** the shooter and zombie views; full-HP unselected zombies show no bar; selecting a full-HP zombie shows its (full) bar; bars stay horizontal as zombies rotate.

- [ ] **Step 5: Commit + changelog**

```bash
git add scripts/health_bar.gd scenes/zombie/zombie.gd scenes/zombie/master_zombie.gd CHANGELOG.md
git commit -m "feat(ui): per-zombie health bars (shown when damaged or selected); close Phase E"
```
CHANGELOG line: `Phase E (RTS): per-zombie health bars above units, visible when damaged or selected, replicated to both views.`

---

## Phase F — Minimap

### Task 13: Minimap coordinate math

**Files:**
- Create: `scripts/minimap_math.gd`
- Test: `test/test_minimap_math.gd`

**Interfaces:**
- Produces:
  - `MinimapMath.world_to_minimap(world: Vector2, world_px: float, minimap_size: float) -> Vector2`
  - `MinimapMath.minimap_to_world(local: Vector2, world_px: float, minimap_size: float) -> Vector2`
  - `MinimapMath.fuzz(pos: Vector2, jitter_px: float, rng: RandomNumberGenerator) -> Vector2`

- [ ] **Step 1: Write the failing test**

```gdscript
# test/test_minimap_math.gd
extends SceneTree

func _init() -> void:
	var M = load("res://scripts/minimap_math.gd")
	var failed := 0
	# Center of a 3008px world maps to center of a 200px minimap.
	var c := M.world_to_minimap(Vector2(1504, 1504), 3008.0, 200.0)
	if not c.is_equal_approx(Vector2(100, 100)):
		push_error("center map wrong: %s" % c); failed += 1
	# Round-trip: world -> minimap -> world is identity.
	var w := Vector2(800, 2200)
	var back := M.minimap_to_world(M.world_to_minimap(w, 3008.0, 200.0), 3008.0, 200.0)
	if not back.is_equal_approx(w):
		push_error("round trip wrong: %s" % back); failed += 1
	# Fuzz stays within jitter radius.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var f := M.fuzz(Vector2(500, 500), 40.0, rng)
	if f.distance_to(Vector2(500, 500)) > 40.0:
		push_error("fuzz out of range"); failed += 1
	if failed == 0:
		print("test_minimap_math: PASS"); quit(0)
	else:
		print("test_minimap_math: FAIL (%d)" % failed); quit(1)
```

- [ ] **Step 2: Run to verify it fails**

`Godot --headless --path . --script test/test_minimap_math.gd` → FAIL.

- [ ] **Step 3: Write the helper**

```gdscript
# scripts/minimap_math.gd
extends RefCounted
class_name MinimapMath

static func world_to_minimap(world: Vector2, world_px: float, minimap_size: float) -> Vector2:
	return (world / world_px) * minimap_size

static func minimap_to_world(local: Vector2, world_px: float, minimap_size: float) -> Vector2:
	return (local / minimap_size) * world_px

static func fuzz(pos: Vector2, jitter_px: float, rng: RandomNumberGenerator) -> Vector2:
	var ang := rng.randf() * TAU
	var dist := sqrt(rng.randf()) * jitter_px
	return pos + Vector2.from_angle(ang) * dist
```

- [ ] **Step 4: Run to verify it passes**

`Godot --headless --path . --script test/test_minimap_math.gd` → PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/minimap_math.gd test/test_minimap_math.gd
git commit -m "feat(minimap): coordinate-mapping + fuzz helpers"
```

---

### Task 14: Minimap control — terrain, blips, click-to-jump

**Files:**
- Create: `scripts/minimap.gd`
- Modify: `scenes/world/world.tscn` (add `Minimap` Control in `ZombieControllerNode/ZCOverlay`, a screen corner)
- Modify: `scripts/balance.gd` (`MINIMAP` block)
- Modify: `scripts/zombie_controller.gd` (give the minimap a ref to `fog_zc`, `camera`)

**Interfaces:**
- Consumes: `fog_zc.tile_states`, `FogZombieController` state constants, `MinimapMath`, entity groups, `zc_camera`
- Produces: `Minimap` Control drawing terrain + blips; click moves `zc_camera`

- [ ] **Step 1: Add the balance block**

```gdscript
# --- Minimap ----------------------------------------------------------------
const MINIMAP := {
	size_px = 200.0,            # on-screen square size
	world_px = 3008.0,          # world extent the minimap covers
	margin_px = 12.0,           # inset from the screen corner
	zombie_blip = 2.5,
	enemy_blip = 3.0,
	ghost_fade = 4.0,           # s, last-known blip fade
	under_attack_seconds = 1.5, # s, red pulse duration
	gunshot_jitter_px = 90.0,   # "general area" fuzz for the shot ripple
	ripple_seconds = 1.2,
}
```

- [ ] **Step 2: Add the Minimap control to world.tscn**

Add a `Control` named `Minimap` under `ZombieControllerNode/ZCOverlay`, anchored to a corner (e.g. bottom-right), size `200×200`, attach `scripts/minimap.gd`. The overlay is already hidden for the HUMAN role via `ZCOverlay.visible` toggling, so the minimap shows only on the zombie view.

- [ ] **Step 3: Write minimap.gd — terrain + own/enemy blips**

```gdscript
# scripts/minimap.gd
extends Control

var fog_zc: FogZombieController
var camera: Camera2D
var ground_layer: TileMapLayer

func setup(p_fog: FogZombieController, p_cam: Camera2D) -> void:
	fog_zc = p_fog
	camera = p_cam

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var s: float = Balance.MINIMAP.size_px
	var wpx: float = Balance.MINIMAP.world_px
	# Terrain from fog tile_states
	if fog_zc:
		var gw: int = fog_zc.GRID_W
		var gh: int = fog_zc.GRID_H
		var cw := s / gw
		var ch := s / gh
		for x in range(gw):
			for y in range(gh):
				var st: int = fog_zc.tile_states[y * gw + x]
				var col: Color
				match st:
					FogZombieController.STATE_UNEXPLORED: col = Color(0, 0, 0, 1)
					FogZombieController.STATE_EXPLORED:   col = Color(0.18, 0.18, 0.2, 1)
					_:                                    col = Color(0.32, 0.34, 0.38, 1)
				draw_rect(Rect2(Vector2(x * cw, y * ch), Vector2(cw + 1, ch + 1)), col)
	# Own zombies (always)
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D:
			draw_circle(MinimapMath.world_to_minimap(z.global_position, wpx, s),
				Balance.MINIMAP.zombie_blip, Color(0.6, 0.1, 0.1))
	# Enemies only where currently visible
	for grp in ["shooter", "npcs"]:
		for e in get_tree().get_nodes_in_group(grp):
			if e is Node2D and _tile_visible(e.global_position):
				draw_circle(MinimapMath.world_to_minimap(e.global_position, wpx, s),
					Balance.MINIMAP.enemy_blip, Color(1, 1, 0.2))

func _tile_visible(world: Vector2) -> bool:
	if fog_zc == null or ground_layer == null:
		return true
	var t: Vector2i = ground_layer.local_to_map(ground_layer.to_local(world))
	if t.x < 0 or t.y < 0 or t.x >= fog_zc.GRID_W or t.y >= fog_zc.GRID_H:
		return false
	return fog_zc.tile_states[t.y * fog_zc.GRID_W + t.x] == FogZombieController.STATE_VISIBLE

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_jump_camera(event.position)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_jump_camera(event.position)

func _jump_camera(local_pos: Vector2) -> void:
	if camera == null: return
	var world := MinimapMath.minimap_to_world(local_pos, Balance.MINIMAP.world_px, Balance.MINIMAP.size_px)
	camera.global_position = world.clamp(Vector2.ZERO, Vector2(Balance.MINIMAP.world_px, Balance.MINIMAP.world_px))
```

- [ ] **Step 4: Wire it up in zombie_controller.gd**

After `fog_zc` is created in `_ready()`, find the minimap and call `setup`:

```gdscript
	var minimap := get_node_or_null("ZCOverlay/Minimap")
	if minimap:
		minimap.setup(fog_zc, camera)
		minimap.ground_layer = ground_layer
```

- [ ] **Step 5: Verify in editor**

MCP `project_run` + `logs_read` → clean boot. Owner playtest (zombie role): the minimap starts black; as zombies move, terrain fills in (dim where explored, brighter where currently watched); own zombies always blip; the shooter/NPC blips appear only while a zombie watches that tile; clicking/dragging the minimap recenters the camera.

- [ ] **Step 6: Commit**

```bash
git add scripts/minimap.gd scenes/world/world.tscn scripts/balance.gd scripts/zombie_controller.gd
git commit -m "feat(minimap): explored terrain, own/enemy blips, click-to-jump camera"
```

---

### Task 15: Ghost blips + under-attack pulse

**Files:**
- Modify: `scripts/minimap.gd`
- Modify: `scripts/zombie_controller.gd` (connect zombies' `took_damage` to the minimap)

**Interfaces:**
- Consumes: zombie `took_damage(zombie, amount)` signal
- Produces: minimap `register_attack(world_pos: Vector2)`; internal ghost tracking

- [ ] **Step 1: Last-known ghost blips**

In `minimap.gd`, track the last-seen position + timestamp per enemy and draw a fading grey blip after it leaves vision. Add:

```gdscript
var _ghosts: Dictionary = {}  # instance_id -> { pos: Vector2, t: float }

# in _draw, in the enemy loop:
#   when visible: update _ghosts[e.get_instance_id()] = { pos = e.global_position, t = now }
#   draw the live yellow blip
# after the loop, draw ghosts whose age < ghost_fade and whose owner is NOT currently visible
```

Concretely, replace the enemy loop with logic that updates `_ghosts` when visible, then a second pass that draws ghosts:

```gdscript
	var now := Time.get_ticks_msec() / 1000.0
	for grp in ["shooter", "npcs"]:
		for e in get_tree().get_nodes_in_group(grp):
			if e is Node2D and _tile_visible(e.global_position):
				_ghosts[e.get_instance_id()] = { "pos": e.global_position, "t": now }
				draw_circle(MinimapMath.world_to_minimap(e.global_position, wpx, s),
					Balance.MINIMAP.enemy_blip, Color(1, 1, 0.2))
	for id in _ghosts.keys():
		var g: Dictionary = _ghosts[id]
		var age: float = now - g["t"]
		if age <= 0.05:
			continue  # freshly-seen this frame, already drawn live
		if age > Balance.MINIMAP.ghost_fade:
			_ghosts.erase(id)
			continue
		var a := 1.0 - age / Balance.MINIMAP.ghost_fade
		draw_circle(MinimapMath.world_to_minimap(g["pos"], wpx, s),
			Balance.MINIMAP.enemy_blip, Color(0.7, 0.7, 0.7, a * 0.8))
```

- [ ] **Step 2: Under-attack pulse**

Add to `minimap.gd`:

```gdscript
var _attacks: Array = []  # [{ pos: Vector2, t: float }]

func register_attack(world_pos: Vector2) -> void:
	_attacks.append({ "pos": world_pos, "t": Time.get_ticks_msec() / 1000.0 })

# in _draw, after blips:
	var n2 := Time.get_ticks_msec() / 1000.0
	for i in range(_attacks.size() - 1, -1, -1):
		var age: float = n2 - _attacks[i]["t"]
		if age > Balance.MINIMAP.under_attack_seconds:
			_attacks.remove_at(i); continue
		var pulse := 0.5 + 0.5 * sin(age * 18.0)
		draw_circle(MinimapMath.world_to_minimap(_attacks[i]["pos"], wpx, s),
			Balance.MINIMAP.enemy_blip + 2.0, Color(1, 0.1, 0.1, pulse))
```

- [ ] **Step 3: Connect took_damage to the minimap**

A zombie taking damage should pulse the map. In `zombie_controller.gd`, connect every zombie's `took_damage` to `minimap.register_attack`. Since zombies spawn via the MultiplayerSpawner, hook newly-spawned ones. Simplest robust approach: in `minimap.gd` `_process`, lazily connect any zombie in group `zombies` not yet connected:

```gdscript
var _attack_connected: Dictionary = {}
func _connect_new_zombies() -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		var id := z.get_instance_id()
		if not _attack_connected.has(id) and z.has_signal("took_damage"):
			z.took_damage.connect(func(_zb, _amt): register_attack(z.global_position))
			_attack_connected[id] = true
```
Call `_connect_new_zombies()` at the top of `_process`.

- [ ] **Step 4: Verify in editor**

Owner playtest: shoot a zombie → red pulse on the minimap at its location (AoE under-attack cue). Watch an enemy then break line of sight → its blip turns into a fading grey ghost where last seen.

- [ ] **Step 5: Commit**

```bash
git add scripts/minimap.gd scripts/zombie_controller.gd
git commit -m "feat(minimap): last-known ghost blips + under-attack red pulse"
```

---

### Task 16: Noise event infra + minimap gunshot ripple

**Files:**
- Modify: `scenes/shooter/shooter.gd` (broadcast a noise event on each shot)
- Modify: `scenes/world/world.gd` (`rpc_noise_event` fan-out + a `noise_event` signal)
- Modify: `scripts/minimap.gd` (draw the gunshot ripple)
- Modify: `scripts/zombie_controller.gd` (subscribe minimap to noise events)

**Interfaces:**
- Produces: `World.rpc_noise_event(world_pos: Vector2, strength: float)` and `signal noise_event(world_pos: Vector2, strength: float)`; minimap `register_noise(world_pos: Vector2)`

- [ ] **Step 1: Broadcast a noise event when the shooter fires**

In `shooter.gd` `shoot()`, after `Weapons.fire(...)` (server-side path), add:

```gdscript
	var w_scene := get_tree().current_scene
	if w_scene.has_method("emit_noise"):
		w_scene.emit_noise(gun_tip.global_position, 1.0)
```

- [ ] **Step 2: Fan out from world.gd**

```gdscript
signal noise_event(world_pos: Vector2, strength: float)

func emit_noise(world_pos: Vector2, strength: float) -> void:
	if multiplayer.is_server():
		rpc_noise_event.rpc(world_pos, strength)

@rpc("authority", "call_local", "reliable")
func rpc_noise_event(world_pos: Vector2, strength: float) -> void:
	noise_event.emit(world_pos, strength)
```

- [ ] **Step 3: Minimap ripple at a fuzzed position**

In `minimap.gd`:

```gdscript
var _rng := RandomNumberGenerator.new()
var _ripples: Array = []  # [{ pos: Vector2, t: float }]

func register_noise(world_pos: Vector2) -> void:
	_ripples.append({ "pos": MinimapMath.fuzz(world_pos, Balance.MINIMAP.gunshot_jitter_px, _rng),
		"t": Time.get_ticks_msec() / 1000.0 })

# in _draw, last:
	var n3 := Time.get_ticks_msec() / 1000.0
	for i in range(_ripples.size() - 1, -1, -1):
		var age: float = n3 - _ripples[i]["t"]
		if age > Balance.MINIMAP.ripple_seconds:
			_ripples.remove_at(i); continue
		var frac := age / Balance.MINIMAP.ripple_seconds
		var center := MinimapMath.world_to_minimap(_ripples[i]["pos"], wpx, s)
		draw_arc(center, 3.0 + frac * 16.0, 0.0, TAU, 20, Color(1, 1, 1, (1.0 - frac) * 0.4), 1.5)
```

- [ ] **Step 4: Subscribe the minimap to noise events**

In `zombie_controller.gd` `_ready()`, after wiring the minimap:

```gdscript
	get_tree().current_scene.noise_event.connect(func(pos, _str):
		if minimap: minimap.register_noise(pos))
```

- [ ] **Step 5: Verify in editor**

Local MP run: as the shooter fires, the zombie player sees a subtle expanding ring on the minimap at the *general* area of the shot (not pinpoint), fading out.

- [ ] **Step 6: Commit + changelog**

```bash
git add scenes/shooter/shooter.gd scenes/world/world.gd scripts/minimap.gd scripts/zombie_controller.gd CHANGELOG.md
git commit -m "feat(minimap): gunshot noise events + subtle map ripple; close Phase F"
```
CHANGELOG line: `Phase F (RTS): minimap (explored terrain, fog-aware enemy blips, ghost blips, under-attack pulse, gunshot ripple, click-to-jump).`

---

## Phase G — World-view gunshot feedback + sound aggro

### Task 17: World-view ripple near the camera

**Files:**
- Create: `scripts/noise_ripple.gd` (a self-removing world ripple Node2D)
- Modify: `scripts/zombie_controller.gd` (spawn a ripple when a noise event lands near the camera)
- Modify: `scripts/balance.gd` (`AGGRO` block)

**Interfaces:**
- Consumes: `World.noise_event`
- Produces: a brief world-space ripple at the (fuzzed) shot source when `zc_camera` is within range

- [ ] **Step 1: Add the balance block**

```gdscript
# --- Sound aggro + world feedback ------------------------------------------
const AGGRO := {
	world_ripple_px = 700.0,   # show a world ripple only if camera within this of the shot
	ripple_seconds = 0.7,
	ripple_radius = 120.0,
	alert_radius_px = 600.0,   # Aggressive zombies within this get pulled toward the shot
	alert_seconds = 3.0,
}
```

- [ ] **Step 2: World ripple node**

```gdscript
# scripts/noise_ripple.gd
extends Node2D
var _age := 0.0

func _process(delta: float) -> void:
	_age += delta
	if _age > Balance.AGGRO.ripple_seconds:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var frac := _age / Balance.AGGRO.ripple_seconds
	var r := frac * Balance.AGGRO.ripple_radius
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(1, 1, 1, (1.0 - frac) * 0.18), 2.0)
```

- [ ] **Step 3: Spawn it on nearby noise events**

In `zombie_controller.gd`, extend the `noise_event` subscription:

```gdscript
	get_tree().current_scene.noise_event.connect(func(pos, _str):
		if minimap: minimap.register_noise(pos)
		if camera and camera.global_position.distance_to(pos) <= Balance.AGGRO.world_ripple_px:
			var rip := preload("res://scripts/noise_ripple.gd").new()
			rip.global_position = MinimapMath.fuzz(pos, 30.0, _ripple_rng)
			rip.z_index = 40
			get_tree().current_scene.add_child(rip))
```
Add `var _ripple_rng := RandomNumberGenerator.new()`.

- [ ] **Step 4: Verify in editor**

Local MP: fire while the zombie camera is near the shooter → a faint, brief world-space ripple appears near the shot; fire while the camera is far away → no world ripple (only the minimap one).

- [ ] **Step 5: Commit**

```bash
git add scripts/noise_ripple.gd scripts/zombie_controller.gd scripts/balance.gd
git commit -m "feat(fx): subtle world-view ripple near gunshots when the zombie camera is close"
```

---

### Task 18: Sound aggro for Aggressive zombies

**Files:**
- Modify: `scenes/world/world.gd` (server-side: on noise event, alert nearby Aggressive zombies)
- Modify: `scenes/zombie/zombie.gd` (accept an alert that biases the target toward the shot)

**Interfaces:**
- Consumes: `World.emit_noise` (server side already fires)
- Produces: `zombie.alert_to(world_pos: Vector2)` — temporarily steers an Aggressive zombie toward `world_pos`

- [ ] **Step 1: Add alert handling on the zombie**

```gdscript
var _alert_point: Vector2 = Vector2.ZERO
var _alert_timer: float = 0.0

func alert_to(world_pos: Vector2) -> void:
	if stance != Stance.AGGRESSIVE:
		return  # Hold/flee/etc. deliberately ignore sound
	_alert_point = world_pos
	_alert_timer = Balance.AGGRO.alert_seconds
```

In the AGGRESSIVE branch of `_physics_process`, if no enemy is acquired but an alert is active, head toward the alert point:

```gdscript
		Stance.AGGRESSIVE:
			var e := _acquire_enemy()
			if e:
				target = e
				nav_agent.target_position = e.global_position
			elif _alert_timer > 0.0:
				target = null
				_alert_timer -= delta
				nav_agent.target_position = _alert_point
			else:
				target = null
				return
```

- [ ] **Step 2: Alert nearby zombies server-side**

In `world.gd` `emit_noise` (server branch), before/after the RPC, pull Aggressive zombies within range:

```gdscript
func emit_noise(world_pos: Vector2, strength: float) -> void:
	if not multiplayer.is_server():
		return
	for z in get_tree().get_nodes_in_group("zombies"):
		if z is Node2D and z.has_method("alert_to") \
			and z.global_position.distance_to(world_pos) <= Balance.AGGRO.alert_radius_px:
			z.alert_to(world_pos)
	rpc_noise_event.rpc(world_pos, strength)
```

- [ ] **Step 3: Verify in editor**

Local MP: put some zombies on **Aggressive** out of sight of the shooter and some on **Hold**; fire near them. Aggressive zombies turn and move toward the gunshot; Hold zombies do not react (even though they "heard" it). Confirm `logs_read` clean.

- [ ] **Step 4: Commit + changelog**

```bash
git add scenes/world/world.gd scenes/zombie/zombie.gd CHANGELOG.md
git commit -m "feat(ai): sound aggro pulls Aggressive zombies toward gunshots; close Phase G"
```
CHANGELOG line: `Phase G (RTS): world-view gunshot ripple near the camera + sound aggro that draws Aggressive zombies toward shots (Hold/flee stances ignore it).`

---

## Phase H — Fog verify/polish

### Task 19: Verify fog coverage and tune

**Files:**
- Modify (only if tuning needed): `scripts/balance.gd` (`FOG_ZC`)
- Modify: `PROJECT.md`, `ARCHITECTURE.md` (status/structure update)

- [ ] **Step 1: Verify in editor**

MCP `project_run` (zombie role) + owner playtest: confirm `ZCFogRect` covers the full 3008px map at min and max zoom, and all three states render distinctly (black unexplored / dim explored / bright visible). Confirm the minimap's terrain matches the world fog.

- [ ] **Step 2: Tune if needed**

If explored areas read too dark/bright against the new minimap, adjust `Balance.FOG_ZC.vis_explored` (currently `0.35`). Otherwise no change.

- [ ] **Step 3: Update docs**

Update `PROJECT.md` "Current status" with the new RTS features and `ARCHITECTURE.md` with the new files (`combat_math.gd`, `targeting.gd`, `stance_logic.gd`, `minimap_math.gd`, `health_bar.gd`, `minimap.gd`, `noise_ripple.gd`) and the noise-event flow.

- [ ] **Step 4: Commit + changelog**

```bash
git add scripts/balance.gd PROJECT.md ARCHITECTURE.md CHANGELOG.md
git commit -m "docs(rts): verify fog, update architecture/project status; close Phase H"
```
CHANGELOG line: `Phase H (RTS): verified two-layer fog coverage; docs updated for the RTS zombie experience.`

---

## Self-review notes

- **Spec coverage:** discrete combat (A) · unit separation (B) · stances + targeting (C) · stance toolbar/placement/preview/control-groups (D) · health bars (E) · minimap with terrain/blips/ghosts/under-attack/ripple/click-to-jump (F) · world ripple + sound aggro (G) · fog verify (H). All spec sections map to tasks.
- **Replication:** `hp` already replicated — health bars (E) and under-attack pulse (F) read it directly; no new sync config needed beyond existing scenes.
- **Headless tests** only for pure helpers (`CombatMath`, `Targeting`, `StanceLogic`, `MinimapMath`); all scene behavior is verified in the live editor per project constraints.
- **Type consistency:** `set_stance(stance, p1, p2)`, `Stance` enum, `took_damage(zombie, amount)`, `register_attack/register_noise`, `emit_noise/rpc_noise_event/noise_event`, `MinimapMath.world_to_minimap/minimap_to_world/fuzz` are used consistently across tasks.
