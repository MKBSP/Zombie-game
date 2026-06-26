# Shooting Phase 3 — NPC Shooting Under the Aim Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Armed NPCs fire under the real `AimModel` spread with their own panic + moving/injured/recoil debuffs, a spark-then-autonomous engagement rule, and a 1.5 shots/sec cap — all tunable separately from the player.

**Architecture:** A new NPC-only pure-math module (`NpcAim`) computes the additive aim debuff and recoil decay; `npc_human.gd` holds the live recoil + engagement state and feeds the debuff into the shared `AimModel.spread_coeff`. The player's `shooter.gd` is untouched.

**Tech Stack:** Godot 4.6 / GDScript, WebSocket multiplayer, MultiplayerSynchronizer/Spawner.

**Spec:** `docs/superpowers/specs/2026-06-25-npc-shooting-design.md`

## Global Constraints

- Godot binary: `"/Applications/Godot 2.app/Contents/MacOS/Godot"` (called `$GODOT` below).
- **Compile-check** (expects NO matching lines):
  ```bash
  "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
    | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
  ```
- **Headless unit test:** `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script <test.gd>`
- After adding a new `class_name` script, run the compile-check once before the headless `--script` run so the global class cache registers it.
- **Commits are LOCAL ONLY. Never `git push`.** The user pushes to GitHub themselves.
- **Do not touch `scenes/shooter/shooter.gd`** — NPC accuracy is independent of the player's.
- Friendly fire stays **on** (no bullet changes). NPC bullets carry no `source` (no toast; crits + falloff already apply).
- NPCs fire **no faster than 1.5 shots/sec**.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `scripts/npc_aim.gd` | Pure NPC aim math (`NpcAim`): debuff + recoil decay | Create |
| `test/test_npc_aim.gd` | Headless unit test for `NpcAim` | Create |
| `scripts/balance.gd` | `Balance.NPC` accuracy/engagement knobs | Modify |
| `scenes/npc/npc_human.gd` | Engagement latch, spread model, recoil, fire-rate cap | Modify |

---

## Task 1: `NpcAim` pure math + unit test

**Files:**
- Create: `scripts/npc_aim.gd`
- Test: `test/test_npc_aim.gd`

**Interfaces:**
- Produces:
  - `NpcAim.aim_debuff(b: Dictionary, moving: bool, hp: int, max_hp: int, recoil: float) -> float` — additive panic + moving + injured/hurt (worse wins) + recoil; unclamped.
  - `NpcAim.recoil_after(initial: float, elapsed: float, recover: float) -> float` — current recoil as it decays to 0 over `recover` seconds.

- [ ] **Step 1: Write the failing test**

Create `test/test_npc_aim.gd`:

```gdscript
extends SceneTree

## Headless unit test for NpcAim. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_npc_aim.gd

var _failures := 0


func _init() -> void:
	var b := {
		panic = 0.35, debuff_running = 0.20, debuff_injured = 0.20,
		debuff_hurt = 0.40, injured_hp_frac = 0.5,
	}
	_eq("panic only", NpcAim.aim_debuff(b, false, 50, 50, 0.0), 0.35)
	_eq("moving adds running", NpcAim.aim_debuff(b, true, 50, 50, 0.0), 0.55)
	_eq("injured tier (below max, above half)", NpcAim.aim_debuff(b, false, 30, 50, 0.0), 0.55)
	_eq("hurt tier (below half) - worse wins", NpcAim.aim_debuff(b, false, 20, 50, 0.0), 0.75)
	_eq("recoil adds on top", NpcAim.aim_debuff(b, false, 50, 50, 0.5), 0.85)
	_eq("recoil full at elapsed 0", NpcAim.recoil_after(0.5, 0.0, 2.0), 0.5)
	_eq("recoil half-decayed", NpcAim.recoil_after(0.5, 1.0, 2.0), 0.25)
	_eq("recoil fully decayed", NpcAim.recoil_after(0.5, 2.0, 2.0), 0.0)
	_eq("recoil with no recover window", NpcAim.recoil_after(0.5, 0.0, 0.0), 0.0)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _eq(label: String, got: float, want: float) -> void:
	if absf(got - want) > 0.0001:
		_failures += 1
		print("FAIL %s: got %f want %f" % [label, got, want])
	else:
		print("PASS %s" % label)
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_npc_aim.gd 2>&1 | tail -20
```
Expected: FAIL — a parse/runtime error that `NpcAim` is not declared (the class doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `scripts/npc_aim.gd`:

```gdscript
extends RefCounted
class_name NpcAim

## Pure aim math for armed NPCs — kept separate from the player's (shooter.gd) and
## from the shared weapon spread (AimModel), so NPC accuracy can be tuned and
## upgraded on its own. Stateless; the NPC instance holds the live recoil state.

## Additive aim debuff: panic + moving + injured/hurt (worse tier wins) + recoil.
## Unclamped — AimModel.spread_coeff clamps the total to 1.0.
static func aim_debuff(b: Dictionary, moving: bool, hp: int, max_hp: int, recoil: float) -> float:
	var total: float = b.panic
	if moving:
		total += b.debuff_running
	if hp < int(max_hp * b.injured_hp_frac):
		total += b.debuff_hurt
	elif hp < max_hp:
		total += b.debuff_injured
	total += recoil
	return total


## Current recoil given the per-shot kick `initial` and how far it has decayed
## (`elapsed` seconds into a `recover`-second window). 0 when the window is closed.
static func recoil_after(initial: float, elapsed: float, recover: float) -> float:
	if recover <= 0.0:
		return 0.0
	return initial * clampf(1.0 - elapsed / recover, 0.0, 1.0)
```

- [ ] **Step 4: Register the class, then run the test**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . >/dev/null 2>&1
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_npc_aim.gd 2>&1 | tail -12
```
Expected: every line `PASS ...`, final line `ALL TESTS PASSED`, exit code 0.

- [ ] **Step 5: Commit (local only)**

```bash
git add scripts/npc_aim.gd test/test_npc_aim.gd
git commit -m "feat(npc-aim): NpcAim debuff + recoil math with unit test"
```

---

## Task 2: `Balance.NPC` accuracy/engagement knobs

**Files:**
- Modify: `scripts/balance.gd`

**Interfaces:**
- Produces: `Balance.NPC` keys `panic`, `debuff_running`, `debuff_injured`, `debuff_hurt`, `injured_hp_frac`, `recoil_initial`, `recoil_recover_factor`, `dmg_ref`, `min_shot_interval` (consumed by Task 3). `aim_jitter` is kept for now; Task 3 removes it together with its last reader.

- [ ] **Step 1: Add the knobs**

In `scripts/balance.gd`, replace the `vision_px`/`muzzle_offset` tail of the `NPC` block. Find:

```gdscript
	aim_jitter = 0.25,        # ~14 degrees of armed-NPC sloppiness
	vision_px = 384.0,        # 6 tiles
	muzzle_offset = 40.0,     # spawn bullets past the NPC's own body
}
```

Replace with:

```gdscript
	aim_jitter = 0.25,        # DEPRECATED (Phase 3 removes the last reader)
	vision_px = 384.0,        # 6 tiles
	muzzle_offset = 40.0,     # spawn bullets past the NPC's own body
	# --- Armed-NPC accuracy (Phase 3), separate from the player ---
	panic = 0.35,                  # base inaccuracy floor (always applied)
	debuff_running = 0.20,         # added while moving
	debuff_injured = 0.20,         # added when hp < max_hp
	debuff_hurt = 0.40,            # added when hp < max_hp * injured_hp_frac (replaces injured)
	injured_hp_frac = 0.5,
	recoil_initial = 0.50,         # per-shot kick
	recoil_recover_factor = 2.0,   # seconds-per-damage-unit to recover
	dmg_ref = 35.0,                # damage unit for recoil scaling (pistol = 1)
	min_shot_interval = 0.667,     # 1.5 shots/sec cap
}
```

- [ ] **Step 2: Compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
  | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
```
Expected: no output.

- [ ] **Step 3: Commit (local only)**

```bash
git add scripts/balance.gd
git commit -m "feat(npc-aim): Balance.NPC accuracy + engagement knobs"
```

---

## Task 3: Engagement + spread + recoil + fire-rate in npc_human.gd

**Files:**
- Modify: `scenes/npc/npc_human.gd`
- Modify: `scripts/balance.gd` (drop the now-unused `aim_jitter`)

**Interfaces:**
- Consumes: `NpcAim.aim_debuff` / `NpcAim.recoil_after` (Task 1); `Balance.NPC` knobs (Task 2); existing `AimModel.spread_coeff`, `Weapons`, `shooter.is_firing()`.

- [ ] **Step 1: Drop the dead `NPC_AIM_JITTER` field**

In `scenes/npc/npc_human.gd`, delete the declaration line:

```gdscript
var NPC_AIM_JITTER: float   # armed-NPC aim error (radians)
```

and, in `_ready()`, delete the assignment line:

```gdscript
	NPC_AIM_JITTER = b.aim_jitter
```

- [ ] **Step 2: Add engagement + recoil state**

In `scenes/npc/npc_human.gd`, after the existing weapon-state vars (`var _npc_reloading: bool = false`), add:

```gdscript
# Armed-combat state (server-side). _engaged latches on the player's spark and
# holds while a zombie is visible; recoil mirrors the player's shape with NPC knobs.
var _engaged: bool = false
var _recoil: float = 0.0
var _recoil_elapsed: float = 0.0
var _recoil_recover: float = 0.0
```

- [ ] **Step 3: Pass delta into the shooting update**

In `_physics_process`, change the `State.FOLLOWING` branch from:

```gdscript
		State.FOLLOWING:
			_process_following()
			if weapon_id != -1:
				_process_shooting()
```

to:

```gdscript
		State.FOLLOWING:
			_process_following()
			if weapon_id != -1:
				_process_shooting(delta)
```

- [ ] **Step 4: Rewrite `_process_shooting` with the new model**

Replace the entire `_process_shooting` function:

```gdscript
func _process_shooting() -> void:
	if _npc_reloading or not _npc_can_shoot or weapon_mag <= 0:
		return
	if not is_instance_valid(shooter) or not shooter.has_method("is_firing") or not shooter.is_firing():
		return
	var target := _nearest_zombie(NPC_VISION_PX)
	if target == null:
		return

	var w := Weapons.get_data(weapon_id)
	var base_angle: float = (target.global_position - global_position).angle()
	# Spawn past our own collider so the NPC never shoots itself.
	var origin: Vector2 = global_position + Vector2.from_angle(base_angle) * MUZZLE_OFFSET
	var cursor: Vector2 = target.global_position
	var radius: float = NPC_AIM_JITTER * origin.distance_to(cursor)
	Weapons.fire(get_parent(), origin, cursor, radius, w)

	weapon_mag -= 1
	weapon_total -= 1
	_npc_can_shoot = false
	if weapon_total <= 0:
		weapon_id = -1  # weapon spent
		return
	if weapon_mag <= 0:
		_npc_reloading = true
		npc_shoot_cooldown.start(w.reload_time)
	else:
		npc_shoot_cooldown.start(maxf(w.cooldown, 0.05))
```

with:

```gdscript
func _process_shooting(delta: float) -> void:
	# Recoil decays every armed frame.
	_recoil_elapsed += delta
	_recoil = NpcAim.recoil_after(Balance.NPC.recoil_initial, _recoil_elapsed, _recoil_recover)

	# --- Engagement latch: a visible zombie is required to stay engaged. ---
	var target := _nearest_zombie(NPC_VISION_PX)
	if target == null:
		_engaged = false
		return
	if not _engaged:
		# Spark: the player firing near a visible zombie engages us; after that we
		# fight on our own until no zombie is visible.
		if is_instance_valid(shooter) and shooter.has_method("is_firing") and shooter.is_firing():
			_engaged = true
		else:
			return

	# --- Fire (gated by ammo / reload / fire-rate cap). ---
	if _npc_reloading or not _npc_can_shoot or weapon_mag <= 0:
		return

	var w := Weapons.get_data(weapon_id)
	var base_angle: float = (target.global_position - global_position).angle()
	# Spawn past our own collider so the NPC never shoots itself.
	var origin: Vector2 = global_position + Vector2.from_angle(base_angle) * MUZZLE_OFFSET
	var cursor: Vector2 = target.global_position
	var moving: bool = velocity.length() > 5.0
	var debuff: float = NpcAim.aim_debuff(Balance.NPC, moving, hp, max_hp, _recoil)
	var coeff: float = AimModel.spread_coeff(w, debuff, 0.0)
	var radius: float = coeff * origin.distance_to(cursor)
	Weapons.fire(get_parent(), origin, cursor, radius, w)

	# Per-shot recoil kick (decays over recover-factor x damage-units seconds).
	var dmg_units: float = (w.damage * w.pellets) / Balance.NPC.dmg_ref
	_recoil_elapsed = 0.0
	_recoil_recover = Balance.NPC.recoil_recover_factor * dmg_units

	weapon_mag -= 1
	weapon_total -= 1
	_npc_can_shoot = false
	if weapon_total <= 0:
		weapon_id = -1  # weapon spent
		return
	if weapon_mag <= 0:
		_npc_reloading = true
		npc_shoot_cooldown.start(w.reload_time)
	else:
		npc_shoot_cooldown.start(maxf(w.cooldown, Balance.NPC.min_shot_interval))
```

- [ ] **Step 5: Remove the deprecated Balance key**

In `scripts/balance.gd`, delete the now-unused line in the `NPC` block:

```gdscript
	aim_jitter = 0.25,        # DEPRECATED (Phase 3 removes the last reader)
```

- [ ] **Step 6: Compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
  | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
```
Expected: no output.

- [ ] **Step 7: Manual sanity (editor / godot-ai MCP)**

Play single-player → Human. Walk an NPC into you so it follows, hand it a weapon (the give-to-NPC key), then approach zombies and fire: the NPC starts shooting once a zombie is in its sight and you've fired; it keeps firing after you stop; it goes quiet when you drag the fight out of its sight; its shots are looser while it (or you) is moving and right after it fires; it never out-paces ~1.5 shots/sec.

- [ ] **Step 8: Commit (local only)**

```bash
git add scenes/npc/npc_human.gd scripts/balance.gd
git commit -m "feat(npc-aim): engagement latch + AimModel spread + recoil + 1.5/s cap"
```

---

## Task 4: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Unit tests + compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_npc_aim.gd 2>&1 | tail -3
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -3
```
Expected: no grep output; both tests print `ALL TESTS PASSED`.

- [ ] **Step 2: Single-player feel pass**

Per the spec: spark-to-engage, autonomous-until-out-of-sight, re-spark needed; tighter when still/healthy, wider when moving or post-shot; rifle NPC tighter than shotgun NPC; never faster than ~1.5 shots/sec.

- [ ] **Step 3: Multiplayer pass**

Two windows (host + join). Hand an NPC a weapon as the human; confirm its shots, damage, and engagement replicate identically on both peers (NPC fires on the server).

- [ ] **Step 4: Regression pass**

Unarmed NPCs still wander/hide/follow/convert; pickups, reload, weapon swap/drop/give still work; friendly fire still applies (an NPC's stray shot can still hit another NPC).

- [ ] **Step 5: Final commit (local only, if any tweaks were made)**

```bash
git add -A
git commit -m "test(npc-aim): Phase 3 verification tweaks"
```

---

## Self-Review notes (author)

- **Spec coverage:** AimModel-based spread with NPC-owned panic/moving/injured/recoil (T1 math + T3 wiring), no focus (focus arg = 0 in T3), independent knobs in `Balance.NPC` (T2), engagement latch spark→autonomous→idle-on-no-vision→re-spark (T3 Step 4), 1.5/s cap via `min_shot_interval` (T3), player code untouched (no shooter.gd edits), friendly fire kept (no bullet edits), no new synced state (server-side only). All covered.
- **Separation:** NPC math lives in `NpcAim` (own file) and reads `Balance.NPC`; `AimModel.spread_coeff` is the only shared piece (per-weapon formula). `shooter.gd` is not in any task.
- **No broken intermediate:** T2 adds keys while keeping `aim_jitter`; T3 swaps the reader and removes `aim_jitter` together, so every task ends runnable.
- **Type consistency:** `NpcAim.aim_debuff(b, moving, hp, max_hp, recoil)` and `NpcAim.recoil_after(initial, elapsed, recover)` used identically in the test and `npc_human.gd`; `_process_shooting(delta)` matches its one caller in `_physics_process`.
- **Deferred (per spec):** no target leading; single-shooter `is_firing()` spark (Phase 7 generalises).
