# Shooting Phase 2 — Center-Mass Headshots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A bullet whose straight path threads a zombie's small center crit zone deals 4× the range-adjusted damage, with a "HEADSHOT!" HUD toast for the player's own crits.

**Architecture:** Detection is pure ray-distance math added to `AimModel` (no new colliders) and applied server-side in `bullet.gd`. The two tuning numbers live in `Balance.HEADSHOT`. Feedback reuses the existing pickup-toast path: a synced counter on the shooter bumps on a player crit, and the controlling client's HUD pops a message.

**Tech Stack:** Godot 4.6 / GDScript, WebSocket multiplayer, MultiplayerSynchronizer/Spawner.

**Spec:** `docs/superpowers/specs/2026-06-23-shooting-headshots-design.md`

## Global Constraints

- Godot binary: `"/Applications/Godot 2.app/Contents/MacOS/Godot"` (called `$GODOT` below).
- **Compile-check command** (the "test" for scene/gameplay tasks — expects NO matching lines):
  ```bash
  "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
    | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
  ```
- **Headless unit test:** `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd`
- **Commits are LOCAL ONLY. Never `git push`.** The user pushes to GitHub themselves.
- Crit applies to **zombies only** (group `"zombies"`): standard/fast/fat/master. NPCs and the shooter have no crit zone.
- **Any** bullet can crit (allies included); only **player** crits show the toast.
- Tuning values live in `Balance` — no magic numbers in the consumers.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `scripts/aim_model.gd` | Add `is_headshot()` ray-distance math | Modify |
| `test/test_aim_model.gd` | Unit-test `is_headshot` | Modify |
| `scripts/balance.gd` | `HEADSHOT` tuning block | Modify |
| `scenes/bullet/bullet.gd` | Apply crit damage; gate toast via `from_player` | Modify |
| `scripts/weapons.gd` | `fire()` accepts an optional `source` (firer) | Modify |
| `scenes/shooter/shooter.gd` | `register_headshot()` + synced counter + signal | Modify |
| `scenes/shooter/shooter.tscn` | Sync `headshot_seq` | Modify |
| `scenes/ui/hud.gd` | "HEADSHOT!" toast (shared `_pop_toast`) | Modify |

---

## Task 1: `AimModel.is_headshot` + unit test

**Files:**
- Modify: `scripts/aim_model.gd`
- Test: `test/test_aim_model.gd`

**Interfaces:**
- Produces: `AimModel.is_headshot(origin: Vector2, dir: Vector2, target: Vector2, radius: float) -> bool` — true when the perpendicular distance from `target` to the ray `(origin, dir)` is ≤ `radius`. `dir` need not be normalised.

- [ ] **Step 1: Write the failing test**

In `test/test_aim_model.gd`, immediately after the existing line `_check("random_in_disk within radius", ok)`, insert:

```gdscript
	# --- Headshot ray-distance (Phase 2) ---
	_check("dead-center is a headshot",
		AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 0), 5.0))
	_check("just inside the radius is a headshot",
		AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 4.9), 5.0))
	_check("just outside the radius is not",
		not AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 5.1), 5.0))
	_check("a parallel near-miss is not",
		not AimModel.is_headshot(Vector2.ZERO, Vector2(1, 0), Vector2(100, 50), 5.0))
	_check("works with an un-normalised direction",
		AimModel.is_headshot(Vector2.ZERO, Vector2(10, 0), Vector2(100, 3), 5.0))
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -20
```
Expected: FAIL — a parse/runtime error that `is_headshot` is not a function of `AimModel` (the method doesn't exist yet).

- [ ] **Step 3: Write the implementation**

In `scripts/aim_model.gd`, add after the `random_in_disk` function:

```gdscript

## True when a shot fired from `origin` along `dir` passes within `radius` of
## `target` — i.e. its straight path threads the target's center crit zone.
## `dir` need not be normalised.
static func is_headshot(origin: Vector2, dir: Vector2, target: Vector2, radius: float) -> bool:
	var d := dir.normalized()
	if d == Vector2.ZERO:
		return false
	# Perpendicular distance from `target` to the ray = |(target - origin) x d|.
	return absf((target - origin).cross(d)) <= radius
```

- [ ] **Step 4: Run the test to verify it passes**

`is_headshot` is a new method on the existing `AimModel` class, but run the compile-check first so the editor reimports, then the test:

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . >/dev/null 2>&1
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -8
```
Expected: every line `PASS ...`, final line `ALL TESTS PASSED`, exit code 0.

- [ ] **Step 5: Commit (local only)**

```bash
git add scripts/aim_model.gd test/test_aim_model.gd
git commit -m "feat(headshot): AimModel.is_headshot ray-distance + unit test"
```

---

## Task 2: `Balance.HEADSHOT` + crit damage on zombies

**Files:**
- Modify: `scripts/balance.gd`
- Modify: `scenes/bullet/bullet.gd`

**Interfaces:**
- Consumes: `AimModel.is_headshot` (Task 1).
- Produces: `Balance.HEADSHOT = { radius_px: float, mult: float }`; crit-scaled damage in the bullet's zombie branch.

- [ ] **Step 1: Add the Balance block**

In `scripts/balance.gd`, add after the `const SHOTGUN := { ... }` block (just before the `# --- Merging ---` line):

```gdscript

# --- Headshots (Phase 2) ---
const HEADSHOT := {
	radius_px = 5.0,   # center crit zone radius, same on every zombie
	mult = 4.0,        # crit damage multiplier (x the range-adjusted damage)
}
```

- [ ] **Step 2: Apply the crit in the bullet's zombie branch**

In `scenes/bullet/bullet.gd` `_on_body_entered`, replace the zombie branch:

```gdscript
	if body.is_in_group("zombies"):
		# Deal damage to the zombie
		if body.has_method("take_damage"):
			body.take_damage(_damage_for_hit())
		queue_free()
```

with:

```gdscript
	if body.is_in_group("zombies"):
		# Center-mass crit: 4x when the shot's path threads the zombie's core.
		var dmg := _damage_for_hit()
		if AimModel.is_headshot(origin, direction, body.global_position, Balance.HEADSHOT.radius_px):
			dmg *= Balance.HEADSHOT.mult
		if body.has_method("take_damage"):
			body.take_damage(dmg)
		queue_free()
```

(Leave the `npcs`, `TileMapLayer`, and `StaticBody2D` branches unchanged — crit is zombies-only.)

- [ ] **Step 3: Compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
  | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
```
Expected: no output.

- [ ] **Step 4: Manual sanity (editor / godot-ai MCP)**

Play single-player → Human. Fire at a standing zombie's exact center vs its edge: center hits kill markedly faster (4×). Walk toward max pistol range and confirm a center hit there deals clearly less than 140 (range falloff still scales the crit).

- [ ] **Step 5: Commit (local only)**

```bash
git add scripts/balance.gd scenes/bullet/bullet.gd
git commit -m "feat(headshot): center-mass crit damage on zombies (4x, range-scaled)"
```

---

## Task 3: "HEADSHOT!" toast for player crits

**Files:**
- Modify: `scripts/weapons.gd`
- Modify: `scenes/bullet/bullet.gd`
- Modify: `scenes/shooter/shooter.gd`
- Modify: `scenes/shooter/shooter.tscn`
- Modify: `scenes/ui/hud.gd`

**Interfaces:**
- Consumes: the bullet crit branch (Task 2); the shooter's existing pickup-toast pattern.
- Produces: `Weapons.fire(..., source: Node = null)`; `bullet.from_player: bool`, `bullet.shooter_ref: Node`; `shooter.register_headshot()`; `shooter.headshot` signal; synced `shooter.headshot_seq`.

- [ ] **Step 1: Let `Weapons.fire` tag the firer**

In `scripts/weapons.gd`, change the `fire` signature:

```gdscript
static func fire(parent: Node, origin: Vector2, cursor_pos: Vector2, radius_px: float, w: WeaponData, source: Node = null) -> void:
```

and inside the per-pellet loop, immediately after `bullet.weapon = w`, add:

```gdscript
		bullet.shooter_ref = source
		bullet.from_player = source != null
```

(The NPC fire call passes no `source`, so it defaults to `null` — armed-NPC crits still deal 4× but never toast. No NPC file change needed.)

- [ ] **Step 2: Add the fields + crit-notify to the bullet**

In `scenes/bullet/bullet.gd`, add after `var weapon: WeaponData = null`:

```gdscript
## Set by Weapons.fire when the player fires; gates the HEADSHOT toast (not damage).
var from_player: bool = false
var shooter_ref: Node = null
```

Then in the zombie branch (from Task 2), add the notify inside the headshot `if`:

```gdscript
	if body.is_in_group("zombies"):
		# Center-mass crit: 4x when the shot's path threads the zombie's core.
		var dmg := _damage_for_hit()
		if AimModel.is_headshot(origin, direction, body.global_position, Balance.HEADSHOT.radius_px):
			dmg *= Balance.HEADSHOT.mult
			if from_player and is_instance_valid(shooter_ref):
				shooter_ref.register_headshot()
		if body.has_method("take_damage"):
			body.take_damage(dmg)
		queue_free()
```

- [ ] **Step 3: Pass the shooter as the firer**

In `scenes/shooter/shooter.gd` `shoot()`, change:

```gdscript
	Weapons.fire(parent, gun_tip.global_position, cursor, radius, w)
```

to:

```gdscript
	Weapons.fire(parent, gun_tip.global_position, cursor, radius, w, self)
```

- [ ] **Step 4: Add the counter, signal, and method to the shooter**

In `scenes/shooter/shooter.gd`, add after the `pickup_seq` property block:

```gdscript
## Bumped server-side on each player headshot; the controlling client's HUD
## reads the change and pops a "HEADSHOT!" toast (mirrors pickup_seq).
var headshot_seq: int = 0:
	set(value):
		headshot_seq = value
		headshot.emit()
```

Add next to the other signals (after `signal pickup_collected(kind: int)`):

```gdscript
signal headshot
```

Add the method (near `_notify_pickup`):

```gdscript
## Server-side: record a headshot so the controlling client toasts it.
func register_headshot() -> void:
	headshot_seq += 1
```

- [ ] **Step 5: Sync `headshot_seq`**

In `scenes/shooter/shooter.tscn`, in the `[sub_resource type="SceneReplicationConfig" id="SceneReplicationConfig_sync"]` block, after the `properties/12/...` lines add:

```
properties/13/path = NodePath(".:headshot_seq")
properties/13/spawn = true
properties/13/replication_mode = 2
```

- [ ] **Step 6: Show the toast (shared helper)**

In `scenes/ui/hud.gd` `setup()`, after the `pickup_collected` connection, add:

```gdscript
	if shooter.has_signal("headshot"):
		shooter.headshot.connect(_on_headshot)
```

Then replace the whole `_on_pickup_collected` function with these three functions (extracts the shared toast tween so the headshot reuses it):

```gdscript
## Pop a fading toast when the shooter collects a pickup.
func _on_pickup_collected(kind: int) -> void:
	if not PICKUP_MESSAGES.has(kind):
		return
	_pop_toast(PICKUP_MESSAGES[kind], PICKUP_COLORS.get(kind, Color.WHITE))


## Pop the crit toast for the player's own headshots.
func _on_headshot() -> void:
	_pop_toast("HEADSHOT!", Color(1.0, 0.85, 0.2))


## Show `text` on the toast label and fade it out.
func _pop_toast(text: String, color: Color) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.modulate = color
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	# Snap to fully visible, hold, then fade out.
	_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.1)
	_toast_tween.tween_interval(1.0)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)
```

- [ ] **Step 7: Compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
  | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
```
Expected: no output.

- [ ] **Step 8: Manual sanity (editor / godot-ai MCP)**

Play single-player → Human. A center hit pops a yellow **"HEADSHOT!"** toast (same spot/style as pickup messages); an edge hit deals normal damage with no toast.

- [ ] **Step 9: Commit (local only)**

```bash
git add scripts/weapons.gd scenes/bullet/bullet.gd scenes/shooter/shooter.gd scenes/shooter/shooter.tscn scenes/ui/hud.gd
git commit -m "feat(headshot): HEADSHOT! toast on player crits (reuses pickup toast)"
```

---

## Task 4: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Unit test + compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -3
```
Expected: no grep output; `ALL TESTS PASSED`.

- [ ] **Step 2: Single-player feel pass**

Center hit = 4× (kills faster) and shows the toast; edge hit = normal, no toast. A center hit near max range is reduced by falloff. Shotgun: each centered pellet crits independently.

- [ ] **Step 3: Multiplayer pass**

Two windows (host + join; e.g. `--autojoin` second instance). As the human: center hits crit and toast on your screen; confirm the **zombie-role** player never sees the toast and damage/positions replicate identically on both peers.

- [ ] **Step 4: Regression pass**

Normal (non-center) shots, range falloff, reload/ammo/swap/drop, NPC fire-at-will, and the pickup toast all behave as before. An armed-NPC ally's center hit on a zombie deals 4× but produces **no** toast.

- [ ] **Step 5: Final commit (local only, if any tweaks were made)**

```bash
git add -A
git commit -m "test(headshot): Phase 2 verification tweaks"
```

---

## Self-Review notes (author)

- **Spec coverage:** crit detection (T1 `is_headshot`), crit damage 4× range-scaled on zombies (T2), `Balance.HEADSHOT` tuning (T2), "HEADSHOT!" toast for player crits only via the pickup-toast pattern (T3), server-authoritative + synced counter, no new entity state (T3/T4), zombies-only + any-bullet-crits (T2 zombie branch unguarded by owner; toast gated by `from_player`). All covered.
- **Non-breakage:** `Weapons.fire` gains a trailing optional `source = null`, so the NPC call site is unaffected; bullet `from_player`/`shooter_ref` default to false/null and are server-only (not in the replication config), so clients and NPC fire behave unchanged.
- **Type consistency:** `is_headshot(origin, dir, target, radius) -> bool` used identically in the test and `bullet.gd`; `register_headshot()` (shooter) called from `bullet.gd`; `headshot_seq` synced int mirrors `pickup_seq`; `_pop_toast(text, color)` used by both toast handlers.
- **Deferred (per spec):** one global crit multiplier (no per-weapon crit); no crit on NPCs/shooter; no sound/floating numbers.
