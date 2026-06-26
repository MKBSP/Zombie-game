# Phase 5 — Weapon Visuals Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Render the equipped weapon as a sprite on the player, on armed NPCs, on floor pickups, and in the HUD, from one shared weapon→texture map — static art, no animation.

**Architecture:** A `WeaponVisuals` helper maps each `Weapons.*` id to its PNG. The shooter and NPC each gain a `WeaponSprite` child whose texture follows the synced `equipped` / `weapon_id`; pickups swap their floor sprite to the weapon PNG; the HUD shows an icon.

**Tech Stack:** Godot 4.6 / GDScript, WebSocket multiplayer.

**Spec:** `docs/superpowers/specs/2026-06-26-weapon-visuals-design.md`

## Global Constraints

- `$GODOT` = `"/Applications/Godot 2.app/Contents/MacOS/Godot"`.
- Compile-check: `$GODOT --headless --editor --quit-after 400 --path . 2>&1 | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"` (expect none).
- Commits LOCAL ONLY. **No `Co-Authored-By` trailer** in commit messages.
- Art files (exact case): `sprites/Gun.png` `Shotgun.png` `Rifle.png` `Machinegun.png` `Club.png`. Mapping: PISTOL→Gun, SHOTGUN→Shotgun, RIFLE→Rifle, MACHINEGUN→Machinegun, MELEE→Club.
- Static sprites only — no firing/recoil/muzzle animation this phase. NPC gun shows but doesn't aim-track on clients.

---

## Task 1: Import PNGs + `WeaponVisuals` map

**Files:** Create `scripts/weapon_visuals.gd`, Test `test/test_weapon_visuals.gd`

**Interfaces — Produces:** `WeaponVisuals.texture(weapon_id: int) -> Texture2D` (the PNG, or `null`).

- [ ] **Step 1: Import the PNGs** — run the editor once so Godot imports the new PNGs (generates `.import` files):

```bash
"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --editor --quit-after 400 --path . >/dev/null 2>&1
ls sprites/*.png.import
```
Expected: `.import` files now exist for Gun/Shotgun/Rifle/Machinegun/Club.

- [ ] **Step 2: Write the failing test** — create `test/test_weapon_visuals.gd`:

```gdscript
extends SceneTree

var _failures := 0

func _init() -> void:
	_check("pistol has a texture", WeaponVisuals.texture(Weapons.PISTOL) != null)
	_check("machinegun has a texture", WeaponVisuals.texture(Weapons.MACHINEGUN) != null)
	_check("club for melee", WeaponVisuals.texture(Weapons.MELEE) != null)
	_check("unknown id is null", WeaponVisuals.texture(-1) == null)
	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)

func _check(label: String, cond: bool) -> void:
	if cond:
		print("PASS %s" % label)
	else:
		_failures += 1
		print("FAIL %s" % label)
```

- [ ] **Step 3: Run, expect fail** — `$GODOT --headless --path . --script test/test_weapon_visuals.gd 2>&1 | tail -6` → parse error, `WeaponVisuals` undeclared.

- [ ] **Step 4: Implement** — create `scripts/weapon_visuals.gd`:

```gdscript
extends RefCounted
class_name WeaponVisuals

## Single source of truth mapping a Weapons.* id to its sprite, so the equipped
## weapon renders the same on the player, NPCs, pickups, and the HUD.
static func texture(weapon_id: int) -> Texture2D:
	match weapon_id:
		Weapons.PISTOL:     return preload("res://sprites/Gun.png")
		Weapons.SHOTGUN:    return preload("res://sprites/Shotgun.png")
		Weapons.RIFLE:      return preload("res://sprites/Rifle.png")
		Weapons.MACHINEGUN: return preload("res://sprites/Machinegun.png")
		Weapons.MELEE:      return preload("res://sprites/Club.png")
	return null
```

- [ ] **Step 5: Register + run** — `$GODOT --headless --editor --quit-after 400 --path . >/dev/null 2>&1; $GODOT --headless --path . --script test/test_weapon_visuals.gd 2>&1 | grep -E "ALL TESTS PASSED|FAIL"` → `ALL TESTS PASSED` (a `FAIL` here means a filename/case mismatch).

- [ ] **Step 6: Commit** — `git add scripts/weapon_visuals.gd scripts/weapon_visuals.gd.uid test/test_weapon_visuals.gd sprites/*.png sprites/*.png.import && git commit -m "feat(visuals): WeaponVisuals texture map + import weapon PNGs"`

---

## Task 2: Gun on the player

**Files:** Modify `scenes/shooter/shooter.tscn`, `scenes/shooter/shooter.gd`

- [ ] **Step 1: Add the WeaponSprite node** — in `scenes/shooter/shooter.tscn`, add after the `Sprite2D` node block (it has no texture in the scene; it's set at runtime; mounted forward so it inherits the shooter's aim rotation):

```
[node name="WeaponSprite" type="Sprite2D" parent="." unique_id=918273645]
position = Vector2(16, 6)
```

- [ ] **Step 2: Refresh it from `equipped`** — in `scenes/shooter/shooter.gd`, add an `@onready` ref near the other node refs:

```gdscript
@onready var _weapon_sprite: Sprite2D = $WeaponSprite
```

Change the `equipped` declaration:

```gdscript
var equipped: int = Weapons.PISTOL
```

to a setter that refreshes the sprite:

```gdscript
var equipped: int = Weapons.PISTOL:
	set(value):
		equipped = value
		if _weapon_sprite:
			_weapon_sprite.texture = WeaponVisuals.texture(equipped)
```

And in `_ready()`, after the `@onready`s are live, add a first refresh (so the pistol shows from the start):

```gdscript
	_weapon_sprite.texture = WeaponVisuals.texture(equipped)
```

- [ ] **Step 3: Compile-check** — expect no output.

- [ ] **Step 4: Manual** — single-player → Human: a gun is drawn on the player and rotates as you aim; pressing 2 (after picking up a heavy) / 3 (melee) swaps the sprite; 1 returns to the pistol.

- [ ] **Step 5: Commit** — `git add scenes/shooter/shooter.tscn scenes/shooter/shooter.gd && git commit -m "feat(visuals): equipped gun sprite on the player"`

---

## Task 3: Weapon PNGs on floor pickups

**Files:** Modify `scenes/pickup/pickup.gd`

- [ ] **Step 1: Map weapon kinds to ids** — in `scenes/pickup/pickup.gd`, after the `WEAPON_TO_KIND` const, add:

```gdscript
## Inverse of WEAPON_TO_KIND for the floor sprite.
const KIND_TO_WEAPON := {
	Kind.RIFLE: Weapons.RIFLE,
	Kind.SHOTGUN: Weapons.SHOTGUN,
	Kind.MACHINEGUN: Weapons.MACHINEGUN,
	Kind.MELEE: Weapons.MELEE,
}
```

- [ ] **Step 2: Show the weapon PNG** — replace `_refresh_color`:

```gdscript
func _refresh_color() -> void:
	var s := get_node_or_null("Sprite2D")
	if s == null:
		return
	if KIND_TO_WEAPON.has(kind):
		s.texture = WeaponVisuals.texture(KIND_TO_WEAPON[kind])
		s.modulate = Color.WHITE
	else:
		s.modulate = COLORS.get(kind, Color.WHITE)
```

(Ammo-mag / medpack fall through and keep their tinted square.)

- [ ] **Step 3: Compile-check** — expect no output.

- [ ] **Step 4: Manual** — the rifle/shotgun/MG/club pickups on the floor now show their PNGs; ammo/medpack are still squares.

- [ ] **Step 5: Commit** — `git add scenes/pickup/pickup.gd && git commit -m "feat(visuals): weapon PNGs on floor pickups"`

---

## Task 4: HUD weapon icon

**Files:** Modify `scenes/world/world.tscn`, `scenes/ui/hud.gd`

- [ ] **Step 1: Add the icon node** — in `scenes/world/world.tscn`, add a `WeaponIcon` under `HUDLayer/HUD` (after the `AmmoLabel` block):

```
[node name="WeaponIcon" type="TextureRect" parent="HUDLayer/HUD"]
layout_mode = 0
offset_left = 330.0
offset_top = 46.0
offset_right = 378.0
offset_bottom = 78.0
expand_mode = 1
stretch_mode = 5
```

- [ ] **Step 2: Drive it from equipped** — in `scenes/ui/hud.gd`, add the ref:

```gdscript
@onready var weapon_icon: TextureRect = $WeaponIcon
```

and at the end of `_update_ammo()`, set it:

```gdscript
	if weapon_icon:
		weapon_icon.texture = WeaponVisuals.texture(shooter.equipped)
```

- [ ] **Step 3: Compile-check** — expect no output.

- [ ] **Step 4: Manual** — the HUD shows the equipped weapon's icon next to the ammo text and updates on 1/2/3.

- [ ] **Step 5: Commit** — `git add scenes/world/world.tscn scenes/ui/hud.gd && git commit -m "feat(visuals): HUD weapon icon"`

---

## Task 5: Gun on armed NPCs

**Files:** Modify `scenes/npc/npc_human.tscn`, `scenes/npc/npc_human.gd`

- [ ] **Step 1: Add the WeaponSprite + sync weapon_id** — in `scenes/npc/npc_human.tscn`, add a `WeaponSprite` child (start hidden):

```
[node name="WeaponSprite" type="Sprite2D" parent="."]
position = Vector2(16, 0)
visible = false
```

and add `weapon_id` to the `SceneReplicationConfig_sync` block (after `properties/3`):

```
properties/4/path = NodePath(".:weapon_id")
properties/4/spawn = true
properties/4/replication_mode = 2
```

- [ ] **Step 2: Refresh on weapon_id change** — in `scenes/npc/npc_human.gd`, add the ref near the other `@onready`s:

```gdscript
@onready var _weapon_sprite: Sprite2D = $WeaponSprite
```

Change the `weapon_id` declaration:

```gdscript
var weapon_id: int = -1
```

to a setter:

```gdscript
var weapon_id: int = -1:
	set(value):
		weapon_id = value
		if _weapon_sprite:
			_weapon_sprite.visible = value != -1
			if value != -1:
				_weapon_sprite.texture = WeaponVisuals.texture(value)
```

(The NPC only ever receives firearms, so `WeaponVisuals.texture` always resolves.)

- [ ] **Step 3: Compile-check** — expect no output.

- [ ] **Step 4: Manual** — hand an NPC a weapon (give-to-NPC): it shows that gun; an unarmed NPC shows none. In a 2-window session the gun appears on both peers.

- [ ] **Step 5: Commit** — `git add scenes/npc/npc_human.tscn scenes/npc/npc_human.gd && git commit -m "feat(visuals): gun sprite on armed NPCs (synced)"`

---

## Task 6: Verification

- [ ] **Step 1: Compile + all unit tests** —
```bash
$GODOT --headless --editor --quit-after 400 --path . 2>&1 | grep -iE "SCRIPT ERROR|Compile Error|Parse Error|Failed to load"
for t in aim_model npc_aim melee weapon_visuals; do echo -n "$t: "; $GODOT --headless --path . --script test/test_$t.gd 2>&1 | grep -E "ALL TESTS PASSED|FAIL"; done
```
Expected: no grep output; four `ALL TESTS PASSED`.

- [ ] **Step 2: Visual pass (godot-ai MCP)** — run, Single Player → Human; screenshot and confirm: gun on the player rotating with aim; 1/2/3 swaps it (Gun / heavy PNG / Club); floor pickups show their PNGs; HUD icon matches; give a weapon to an NPC and see its gun.

- [ ] **Step 3: Final commit if tweaks** — `git add -A && git commit -m "fix(visuals): mount/scale tweaks"`

---

## Self-Review notes (author)

- **Spec coverage:** single texture map (T1), player gun rotating with aim + swap (T2), floor pickups (T3), HUD icon (T4), NPC gun synced via `weapon_id` (T5). All covered.
- **MP:** `equipped` already synced drives the player gun + HUD on both peers via the setter; `weapon_id` newly synced drives the NPC gun. Textures resolve locally from ids — no texture data on the wire.
- **Type consistency:** `WeaponVisuals.texture(id)` used by shooter, pickup, hud, npc; setters on `equipped` / `weapon_id` guard the null `@onready` during spawn and re-refresh in `_ready`.
- **Deferred:** no animation; NPC gun is static (no per-frame aim); ammo/medpack stay squares.
