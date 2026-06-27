# Loot Box System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace scattered item spawning with openable loot crates that burst 1–3 items onto the floor, collected via a single contextual interact key.

**Architecture:** Pure roll logic (item count, weighted type, nearest-interactable pick) lives in headless-testable static helpers (`LootTable`, `Interact`). A new `LootBox` scene (server-authoritative, replicated) rolls loot on open and spawns existing `Pickup` nodes that animate out of the box. A contextual `interact` action on the shooter resolves to the nearest box/pickup/NPC within per-type radii. All tuning lives in `balance.gd`.

**Tech Stack:** Godot 4.6.3 GDScript, GL Compatibility 2D, server-authoritative multiplayer via `MultiplayerSpawner` + `MultiplayerSynchronizer`. Tests are headless `SceneTree` scripts.

## Global Constraints

- Engine: Godot 4.6.3, GL Compatibility, 2D. Run tests with: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/<file>.gd` (exit code 0 = pass).
- A live editor is usually running — prefer the **godot-ai MCP** (`script_patch`, `node_*`, `scene_*`, `test_run`, `editor_screenshot`, `project_run`, `logs_read`) over blind edits where practical. Check `editor_state` first.
- **All gameplay numbers go in `scripts/balance.gd`** — never hardcode tuning in scenes/scripts.
- Server-authoritative: all loot rolls, box opening, and effects run only when `multiplayer.is_server()`. Clients receive results via replication.
- **No `Co-Authored-By` / Claude attribution in commit messages.** Don't push unless asked.
- After meaningful changes, add a line to `CHANGELOG.md`; update `ARCHITECTURE.md` / `PROJECT.md` if structure or status shifts.
- House test convention: pure logic in `class_name` static helpers, tested headless. Scene/integration behavior verified manually via MCP `project_run` + `editor_screenshot` + `logs_read`.

---

## File Structure

- **Create** `scripts/loot_table.gd` — `LootTable` static helper: item-count roll, weighted-kind roll, weights assembly.
- **Create** `scripts/interact_pick.gd` — `Interact` static helper: nearest-candidate-within-radius resolution.
- **Create** `test/test_loot_table.gd` — headless tests for `LootTable`.
- **Create** `test/test_interact_pick.gd` — headless tests for `Interact`.
- **Create** `scenes/loot_box/loot_box.gd` + `scenes/loot_box/loot_box.tscn` — `LootBox` scene.
- **Modify** `scripts/balance.gd` — add `LOOT` tuning block.
- **Modify** `scenes/pickup/pickup.gd` — `BANDAGE` kind, sprite rendering, bandage heal, `collect()` refactor, cosmetic burst, `_collectable` gate.
- **Modify** `scenes/pickup/pickup.tscn` — add replicated `spawn_origin` property.
- **Modify** `scenes/ui/hud.gd` — `BANDAGE` toast message/color.
- **Modify** `scenes/shooter/shooter.gd` — contextual `interact` resolver; NPC give (tight radius) + take-back; heal signature.
- **Modify** `scenes/npc/npc_human.gd` — `surrender_weapon()`.
- **Modify** `scenes/world/world.gd` — `_spawn_loot_boxes()` replaces `_spawn_items()`; box placement + landing validation helpers.
- **Modify** `scenes/world/world.tscn` — add `loot_box.tscn` to `MultiplayerSpawner._spawnable_scenes`.
- **Modify** `project.godot` — rename input action `give_weapon_to_npc` → `interact`.

---

## Task 1: Balance block + pure roll/pick helpers

**Files:**
- Modify: `scripts/balance.gd` (append `LOOT` block after `WORLD`, ~line 115)
- Create: `scripts/loot_table.gd`
- Create: `scripts/interact_pick.gd`
- Test: `test/test_loot_table.gd`, `test/test_interact_pick.gd`

**Interfaces:**
- Produces: `LootTable.roll_item_count(r: float, chance_two: float, chance_three: float) -> int`
- Produces: `LootTable.roll_kind(r: float, weights: Dictionary) -> int` (weights = `{kind_int: weight_int}`, deterministic cumulative walk over sorted keys)
- Produces: `LootTable.kind_weights() -> Dictionary` (assembled from `Balance.LOOT` + `Pickup.Kind`)
- Produces: `Interact.choose_nearest(origin: Vector2, candidates: Array) -> int` (each candidate = `{ "pos": Vector2, "radius": float }`; returns index of nearest candidate whose distance ≤ its radius, else `-1`)
- Produces: `Balance.LOOT` dictionary (keys below)

- [ ] **Step 1: Add the `LOOT` block to `balance.gd`**

Insert after the `WORLD` constant (line 115):

```gdscript
# --- Loot boxes ------------------------------------------------------------
# box_count crates scatter on walkable tiles. Each box rolls an item count
# (chance_three -> 3, else chance_two -> 2, else 1), then each item rolls a
# kind by relative weight. Heal amounts and interaction radii live here too.
const LOOT := {
	box_count = 8,
	chance_two = 0.20,
	chance_three = 0.01,
	# Relative spawn weights per item kind (tune freely; need not sum to 100).
	weight_ammo_mag = 25,
	weight_bandage = 30,
	weight_medipack = 10,
	weight_melee = 10,
	weight_shotgun = 10,
	weight_machinegun = 10,
	weight_rifle = 5,
	# Heal amounts.
	heal_bandage = 10,
	heal_medipack = 50,
	# Burst: items land within burst_radius_px of the box, kept burst_min_sep_px
	# apart, animating over burst_tween_time seconds.
	burst_radius_px = 64.0,
	burst_min_sep_px = 28.0,
	burst_tween_time = 0.3,
	# Contextual-interact reach per target type (px).
	interact_pickup_px = 56.0,
	interact_box_px = 64.0,
	interact_give_px = 22.0,   # tight: must be on top of the NPC to give
	interact_take_px = 56.0,   # take-back is non-destructive -> normal reach
}
```

- [ ] **Step 2: Write the failing test for `LootTable`**

Create `test/test_loot_table.gd`:

```gdscript
extends SceneTree

## Headless unit test for LootTable. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_table.gd

var _failures := 0


func _init() -> void:
	# --- Item count: chance_three -> 3, chance_two -> 2, else 1 ---
	_eq_i("r below chance_three is 3", LootTable.roll_item_count(0.005, 0.20, 0.01), 3)
	_eq_i("r at chance_three boundary is 2", LootTable.roll_item_count(0.01, 0.20, 0.01), 2)
	_eq_i("r below chance_two is 2", LootTable.roll_item_count(0.1, 0.20, 0.01), 2)
	_eq_i("r at chance_two boundary is 1", LootTable.roll_item_count(0.20, 0.20, 0.01), 1)
	_eq_i("high r is 1", LootTable.roll_item_count(0.9, 0.20, 0.01), 1)

	# --- Weighted kind: cumulative walk over sorted keys {10:1, 20:3} ---
	var w := {10: 1, 20: 3}  # total 4: r<0.25 -> 10, else -> 20
	_eq_i("first bucket", LootTable.roll_kind(0.0, w), 10)
	_eq_i("just inside first bucket", LootTable.roll_kind(0.24, w), 10)
	_eq_i("second bucket", LootTable.roll_kind(0.25, w), 20)
	_eq_i("top of range", LootTable.roll_kind(0.999, w), 20)

	# --- Distribution sanity: weights roughly match counts over many rolls ---
	var counts := {10: 0, 20: 0}
	for i in range(8000):
		counts[LootTable.roll_kind(float(i) / 8000.0, w)] += 1
	var ratio := float(counts[20]) / float(counts[10])
	_check("20-weighted kind ~3x as common as 10-weighted (got %f)" % ratio,
		absf(ratio - 3.0) < 0.2)

	# --- kind_weights pulls every kind from Balance ---
	var kw := LootTable.kind_weights()
	_eq_i("bandage weight from balance", kw[Pickup.Kind.BANDAGE], Balance.LOOT.weight_bandage)
	_eq_i("rifle weight from balance", kw[Pickup.Kind.RIFLE], Balance.LOOT.weight_rifle)
	_check("kind_weights has all 7 kinds", kw.size() == 7)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _eq_i(label: String, got: int, want: int) -> void:
	if got != want:
		_failures += 1
		print("FAIL %s: got %d want %d" % [label, got, want])
	else:
		print("PASS %s" % label)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_table.gd`
Expected: FAIL — `LootTable` is an unknown identifier (class doesn't exist yet).

- [ ] **Step 4: Implement `LootTable`**

Create `scripts/loot_table.gd`:

```gdscript
extends RefCounted
class_name LootTable

## Pure, headless-testable loot rolls. No engine/scene state.


## Items in a box: chance_three -> 3, else chance_two -> 2, else 1.
## `r` is expected in [0, 1).
static func roll_item_count(r: float, chance_two: float, chance_three: float) -> int:
	if r < chance_three:
		return 3
	if r < chance_two:
		return 2
	return 1


## Pick a kind from `weights` ({kind_int: weight_int}) by a cumulative walk over
## sorted keys. `r` in [0, 1) maps onto the normalized cumulative ranges.
static func roll_kind(r: float, weights: Dictionary) -> int:
	var keys := weights.keys()
	keys.sort()
	var total := 0
	for k in keys:
		total += int(weights[k])
	if total <= 0:
		return keys[0]
	var threshold := r * float(total)
	var acc := 0.0
	for k in keys:
		acc += float(weights[k])
		if threshold < acc:
			return k
	return keys[keys.size() - 1]


## Assemble the {Pickup.Kind: weight} table from Balance.LOOT.
static func kind_weights() -> Dictionary:
	var l: Dictionary = Balance.LOOT
	return {
		Pickup.Kind.AMMO_MAG: l.weight_ammo_mag,
		Pickup.Kind.BANDAGE: l.weight_bandage,
		Pickup.Kind.MEDPACK: l.weight_medipack,
		Pickup.Kind.MELEE: l.weight_melee,
		Pickup.Kind.SHOTGUN: l.weight_shotgun,
		Pickup.Kind.MACHINEGUN: l.weight_machinegun,
		Pickup.Kind.RIFLE: l.weight_rifle,
	}
```

Note: `kind_weights()` references `Pickup.Kind.BANDAGE`, which is added in Task 2. To keep Task 1 self-contained and its test green now, **temporarily** map `BANDAGE` via its eventual int. `Pickup.Kind` is currently `{AMMO_MAG=0, RIFLE=1, SHOTGUN=2, MEDPACK=3, MACHINEGUN=4, MELEE=5}`; Task 2 appends `BANDAGE=6`. So for this task, if `Pickup.Kind` lacks `BANDAGE`, the test's `kind_weights` assertions will fail. **Therefore add `BANDAGE` to the enum as the first edit of Step 4** (it's a one-line enum addition in `scenes/pickup/pickup.gd:8`):

```gdscript
enum Kind { AMMO_MAG, RIFLE, SHOTGUN, MEDPACK, MACHINEGUN, MELEE, BANDAGE }
```

(The rest of the `BANDAGE` wiring — colors, sprite, heal — lands in Task 2.)

- [ ] **Step 5: Run the `LootTable` test to confirm it passes**

Run: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_table.gd`
Expected: PASS — `ALL TESTS PASSED`, exit 0.

- [ ] **Step 6: Write the failing test for `Interact`**

Create `test/test_interact_pick.gd`:

```gdscript
extends SceneTree

## Headless unit test for Interact.choose_nearest. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_interact_pick.gd

var _failures := 0


func _init() -> void:
	var origin := Vector2.ZERO

	# Out of range on all -> -1
	_eq_i("none in range", Interact.choose_nearest(origin, [
		{ "pos": Vector2(100, 0), "radius": 50.0 },
	]), -1)

	# Single in range -> 0
	_eq_i("single in range", Interact.choose_nearest(origin, [
		{ "pos": Vector2(40, 0), "radius": 50.0 },
	]), 0)

	# Nearest wins even when both in range
	_eq_i("nearest of two", Interact.choose_nearest(origin, [
		{ "pos": Vector2(50, 0), "radius": 64.0 },
		{ "pos": Vector2(20, 0), "radius": 64.0 },
	]), 1)

	# Tight radius excludes a closer-but-out-of-its-radius candidate:
	# index 0 is closer (30) but its radius is 22 -> out; index 1 (50) within 64.
	_eq_i("per-type radius gating", Interact.choose_nearest(origin, [
		{ "pos": Vector2(30, 0), "radius": 22.0 },
		{ "pos": Vector2(50, 0), "radius": 64.0 },
	]), 1)

	# Empty list -> -1
	_eq_i("empty list", Interact.choose_nearest(origin, []), -1)

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _eq_i(label: String, got: int, want: int) -> void:
	if got != want:
		_failures += 1
		print("FAIL %s: got %d want %d" % [label, got, want])
	else:
		print("PASS %s" % label)
```

- [ ] **Step 7: Run it to confirm it fails**

Run: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_interact_pick.gd`
Expected: FAIL — `Interact` unknown identifier.

- [ ] **Step 8: Implement `Interact`**

Create `scripts/interact_pick.gd`:

```gdscript
extends RefCounted
class_name Interact

## Pure nearest-interactable resolution. Each candidate carries its own reach,
## so a tight-radius type (e.g. NPC give) only wins when you're nearly on top
## of it. Returns the index of the nearest candidate within its own radius,
## or -1 if nothing is reachable.
static func choose_nearest(origin: Vector2, candidates: Array) -> int:
	var best := -1
	var best_d := INF
	for i in range(candidates.size()):
		var c: Dictionary = candidates[i]
		var d := origin.distance_to(c["pos"])
		if d <= float(c["radius"]) and d < best_d:
			best_d = d
			best = i
	return best
```

- [ ] **Step 9: Run the `Interact` test to confirm it passes**

Run: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_interact_pick.gd`
Expected: PASS — `ALL TESTS PASSED`, exit 0.

- [ ] **Step 10: Commit**

```bash
git add scripts/balance.gd scripts/loot_table.gd scripts/interact_pick.gd \
        scenes/pickup/pickup.gd test/test_loot_table.gd test/test_interact_pick.gd
git commit -m "feat(loot): balance block + pure loot-roll and interact-pick helpers"
```

---

## Task 2: Pickup — bandage kind, sprites, heal, collect() refactor, burst

**Files:**
- Modify: `scenes/pickup/pickup.gd`
- Modify: `scenes/pickup/pickup.tscn`
- Modify: `scenes/ui/hud.gd`
- Modify: `scenes/shooter/shooter.gd:434` (`heal` signature)

**Interfaces:**
- Consumes: `Balance.LOOT.heal_bandage`, `Balance.LOOT.heal_medipack`, `Balance.LOOT.burst_tween_time`; `Pickup.Kind.BANDAGE` (enum added in Task 1 Step 4).
- Produces: `Pickup.collect(body: Node2D) -> void` (server-side effect application, then `queue_free`)
- Produces: `Pickup.is_collectable() -> bool`
- Produces: `Pickup.spawn_origin: Vector2` (replicated; when set, the pickup animates from it to its final position on every peer)
- Produces: `shooter.heal(amount: int, kind: int = Pickup.Kind.MEDPACK) -> void`

- [ ] **Step 1: Add the `spawn_origin` replicated property to `pickup.tscn`**

In `scenes/pickup/pickup.tscn`, extend `SceneReplicationConfig_pk` with a third property (append after the `kind` block):

```
properties/2/path = NodePath(".:spawn_origin")
properties/2/spawn = true
properties/2/replication_mode = 0
```

- [ ] **Step 2: Refactor `pickup.gd` — sprites, bandage, `collect()`, burst**

Replace the constants/`@export`/`_ready`/`_refresh_color`/`_on_body_entered` region of `scenes/pickup/pickup.gd` (lines 10–79) with:

```gdscript
const COLORS := {
	Kind.AMMO_MAG: Color(0.95, 0.85, 0.2),
	Kind.RIFLE: Color(0.4, 0.6, 1.0),
	Kind.SHOTGUN: Color(1.0, 0.5, 0.2),
	Kind.MEDPACK: Color(0.9, 0.2, 0.3),
	Kind.MACHINEGUN: Color(0.6, 0.6, 0.65),
	Kind.MELEE: Color(0.7, 0.7, 0.75),
	Kind.BANDAGE: Color(0.95, 0.95, 0.9),
}

## Item kinds that render a dedicated PNG instead of a flat color tint.
const KIND_TO_SPRITE := {
	Kind.MEDPACK: preload("res://sprites/Medipack.png"),
	Kind.BANDAGE: preload("res://sprites/bandage.png"),
}

const PICKUP_SCENE := preload("res://scenes/pickup/pickup.tscn")

const WEAPON_TO_KIND := {
	Weapons.RIFLE: Kind.RIFLE,
	Weapons.SHOTGUN: Kind.SHOTGUN,
	Weapons.MACHINEGUN: Kind.MACHINEGUN,
	Weapons.MELEE: Kind.MELEE,
}

const KIND_TO_WEAPON := {
	Kind.RIFLE: Weapons.RIFLE,
	Kind.SHOTGUN: Weapons.SHOTGUN,
	Kind.MACHINEGUN: Weapons.MACHINEGUN,
	Kind.MELEE: Weapons.MELEE,
}

@export var kind: int = Kind.AMMO_MAG:
	set(value):
		kind = value
		_refresh_color()

## Box center this pickup bursts out of. Zero means "no burst" (plain spawn).
## Replicated on spawn so every peer plays the same jump-out locally.
@export var spawn_origin: Vector2 = Vector2.ZERO

## False while the burst tween is mid-flight — can't be collected in the air.
var _collectable: bool = true


func _ready() -> void:
	_refresh_color()
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
	if spawn_origin != Vector2.ZERO:
		_play_burst()


## Animate from spawn_origin to the (replicated) final position. Cosmetic and
## identical on every peer; the server additionally gates collection until the
## item has landed.
func _play_burst() -> void:
	var final_pos := global_position
	global_position = spawn_origin
	_collectable = false
	var t := create_tween()
	t.tween_property(self, "global_position", final_pos, Balance.LOOT.burst_tween_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): _collectable = true)


func is_collectable() -> bool:
	return _collectable


func _refresh_color() -> void:
	var s := get_node_or_null("Sprite2D")
	if s == null:
		return
	if KIND_TO_WEAPON.has(kind):
		s.texture = WeaponVisuals.texture(KIND_TO_WEAPON[kind])
		s.modulate = Color.WHITE
	elif KIND_TO_SPRITE.has(kind):
		s.texture = KIND_TO_SPRITE[kind]
		s.modulate = Color.WHITE
	else:
		s.modulate = COLORS.get(kind, Color.WHITE)


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if not body.is_in_group("shooter"):
		return
	if not _collectable:
		return
	collect(body)


## Apply this pickup's effect to `body` (the shooter) and despawn. Server-only.
## Called by _on_body_entered today; routed through the interact resolver in
## Task 3.
func collect(body: Node2D) -> void:
	if not multiplayer.is_server() or not _collectable:
		return
	match kind:
		Kind.AMMO_MAG:
			body.add_pistol_mag()
		Kind.RIFLE:
			_take_special(body, Weapons.RIFLE)
		Kind.SHOTGUN:
			_take_special(body, Weapons.SHOTGUN)
		Kind.MACHINEGUN:
			_take_special(body, Weapons.MACHINEGUN)
		Kind.MELEE:
			_take_melee(body, Weapons.MELEE)
		Kind.MEDPACK:
			body.heal(Balance.LOOT.heal_medipack, Kind.MEDPACK)
		Kind.BANDAGE:
			body.heal(Balance.LOOT.heal_bandage, Kind.BANDAGE)
	queue_free()
```

(The `_take_special` / `_take_melee` / `_drop_weapon_pickup` helpers below this region stay unchanged.)

- [ ] **Step 3: Update `shooter.heal` to take a kind**

In `scenes/shooter/shooter.gd`, replace `heal` (lines 434–436):

```gdscript
func heal(amount: int, kind: int = Pickup.Kind.MEDPACK) -> void:
	hp = min(hp + amount, max_hp)  # setter emits hp_changed
	_notify_pickup(kind)
```

- [ ] **Step 4: Add the bandage toast to `hud.gd`**

In `scenes/ui/hud.gd`, add a `BANDAGE` entry to `PICKUP_MESSAGES` (after line 21) and `PICKUP_COLORS` (after line 27):

```gdscript
	Pickup.Kind.BANDAGE: "+10 HP",
```
```gdscript
	Pickup.Kind.BANDAGE: Color(0.95, 0.95, 0.9),
```

- [ ] **Step 5: Re-run Task 1 tests (regression — enum/sprites must not break LootTable)**

Run: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_table.gd`
Expected: PASS — `ALL TESTS PASSED`.

- [ ] **Step 6: Manual verification via MCP**

Via godot-ai MCP: `editor_reload_plugin` if needed, then `project_run` the main scene. Use `editor_screenshot` / `logs_read` to confirm: the game loads with no parse errors, existing scattered pickups still appear, and a medpack/bandage pickup shows its PNG sprite (not a flat color). Walk the shooter over a medpack and confirm a "+50 HP" toast; over the (still-scattered, not-yet-from-box) pickups confirm collection still works (auto-grab intact this task).

- [ ] **Step 7: Commit**

```bash
git add scenes/pickup/pickup.gd scenes/pickup/pickup.tscn scenes/ui/hud.gd scenes/shooter/shooter.gd
git commit -m "feat(loot): bandage kind, item sprites, collect() refactor, burst animation"
```

---

## Task 3: Contextual interact — resolver, NPC give/take, drop auto-grab

**Files:**
- Modify: `project.godot` (rename action `give_weapon_to_npc` → `interact`)
- Modify: `scenes/shooter/shooter.gd`
- Modify: `scenes/npc/npc_human.gd`
- Modify: `scenes/pickup/pickup.gd` (remove `body_entered` auto-grab connection)

**Interfaces:**
- Consumes: `Interact.choose_nearest`, `Balance.LOOT.interact_*`, `Pickup.collect`, `Pickup.is_collectable`, the `pickups` / `loot_boxes` / `npcs` groups.
- Produces: `npc.surrender_weapon() -> Dictionary` (`{ "id": int, "total": int }`; leaves the NPC unarmed)
- Produces: contextual `interact` behavior on the shooter (server-side `_interact()`).

- [ ] **Step 1: Rename the input action in `project.godot`**

In `project.godot`, under `[input]`, rename the action `give_weapon_to_npc` to `interact` (keep the same `E` / `physical_keycode:69` event block). The block becomes:

```
interact={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":69,"key_label":0,"unicode":101,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Add `surrender_weapon()` to the NPC**

In `scenes/npc/npc_human.gd`, add after `receive_weapon` (after line 258):

```gdscript
## Hand the carried weapon back to the shooter. Returns {id, total} (id == -1
## if the NPC was unarmed) and leaves the NPC unarmed.
func surrender_weapon() -> Dictionary:
	var data := { "id": weapon_id, "total": weapon_total }
	weapon_id = -1
	weapon_mag = 0
	weapon_total = 0
	return data
```

- [ ] **Step 3: Swap the input dispatch + RPC in `shooter.gd`**

In `scenes/shooter/shooter.gd:_process`, replace the give line (136–137):

```gdscript
	if Input.is_action_just_pressed("interact"):
		_action_interact.rpc_id(1)
```

Replace the `_action_give` RPC (lines 162–165) with:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _action_interact() -> void:
	if multiplayer.is_server():
		_interact()
```

- [ ] **Step 4: Implement the server-side resolver `_interact()` in `shooter.gd`**

Add near the other server handlers (e.g. after `_give_weapon_to_npc`, ~line 388). This replaces the old standalone give as the only `interact` path:

```gdscript
## Contextual interact (server-side). Gathers every reachable interactable —
## dropped items, closed loot boxes, an adjacent following NPC to arm, or an
## armed NPC to disarm — then acts on the single nearest one (each type carries
## its own reach via Balance.LOOT, so a tight-radius give only wins point-blank).
func _interact() -> void:
	var origin := global_position
	var cands: Array = []
	var acts: Array = []  # parallel: ["pickup"|"box"|"give"|"take", node]

	for p in get_tree().get_nodes_in_group("pickups"):
		if not p.is_collectable():
			continue
		cands.append({ "pos": p.global_position, "radius": Balance.LOOT.interact_pickup_px })
		acts.append(["pickup", p])

	for b in get_tree().get_nodes_in_group("loot_boxes"):
		if b.opened:
			continue
		cands.append({ "pos": b.global_position, "radius": Balance.LOOT.interact_box_px })
		acts.append(["box", b])

	for n in get_tree().get_nodes_in_group("npcs"):
		if not (n is Node2D):
			continue
		if n.weapon_id != -1:
			cands.append({ "pos": n.global_position, "radius": Balance.LOOT.interact_take_px })
			acts.append(["take", n])
		elif held_special != -1 and "state" in n and n.state == 2:  # FOLLOWING
			cands.append({ "pos": n.global_position, "radius": Balance.LOOT.interact_give_px })
			acts.append(["give", n])

	var idx := Interact.choose_nearest(origin, cands)
	if idx == -1:
		return
	var act: Array = acts[idx]
	match act[0]:
		"pickup":
			act[1].collect(self)
		"box":
			act[1].open()
		"give":
			act[1].receive_weapon(held_special, special_total)
			_drop_special()
		"take":
			_take_weapon_from(act[1])


## Re-equip the weapon an NPC hands back, preserving its remaining ammo and
## dropping the player's current special first if it's a different gun.
func _take_weapon_from(npc: Node) -> void:
	var data: Dictionary = npc.surrender_weapon()
	if data["id"] == -1:
		return
	if held_special != -1 and held_special != data["id"]:
		_drop_special()
	give_special(data["id"])
	special_total = data["total"]
	special_mag = min(Weapons.get_data(data["id"]).mag_size, special_total)
```

- [ ] **Step 5: Remove the old `_give_weapon_to_npc` standalone (now folded in)**

In `scenes/shooter/shooter.gd`, delete the now-unused `_give_weapon_to_npc()` (lines 381–388) and `_find_following_npc()` (lines 397–402) if no other caller references them. Verify with: `grep -n "_give_weapon_to_npc\|_find_following_npc\|_action_give" scenes/shooter/shooter.gd` — expect no remaining references.

- [ ] **Step 6: Remove pickup auto-grab so collection is interact-only**

In `scenes/pickup/pickup.gd:_ready`, delete the `body_entered` connection and its handler so pickups are collected only via `collect()` from the resolver:

```gdscript
func _ready() -> void:
	_refresh_color()
	if spawn_origin != Vector2.ZERO:
		_play_burst()
```

Then delete the `_on_body_entered` function entirely (the `collect()` method stays).

- [ ] **Step 7: Re-run all headless tests (regression)**

Run both:
```
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_loot_table.gd
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_interact_pick.gd
```
Expected: both `ALL TESTS PASSED`.

- [ ] **Step 8: Manual verification via MCP**

`project_run` the game. Confirm via screenshots/logs:
- Walk onto a scattered pickup — it does **not** auto-grab; pressing `E` while standing on it collects it.
- Stand next to a following NPC at arm's length while near a pickup → `E` grabs the pickup, not the NPC give (tight give radius).
- Stand directly on top of a following NPC while holding a special → `E` gives the weapon.
- Press `E` on that now-armed NPC → the weapon returns to the shooter with its ammo, NPC disarmed.

- [ ] **Step 9: Commit**

```bash
git add project.godot scenes/shooter/shooter.gd scenes/npc/npc_human.gd scenes/pickup/pickup.gd
git commit -m "feat(loot): contextual interact resolver with NPC give/take-back, interact-grab pickups"
```

---

## Task 4: Loot box scene, world spawning, landing validation

**Files:**
- Create: `scenes/loot_box/loot_box.gd`, `scenes/loot_box/loot_box.tscn`
- Modify: `scenes/world/world.gd`
- Modify: `scenes/world/world.tscn` (`MultiplayerSpawner._spawnable_scenes`)

**Interfaces:**
- Consumes: `LootTable.roll_item_count`, `LootTable.roll_kind`, `LootTable.kind_weights`, `Pickup` (`kind`, `spawn_origin`), `Balance.LOOT.*`, `world.loot_landing_spot`, `world.entities`.
- Produces: `LootBox` scene in the `loot_boxes` group with `opened: bool` (replicated) and `open()` (server-only).
- Produces: `world.loot_landing_spot(center: Vector2, placed: Array) -> Vector2`

- [ ] **Step 1: Create `loot_box.gd`**

Create `scenes/loot_box/loot_box.gd`:

```gdscript
extends Node2D
class_name LootBox

## A closed crate. Pressing interact next to it (server-side) rolls 1-3 items
## and bursts them onto the floor as Pickup nodes. Replicated: clients see the
## sprite swap to opened and the items arrive via the MultiplayerSpawner.

const PICKUP_SCENE := preload("res://scenes/pickup/pickup.tscn")
const TEX_CLOSED := preload("res://sprites/Crate_closed.png")
const TEX_OPENED := preload("res://sprites/Crate_opened.png")

@export var opened: bool = false:
	set(value):
		opened = value
		_refresh_sprite()


func _ready() -> void:
	add_to_group("loot_boxes")
	_refresh_sprite()


func _refresh_sprite() -> void:
	var s := get_node_or_null("Sprite2D")
	if s:
		s.texture = TEX_OPENED if opened else TEX_CLOSED


## Server-only: roll and spawn loot, then mark opened (replicates the swap).
func open() -> void:
	if opened or not multiplayer.is_server():
		return
	opened = true
	var world := get_tree().current_scene
	var count := LootTable.roll_item_count(randf(), Balance.LOOT.chance_two, Balance.LOOT.chance_three)
	var weights := LootTable.kind_weights()
	var placed: Array[Vector2] = []
	for _i in range(count):
		var k := LootTable.roll_kind(randf(), weights)
		var target: Vector2 = world.loot_landing_spot(global_position, placed)
		placed.append(target)
		var p: Pickup = PICKUP_SCENE.instantiate()
		p.kind = k
		p.spawn_origin = global_position
		p.position = target
		world.entities.add_child(p, true)
```

- [ ] **Step 2: Create `loot_box.tscn`**

Create `scenes/loot_box/loot_box.tscn`:

```
[gd_scene load_steps=4 format=3 uid="uid://b8lootbox0001"]

[ext_resource type="Script" path="res://scenes/loot_box/loot_box.gd" id="1_lootbox"]
[ext_resource type="Texture2D" path="res://sprites/Crate_closed.png" id="2_crate"]

[sub_resource type="SceneReplicationConfig" id="SceneReplicationConfig_lb"]
properties/0/path = NodePath(".:position")
properties/0/spawn = true
properties/0/replication_mode = 0
properties/1/path = NodePath(".:opened")
properties/1/spawn = true
properties/1/replication_mode = 2

[node name="LootBox" type="Node2D" groups=["loot_boxes"]]
script = ExtResource("1_lootbox")

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2_crate")

[node name="MultiplayerSynchronizer" type="MultiplayerSynchronizer" parent="."]
replication_config = SubResource("SceneReplicationConfig_lb")
```

(`replication_mode = 2` = ON_CHANGE for `opened`, so the open-state swap streams to clients when the server flips it.)

- [ ] **Step 3: Register the scene with the `MultiplayerSpawner`**

In `scenes/world/world.tscn` line 211, append the loot box scene to `_spawnable_scenes`:

```
_spawnable_scenes = PackedStringArray("res://scenes/shooter/shooter.tscn", "res://scenes/zombie/zombie.tscn", "res://scenes/zombie/master_zombie.tscn", "res://scenes/zombie/fast_zombie.tscn", "res://scenes/zombie/fat_zombie.tscn", "res://scenes/npc/npc_human.tscn", "res://scenes/bullet/bullet.tscn", "res://scenes/pickup/pickup.tscn", "res://scenes/loot_box/loot_box.tscn")
```

- [ ] **Step 4: Replace `_spawn_items()` with `_spawn_loot_boxes()` in `world.gd`**

In `scenes/world/world.gd`, add the loot box preload near the others (after line 18):

```gdscript
var loot_box_scene := preload("res://scenes/loot_box/loot_box.tscn")
```

Change the spawn call in `_ready` (line 46) from `_spawn_items()` to `_spawn_loot_boxes()`.

Replace `_spawn_items()` (lines 181–203) with:

```gdscript
## Scatter closed loot boxes on walkable tiles, clear of buildings, props, the
## shooter spawn, and each other. Server-only; boxes replicate via the spawner.
func _spawn_loot_boxes() -> void:
	for _i in range(Balance.LOOT.box_count):
		var pos := _find_box_spawn()
		if pos == Vector2.INF:
			continue
		var b: Node2D = loot_box_scene.instantiate()
		b.position = pos
		entities.add_child(b, true)


## A walkable tile clear of the shooter spawn and of already-placed boxes.
func _find_box_spawn() -> Vector2:
	for _attempt in range(200):
		var pos := _find_item_spawn(false)
		if pos == Vector2.INF:
			return Vector2.INF
		var clear := true
		for b in get_tree().get_nodes_in_group("loot_boxes"):
			if b.global_position.distance_to(pos) < 96.0:
				clear = false
				break
		if clear:
			return pos
	return Vector2.INF


## Pick a valid landing point for a bursting item near `center`: walkable, not
## in a building, not on a prop/body, and burst_min_sep_px clear of `placed`.
## Falls back to the box center if no clear spot is found.
func loot_landing_spot(center: Vector2, placed: Array) -> Vector2:
	var radius: float = Balance.LOOT.burst_radius_px
	var min_sep: float = Balance.LOOT.burst_min_sep_px
	var space := get_world_2d().direct_space_state
	for _attempt in range(24):
		var ang := randf() * TAU
		var dist: float = max(sqrt(randf()) * radius, min_sep)
		var cand := center + Vector2.from_angle(ang) * dist
		if not _is_loot_tile(cand):
			continue
		var too_near := false
		for q in placed:
			if cand.distance_to(q) < min_sep:
				too_near = true
				break
		if too_near:
			continue
		# Reject if a physical body (prop/shooter/npc/zombie) sits on the point.
		var q := PhysicsPointQueryParameters2D.new()
		q.position = cand
		q.collision_mask = 1
		if not space.intersect_point(q, 1).is_empty():
			continue
		return cand
	return center


## True if `world_pos` is a walkable ground tile with no building over it.
func _is_loot_tile(world_pos: Vector2) -> bool:
	var walkable: Array[String] = ["road", "sidewalk", "grass", "parking"]
	var tile := ground_layer.local_to_map(ground_layer.to_local(world_pos))
	var td: TileData = ground_layer.get_cell_tile_data(tile)
	if td == null or not td.get_custom_data("tile_type") in walkable:
		return false
	if building_layer.get_cell_tile_data(tile) != null:
		return false
	return true
```

(`_find_item_spawn` stays — it's reused by `_find_box_spawn`.)

- [ ] **Step 5: Re-run all headless tests (regression)**

Run both Task 1 test files. Expected: both `ALL TESTS PASSED`.

- [ ] **Step 6: Manual verification via MCP**

`project_run` the game. Confirm via screenshots/logs:
- ~8 closed crates are scattered on walkable ground, none inside buildings or overlapping props/each other.
- Walk to a crate, press `E` → sprite swaps to opened, 1–3 items visibly **burst out** within ~1 tile and settle on walkable ground (none inside a building or on a tree/car).
- Press `E` on each landed item to collect it; HUD toasts fire (e.g. "+10 HP" for bandage).
- Re-pressing `E` on an opened crate does nothing.
- Over many opens, multi-item boxes are rare (~1 in 5 give 2, ~1 in 100 give 3) and bandages are the most common drop.

- [ ] **Step 7: Update docs**

Add a `CHANGELOG.md` line under the current date documenting the loot box system. If structure/status changed, update `ARCHITECTURE.md` (new `scenes/loot_box/`, `scripts/loot_table.gd`, `scripts/interact_pick.gd`, contextual interact) and `PROJECT.md` (loot status).

- [ ] **Step 8: Commit**

```bash
git add scenes/loot_box/ scenes/world/world.gd scenes/world/world.tscn \
        CHANGELOG.md ARCHITECTURE.md PROJECT.md
git commit -m "feat(loot): loot box scene, world spawning, and item-burst landing validation"
```

---

## Self-Review

**1. Spec coverage**

- 8 boxes, configurable → Task 1 (`Balance.LOOT.box_count`), Task 4 (`_spawn_loot_boxes`). ✓
- Boxes on walkable tiles, not in buildings, not on other boxes/items/props → Task 4 (`_find_box_spawn`, `_is_loot_tile`). ✓
- Closed/open sprites → Task 4 (`loot_box.gd` `_refresh_sprite`, `Crate_closed`/`Crate_opened`). ✓
- Open via interact; items burst within ~1 tile, animated → Task 3 (resolver `open()`), Task 4 (`open()` + `burst_radius_px`), Task 2 (`_play_burst`). ✓
- Landing validation (no building/prop/other item) → Task 4 (`loot_landing_spot`). ✓
- Item count 80/19/1 with `chance_two`/`chance_three` knobs → Task 1 (`roll_item_count` + tests). ✓
- Per-item weights, each its own balance var → Task 1 (`LOOT.weight_*`, `kind_weights`, `roll_kind`). ✓
- New BANDAGE kind, +10 HP; medpack +50; both render sprites → Task 1 (enum), Task 2 (sprites, heal, toast). ✓
- Contextual interact on `E`, nearest-wins, per-type radius → Task 1 (`Interact.choose_nearest`), Task 3 (`_interact`). ✓
- NPC give tight radius + reversible take-back → Task 3 (`interact_give_px`, `_take_weapon_from`, `surrender_weapon`). ✓
- All tuning in `balance.gd` → Task 1 (`LOOT` block). ✓
- Near-player special bias dropped → Task 4 (`_spawn_loot_boxes` uses `_find_item_spawn(false)`, no near bias). ✓

**2. Placeholder scan** — every code step contains complete code; no TBD/TODO. ✓

**3. Type consistency** — `Pickup.Kind.BANDAGE` added in Task 1 Step 4 and used consistently (`kind_weights`, `collect`, hud, balance heals). `collect(body)` / `is_collectable()` / `spawn_origin` defined in Task 2, consumed in Task 3/4. `surrender_weapon()` returns `{id, total}` in Task 3, consumed by `_take_weapon_from`. `loot_landing_spot(center, placed)` defined in Task 4, called by `loot_box.open()` in Task 4. `opened` property defined on `LootBox` (Task 4), read by resolver in Task 3 (group empty until Task 4 — safe). ✓

**Note on ordering:** Task 3's resolver references the `loot_boxes` group and `b.opened`/`b.open()` before the `LootBox` class exists (Task 4). This is safe because the group is empty until Task 4, and access is dynamic (duck-typed). Manual box verification therefore lands in Task 4, not Task 3.
