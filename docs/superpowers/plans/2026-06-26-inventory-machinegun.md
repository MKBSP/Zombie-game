# Shooting Phase 4a — Inventory Selection + Machine Gun Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the swap-toggle with direct 1/2/3 weapon selection (pistol / heavy / melee slots) and add a full-auto machine gun as a new heavy weapon you can pick up and spray.

**Architecture:** Today's "special" slot already *is* the heavy slot; this adds a (still-empty) melee slot and number-key selection on top, and registers the machine gun as another heavy under the existing `Weapons`/`Balance`/pickup pattern. Melee combat itself is Plan 2.

**Tech Stack:** Godot 4.6 / GDScript, WebSocket multiplayer, MultiplayerSynchronizer/Spawner.

**Spec:** `docs/superpowers/specs/2026-06-26-inventory-melee-machinegun-design.md` (this is Milestones A + B of that spec; Milestone C = Plan 2).

## Global Constraints

- Godot binary: `"/Applications/Godot 2.app/Contents/MacOS/Godot"` (called `$GODOT` below).
- **Compile-check** (expects NO matching lines):
  ```bash
  "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
    | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
  ```
- **Commits are LOCAL ONLY. Never `git push`.** The user pushes to GitHub themselves.
- Three slots: **pistol** (permanent, slot 1) · **heavy** (slot 2: rifle/shotgun/MG) · **melee** (slot 3, stays empty until Plan 2). Selecting an empty slot is a no-op.
- Pistol is never dropped or replaced. Give-to-NPC stays heavy-only.
- All weapon state changes run server-side; the HUD reads synced state. Tuning lives in `Balance`.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `project.godot` (Input Map) | `select_pistol`/`select_heavy`/`select_melee` (1/2/3) | Modify |
| `scenes/shooter/shooter.gd` | melee slot var; 1/2/3 selection RPC | Modify |
| `scripts/balance.gd` | `MACHINEGUN` stat block | Modify |
| `scripts/weapons.gd` | `MACHINEGUN` enum + `get_data` | Modify |
| `scenes/pickup/pickup.gd` | `MACHINEGUN` pickup kind + swap-drop mapping | Modify |
| `scenes/shooter/shooter.gd` (`give_special`) | MG pickup-notify kind | Modify |
| `scenes/world/world.gd` (`_spawn_items`) | spawn an MG pickup | Modify |

---

## Task 1: Number-key selection input actions

**Files:**
- Modify: `project.godot` (Input Map)

- [ ] **Step 1: Add the three actions**

In the Godot editor: **Project → Project Settings → Input Map**, add three actions and bind each to a key:
- `select_pistol` → key **1**
- `select_heavy` → key **2**
- `select_melee` → key **3**

(Or, via the godot-ai MCP, `input_map_manage` `add_action` for each name, then `bind_event` to physical keycodes 49 / 50 / 51.)

- [ ] **Step 2: Compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
  | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
```
Expected: no output. Also confirm the three actions exist: `grep -c "select_pistol\|select_heavy\|select_melee" project.godot` → `3`.

- [ ] **Step 3: Commit (local only)**

```bash
git add project.godot
git commit -m "feat(inventory): select_pistol/heavy/melee (1/2/3) input actions"
```

---

## Task 2: Three-slot selection on the shooter

**Files:**
- Modify: `scenes/shooter/shooter.gd`

**Interfaces:**
- Consumes: the `select_*` actions (Task 1).
- Produces: `held_melee` slot var (server-side, -1 = empty); `_action_select(slot)` RPC and `_select_slot(slot)` where slot 0=pistol, 1=heavy, 2=melee.

- [ ] **Step 1: Add the melee slot var**

In `scenes/shooter/shooter.gd`, after `var held_special: int = -1`, add:

```gdscript
## The melee slot: Weapons.MELEE when held, or -1 (empty). Populated in Plan 2.
var held_melee: int = -1
```

- [ ] **Step 2: Swap the input handlers to 1/2/3 selection**

Replace this block in `_process`:

```gdscript
	# Discrete one-shot weapon actions
	if Input.is_action_just_pressed("swap_weapon"):
		_action_swap.rpc_id(1)
	if Input.is_action_just_pressed("drop_weapon"):
		_action_drop.rpc_id(1)
	if Input.is_action_just_pressed("give_weapon_to_npc"):
		_action_give.rpc_id(1)
```

with:

```gdscript
	# Discrete one-shot weapon actions
	if Input.is_action_just_pressed("select_pistol"):
		_action_select.rpc_id(1, 0)
	if Input.is_action_just_pressed("select_heavy"):
		_action_select.rpc_id(1, 1)
	if Input.is_action_just_pressed("select_melee"):
		_action_select.rpc_id(1, 2)
	if Input.is_action_just_pressed("drop_weapon"):
		_action_drop.rpc_id(1)
	if Input.is_action_just_pressed("give_weapon_to_npc"):
		_action_give.rpc_id(1)
```

- [ ] **Step 3: Replace the swap RPC/function with slot selection**

Replace the `_action_swap` RPC:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _action_swap() -> void:
	if multiplayer.is_server():
		_swap_weapon()
```

with:

```gdscript
@rpc("any_peer", "call_local", "reliable")
func _action_select(slot: int) -> void:
	if multiplayer.is_server():
		_select_slot(slot)
```

and replace the `_swap_weapon` function:

```gdscript
func _swap_weapon() -> void:
	if held_special == -1:
		return
	_cancel_reload()
	equipped = held_special if equipped == Weapons.PISTOL else Weapons.PISTOL
```

with:

```gdscript
## Equip slot 0=pistol, 1=heavy, 2=melee. Empty slots are a no-op.
func _select_slot(slot: int) -> void:
	var target := -1
	match slot:
		0: target = Weapons.PISTOL
		1: target = held_special
		2: target = held_melee
	if target == -1 or target == equipped:
		return
	_cancel_reload()
	equipped = target
```

- [ ] **Step 4: Compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
  | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
```
Expected: no output.

- [ ] **Step 5: Manual sanity (editor / godot-ai MCP)**

Single-player → Human. Press **1** (pistol) — fires pistol. Pick up a rifle/shotgun, press **2** — equips it; **1** returns to pistol. **3** does nothing (no melee yet). Drop/give still work.

- [ ] **Step 6: Commit (local only)**

```bash
git add scenes/shooter/shooter.gd
git commit -m "feat(inventory): 1/2/3 slot selection + empty melee slot"
```

---

## Task 3: Machine gun weapon

**Files:**
- Modify: `scripts/balance.gd`
- Modify: `scripts/weapons.gd`

**Interfaces:**
- Produces: `Weapons.MACHINEGUN` enum id; `Balance.MACHINEGUN` stat dict; `get_data(Weapons.MACHINEGUN)` returns its `WeaponData`.

- [ ] **Step 1: Add the Balance block**

In `scripts/balance.gd`, after the `const SHOTGUN := { ... }` block (before `# --- Headshots`), add:

```gdscript
const MACHINEGUN := {
	display_name = "Machine Gun", damage = 22.0, cooldown = 0.08, mag_size = 40,
	reload_time = 4.0, pellets = 1, bullet_speed = 1300.0, is_special = true, total_ammo = 120,
	aim_base = 0.14, aim_max = 0.40, focus_min_scale = 0.8,
	optimal_range_px = 512.0, zero_range_px = 700.0,
}
```

- [ ] **Step 2: Add MACHINEGUN to the enum + get_data**

In `scripts/weapons.gd`, change the enum:

```gdscript
enum { PISTOL, RIFLE, SHOTGUN }
```

to:

```gdscript
enum { PISTOL, RIFLE, SHOTGUN, MACHINEGUN }
```

and add a branch to `get_data`'s match (before the `_:` default):

```gdscript
		MACHINEGUN: src = Balance.MACHINEGUN
```

- [ ] **Step 3: Compile-check**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 \
  | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
```
Expected: no output.

- [ ] **Step 4: Commit (local only)**

```bash
git add scripts/balance.gd scripts/weapons.gd
git commit -m "feat(weapons): full-auto machine gun (heavy)"
```

---

## Task 4: Machine gun pickup

**Files:**
- Modify: `scenes/pickup/pickup.gd`
- Modify: `scenes/shooter/shooter.gd` (`give_special` notify kind)
- Modify: `scenes/world/world.gd` (`_spawn_items`)

**Interfaces:**
- Consumes: `Weapons.MACHINEGUN` (Task 3); the existing `give_special` / `_take_special` heavy path.
- Produces: `Pickup.Kind.MACHINEGUN`.

- [ ] **Step 1: Add the pickup kind**

In `scenes/pickup/pickup.gd`, change the enum:

```gdscript
enum Kind { AMMO_MAG, RIFLE, SHOTGUN, MEDPACK }
```

to:

```gdscript
enum Kind { AMMO_MAG, RIFLE, SHOTGUN, MEDPACK, MACHINEGUN }
```

Add to `COLORS`:

```gdscript
	Kind.MACHINEGUN: Color(0.6, 0.6, 0.65),
```

Add to `WEAPON_TO_KIND`:

```gdscript
	Weapons.MACHINEGUN: Kind.MACHINEGUN,
```

Add a case in `_on_body_entered`'s match (alongside RIFLE/SHOTGUN):

```gdscript
		Kind.MACHINEGUN:
			_take_special(body, Weapons.MACHINEGUN)
```

- [ ] **Step 2: Fix the pickup-notify kind for the MG**

In `scenes/shooter/shooter.gd` `give_special`, replace the last line:

```gdscript
	_notify_pickup(Pickup.Kind.RIFLE if weapon_id == Weapons.RIFLE else Pickup.Kind.SHOTGUN)
```

with:

```gdscript
	var kind := Pickup.Kind.RIFLE
	if weapon_id == Weapons.SHOTGUN:
		kind = Pickup.Kind.SHOTGUN
	elif weapon_id == Weapons.MACHINEGUN:
		kind = Pickup.Kind.MACHINEGUN
	_notify_pickup(kind)
```

- [ ] **Step 3: Spawn an MG pickup in the world**

In `scenes/world/world.gd` `_spawn_items()`, add one MG pickup near where the rifle/shotgun spawn. Find the existing special-weapon spawn (a `Pickup.Kind.RIFLE` / `SHOTGUN` instantiation) and add an analogous one for `Pickup.Kind.MACHINEGUN` (same pattern: instantiate `pickup_scene`, set `kind = Pickup.Kind.MACHINEGUN`, position it on a walkable near-player tile, `entities.add_child(p, true)`). Match the surrounding code's exact spawn helper.

- [ ] **Step 4: Compile-check + manual**

Compile-check (expect no output). Single-player → Human: a grey MG pickup exists; walk over it, press **2**, hold fire — it sprays full-auto and burns its 40-round mag, then reloads. Picking up a second heavy swaps and drops the old one.

- [ ] **Step 5: Commit (local only)**

```bash
git add scenes/pickup/pickup.gd scenes/shooter/shooter.gd scenes/world/world.gd
git commit -m "feat(weapons): machine-gun pickup + world spawn"
```

---

## Task 5: Verification

**Files:** none.

- [ ] **Step 1: Compile-check + existing unit tests**

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . 2>&1 | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_aim_model.gd 2>&1 | tail -2
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_npc_aim.gd 2>&1 | tail -2
```
Expected: no grep output; both `ALL TESTS PASSED`.

- [ ] **Step 2: Single-player feel pass**

1/2/3 selects pistol/heavy/(empty melee = no-op); MG sprays full-auto, reloads, and obeys range falloff + headshots like any bullet; pick-up swap drops the old heavy; drop + give-to-NPC still work.

- [ ] **Step 3: Multiplayer pass**

Two windows: selecting slots, MG fire, and the equipped-weapon HUD readout replicate on the human client.

- [ ] **Step 4: Final commit (local only, if tweaks)**

```bash
git add -A
git commit -m "test(inventory): Phase 4a verification tweaks"
```

---

## Self-Review notes (author)

- **Spec coverage (Milestones A+B):** typed slots + 1/2/3 selection (T1/T2), empty melee slot plumbed (T2), MG as a full-auto heavy under the existing model (T3) with pickup + swap-drop + world spawn (T4), give-to-NPC stays heavy-only (unchanged), pistol permanent (T2 never targets a droppable pistol). Melee combat = Plan 2.
- **Non-breakage:** the heavy slot reuses the existing `held_special`/`special_mag`/`special_total` machinery, so shoot/reload/HUD/sync are untouched; MG simply flows through it. `equipped` is never melee in this plan (held_melee stays -1), so `shoot()`/`_current_mag()` paths are safe.
- **Type consistency:** `_select_slot(slot)` with 0/1/2 matches `_action_select` and the three input handlers; `Weapons.MACHINEGUN` used in weapons.gd, pickup.gd, shooter.gd; `Pickup.Kind.MACHINEGUN` in pickup.gd + shooter notify + world spawn.
- **Deferred to Plan 2:** the `MELEE` weapon, `held_melee` population + sync, melee swing/fatigue, aim-cursor hide, melee pickup.
