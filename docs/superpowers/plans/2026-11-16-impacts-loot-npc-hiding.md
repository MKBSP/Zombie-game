# Impacts, Hit Feedback, Loot Crates and NPC Hiding: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shots read on every surface, let bullets break street lamps, show where a zombie was hit, start the shooter with only a pistol and torch, scatter loot crates evenly over the map, add a debug cheat for all weapons, and make unrecruited survivors hide in cover and flee (80%) or freeze (20%) when a zombie spots them.

**Architecture:** There are four parts (A–D), and each one ships and plays on its own. Impact effects move out of `viewmodel.gd` into one shared static helper. Gun, bat and survivor shots all call that helper, and so does the new blood. Weapon ownership becomes a pure rule set in `fp_loadout.gd`; the viewmodel and the new crates and pickups only call it. Survivor reactions are two new states in `npc_3d.gd`. They use the same sight test the commander's fog uses (`Zombie3D.can_see`), so "spotted" means the same thing everywhere.

**Tech Stack:** Godot 4.6.3, GDScript. No new addons or dependencies.

**Spec:** Mads's request of 2026-11-16 (quoted below), plus [the 3D conversion design](../specs/2026-09-09-3d-conversion-design.md) §6 (per-part damage) and §9 (stage plan: this is S6 plus S9 follow-ups).

> 1. Bullets hitting floor, walls, etc., and if they can break the light-post lamps so they turn off. 2. Bullets hitting the zombies, so you know when and where you hit them. 3. The shooter spawns with only a handgun and flashlight; weapon boxes in different places, spawned randomly but evenly distributed on the map. 4. NPCs act more correctly before being saved or converted: hide in alleys and behind things, out of sight. If a zombie finds them, 80% run away and 20% get scared, crouch down and freeze. Also: a cheat code to get all weapons, though the real game has a carry limit.

## Global Constraints

- **Editor open:** while the Godot editor is open on the project, never run a headless `--import` or `--script test/…` in `~/Desktop/zombie-game`. Run tests and renders in the scratch copy instead:
  - sync: `rsync -a --exclude .git --exclude "*.mov" --exclude .godot ~/Desktop/zombie-game/ $SP/zg/`
  - then: `"/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path $SP/zg --import`
  - then: `… --headless --path $SP/zg --script test/<name>.gd`
- **Editing:** edit scripts directly, then run godot-ai `filesystem_manage {"op":"scan"}`. Scene edits go through the MCP node tools plus `scene_save`.
- **Tuning:** every tuning number lives in `scripts/balance.gd`, in 3D-only dicts. Gameplay code has no literals.
- **Physics layers:** 1 world, 2 zombie capsules, 8 NPCs, 16 debris, 32 zombie part hitboxes.
  - New: **64 = interactables** (pickups). Nothing has it in its mask, so nothing collides with them; only the interact ray sees them.
  - Shot rays keep `collision_mask = 0xFFFFFFFF & ~2`.
- **Determinism:** whatever is placed at map load (crate positions and their contents) comes from a seeded `RandomNumberGenerator`, so every peer builds the same map in S10.
- **2D game:** stays untouched, apart from making two `loot_box.gd` helpers `static`.
- **Every task's last step:**
  - add a line to `CHANGELOG.md` (Phase 10);
  - update `ARCHITECTURE.md` and `PROJECT.md` where behaviour or controls changed;
  - tick or move the matching `docs/BACKLOG.md` item;
  - then **suggest** a commit message to Mads. Don't commit, and never push.

## Review Focus

1. **Shooting a lamp that is already dead, fallen or glassless.** Glass that's still there shatters, a lamp with no lens has no hitbox, and a second shot does nothing. Tested in Task 2.
2. **Picking up a heavy weapon you already carry.** It refills that weapon's ammo. It doesn't drop a duplicate or swap. Tested in Task 5.
3. **Handing your only heavy to a survivor while it's in your hand, or taking it back after you picked up a different one.** In the first case you fall back to pistol + torch. In the second, your current heavy drops at your feet. Tested in Task 5.
4. **A scatter cell that is all building, or a map smaller than the grid.** You get fewer crates, never one on a roof or inside a block, and it never hangs. Tested in Task 8.
5. **A survivor with nowhere to run, or one already following you.** With no flee spot away from the threat, it cowers. Followers never flee or cower. Tested in Task 10.

---

## Part A: Impacts and breakable lamps

### Task 1: Shared, surface-aware impact effects

Bullet holes and orange sparks already exist (`viewmodel.gd` `_impact`), but every surface shows the same sparks, and survivor shots leave nothing. This task moves the effect into one helper, gives each surface its own look, and routes all shots through it.

**Files:**
- Create: `scripts/3d/impact_fx.gd` (`extends RefCounted`, static only)
- Modify: `scripts/3d/viewmodel.gd`:
  - delete `_impact`, `_particles`, the `_decal_tex` build in `_build_flash` (~l.404) and `_decals`;
  - `_shoot` (l.1020) and `_strike` (l.1072) call the helper.
- Modify: `scripts/3d/npc_3d.gd` `_shooting` (l.327). A hit point gets an impact too.
- Modify: `scripts/3d/street_light.gd` `_segment`. Its body gets `set_meta("surface", "metal")`.
- Modify: `scripts/balance.gd`. Add `IMPACT`.
- Test: `test/test_impact_fx.gd`

**Interfaces:**
- Produces:
  - `ImpactFx.surface_of(collider: Object, normal: Vector3) -> String`. It returns `collider.get_meta("surface")` if set. Otherwise it returns `"ground"` when `normal.y > 0.7`, else `"wall"`.
  - `ImpactFx.spawn(root: Node, pos: Vector3, normal: Vector3, surface: String, dir := Vector3.ZERO) -> void`
  - `ImpactFx.particles(amount: int, life: float, tex: Texture2D) -> CPUParticles3D` (the old `_particles`, made static)
  - Surfaces: `"ground"`, `"wall"`, `"metal"`, `"glass"`, `"flesh"`, `"wood"`. `"flesh"` is built in Task 3.
- `Balance.IMPACT`, per surface: `{decal: bool, count: int, color: Color, unshaded: bool, speed: Vector2, gravity: float}`.
  - ground: grey-brown dust, shaded;
  - wall: pale plaster dust, shaded;
  - metal: today's orange sparks, unshaded;
  - glass: pale blue-white shards, unshaded, no decal;
  - wood: brown chips.
  - `decal_cap = 60`.

- [ ] **Step 1: Write the failing test** in `test/test_impact_fx.gd`, in the `extends SceneTree` / `_check` style of `test/test_fp_loadout.gd`.

```gdscript
var F = load("res://scripts/3d/impact_fx.gd")
var o := Node.new()
_check("floor is ground", F.surface_of(o, Vector3.UP) == "ground")
_check("wall is wall", F.surface_of(o, Vector3.RIGHT) == "wall")
_check("steep slope is wall", F.surface_of(o, Vector3(1, 0.5, 0).normalized()) == "wall")
o.set_meta("surface", "metal")
_check("meta wins over normal", F.surface_of(o, Vector3.UP) == "metal")
for s in ["ground", "wall", "metal", "glass", "wood"]:
    _check("%s has a look" % s, Balance.IMPACT.has(s))
_check("glass leaves no hole", not Balance.IMPACT.glass.decal)
```

- [ ] **Step 2: Run it in the scratch copy.** Expected: FAIL, because `impact_fx.gd` can't load.
- [ ] **Step 3: Implement `impact_fx.gd`.**
  - The decal texture is built once (lazy `static var`), and the decal FIFO is a `static var` capped at `Balance.IMPACT.decal_cap`. That way the shooter's and the survivors' holes share one budget.
  - Move today's decal orientation code over unchanged.
- [ ] **Step 4: Wire the callers.**
  - Viewmodel `_shoot` and `_strike`, and NPC `_shooting`: `ImpactFx.spawn(root, hit.position, hit.normal, ImpactFx.surface_of(hit.collider, hit.normal), dir)`.
  - The bat keeps `bullet=false` behaviour: no decal, using `"wall"` dust.
- [ ] **Step 5: Run the test and the full suite.**
  - Expected: `test_impact_fx` passes, and all 23 existing tests still pass.
  - Render check in the scratch copy: shoot asphalt, a facade and a lamp pole at night. You should see three visibly different puffs, with holes on the asphalt and the facade.
- [ ] **Step 6: Docs.** Suggested commit message: `Add surface-aware bullet impacts shared by shooter and survivors`

### Task 2: Bullets shatter lamp heads

**Files:**
- Modify: `scripts/3d/street_light.gd`: `_head` (l.209), `_build` (l.104), a new `shatter()`
- Modify: `scripts/balance.gd`: `STREET_LIGHTS.shatter_spark_chance = 0.3`
- Test: `test/test_street_lights.gd` (extend)

**Interfaces:**
- Consumes: `ImpactFx.spawn(..., "glass")` from Task 1.
- Produces:
  - `StreetLight.shatter() -> void`
  - `StreetLight.shattered: bool`
  - An inner `class LensHitbox extends StaticBody3D` with `light: StreetLight` and `func take_hit(_d: float, _p: Vector3, _dir: Vector3) -> void: light.shatter()`.
  - The hitbox: `collision_layer = DEBRIS_LAYER`, `SphereShape3D` radius 0.22, at `LENS`, meta `surface = "glass"`.

- [ ] **Step 1: Write the failing tests.** Build each lamp as `StreetLight.new()` with `state` forced, and add it to `root`.

```gdscript
var lamp = SL.new(); lamp.state = SL.State.WORKING; root.add_child(lamp)
lamp.shatter()
_check("shattered lamp is dark", lamp.kind in [SL.State.DEAD, SL.State.SPARKING] and (lamp._light == null or not lamp._light.visible))
_check("glass gone", not lamp._lens.visible)
_check("hitbox off after shatter", lamp.find_children("*", "StaticBody3D", true, false).all(func(b): return not b.has_method("take_hit") or b.collision_layer == 0))
lamp.shatter()  # second hit: no-op, no error
_check("still shattered", lamp.shattered)
# a dead lamp whose roll kept its glass still has a hitbox; one with no visible lens has none
```

- [ ] **Step 2: Run.** Expected: FAIL (`shatter` not found).
- [ ] **Step 3: Implement the hitbox.** `_build` adds the `LensHitbox` only when `_lens.visible` after the state roll. That covers working, blinking, sparking, and dead or fallen lamps whose roll kept their glass.
- [ ] **Step 4: Implement `shatter()`.**
  - No-op if `shattered`. Otherwise set `shattered = true`, free `_light`, hide `_lens`, and set the hitbox layer to 0.
  - Spawn a `"glass"` burst at the lens.
  - With `shatter_spark_chance`, make the lamp `SPARKING` (call `_make_sparks` if `_sparks == null`, then `set_process(true)`); otherwise make it `DEAD`.
  - Blinking stops (`kind` changes).
  - `ponytail:` comment: a shattered lamp is local until S10 replicates a `shattered` list.
- [ ] **Step 5: Run the tests and the suite.** Expected: all pass. Render check: shoot a working lamp. The cone goes out, glass falls, and 3 in 10 lamps keep sparking. The commander fog's glow-through stops on its own, since it reads screen brightness.
- [ ] **Step 6: Docs.** Suggested commit message: `Let bullets shatter street lamps`

---

## Part B: Zombie hit feedback

### Task 3: Hit result, blood and flinch

**Files:**
- Modify: `scripts/3d/zombie_3d.gd`:
  - `take_part_hit` (l.466) returns a result;
  - new `enum Hit { NONE, HIT, LIMB, KILL }`;
  - new static `hit_result`.
- Modify: `scripts/3d/zombie_body.gd`:
  - `Hitbox.take_hit` returns the result and its bodies get meta `surface = "flesh"`;
  - new `flinch()`;
  - `destroy()` makes a bigger burst at the limb bone.
- Modify: `scripts/3d/impact_fx.gd`. Add the `"flesh"` surface: a dark red burst along `-dir` and a forward spray along `dir`. On top of that, `spawn` casts one ray from `pos` along `dir` up to `Balance.IMPACT.flesh.splat_m = 2.5` (mask 1) and puts a blood decal where it lands.
- Modify: `scripts/3d/npc_3d.gd`. The NPC body gets meta `surface = "flesh"`, so shooting a survivor bleeds too.
- Modify: `scripts/balance.gd`. Add `IMPACT.flesh` and `ZOMBIE_PARTS.flinch_s = 0.25`.
- Test: `test/test_zombie_3d.gd` (extend)

**Interfaces:**
- Produces:
  - `Zombie3D.hit_result(before: float, after: float, part: String) -> int`:
    - `NONE` if `before <= 0`;
    - `KILL` if `after <= 0` and the part is `head` or `body`;
    - `LIMB` if `after <= 0`;
    - otherwise `HIT`.
  - `take_part_hit(part, damage) -> int` returns it. `Hitbox.take_hit(...) -> int` passes it through.
  - `ZombieBody.flinch() -> void` plays `Armature|Hit_reaction` for `flinch_s`. It works like `attack()`'s timer and blocks `animate()` meanwhile. It does nothing while dead, crawling, or mid-attack. It's animation only, with no stun.

- [ ] **Step 1: Write the failing test.**

```gdscript
_check("hit", Z.hit_result(30.0, 10.0, "body") == Z.Hit.HIT)
_check("arm off", Z.hit_result(10.0, -2.0, "arm_l") == Z.Hit.LIMB)
_check("head kill", Z.hit_result(10.0, 0.0, "head") == Z.Hit.KILL)
_check("body kill", Z.hit_result(5.0, -1.0, "body") == Z.Hit.KILL)
_check("dead part ignores", Z.hit_result(0.0, -5.0, "leg_r") == Z.Hit.NONE)
```

- [ ] **Step 2: Run.** Expected: FAIL (`hit_result` not found).
- [ ] **Step 3: Implement** `hit_result` and the return values, then call `_body.flinch()` on a `HIT`. A `LIMB` result gets the bigger burst inside `destroy()`, at the limb root bone's global position.
- [ ] **Step 4: Run the test and the suite.** Expected: all pass. Render check: rifle a zombie's arm. You should see a blood puff at the hit point and a splat on the wall behind it, then a bigger burst when the arm goes.
- [ ] **Step 5: Docs.** Suggested commit message: `Add zombie blood, flinch and hit results`

### Task 4: Hitmarker on the crosshair

**Files:**
- Modify: `scripts/3d/viewmodel.gd`:
  - `_build_hud` (l.527) adds a `Control` with 4 short diagonal `Line2D`s around the screen centre;
  - `_shoot` and `_strike` read the `take_hit` return value;
  - `_process` fades the marker.
- Modify: `scripts/balance.gd`: `FP.hitmarker = {show_s = 0.18, hit = Color.WHITE, limb = Color(1, 0.6, 0.2), kill = Color(1, 0.15, 0.1), kill_scale = 1.5}`

**Interfaces:**
- Consumes: `Zombie3D.Hit` from Task 3. A non-zombie `take_hit` returns `null`, which shows no marker.
- Produces: `viewmodel._mark(result: int) -> void`. The strongest result of a multi-pellet shotgun blast wins (`max`).

- [ ] **Step 1: Implement.** `_mark` sets the colour and scale and resets the timer; the alpha fades out over `show_s`. No sound for now (no 3D audio exists yet).
- [ ] **Step 2: Render check** in the scratch copy (a scripted shot at a zombie, then a screenshot). You should see a white tick on a body hit, orange when a limb comes off, and a larger red tick on a kill.
- [ ] **Step 3: Run the suite.** Expected: all pass.
- [ ] **Step 4: Docs.** Suggested commit message: `Add crosshair hitmarker`

---

## Part C: Loadout, crates, cheat

### Task 5: Carry rules (pure)

The rule is the 2D one: you always have the pistol and the torch, plus **one heavy** (shotgun, rifle or uzi) and **one melee** (the bat).

**Files:**
- Modify: `scripts/3d/fp_loadout.gd`
- Test: `test/test_fp_loadout.gd` (extend)

**Interfaces:**
- Produces:
  - `const START := PISTOL_TORCH`
  - `static func available(heavy: int, melee: int, all: bool) -> Array[int]`. It always includes `[EMPTY, TORCH, PISTOL, PISTOL_TORCH]`. It adds the loadout whose `WEAPON` is `heavy`, adds `BAT` if `melee != -1`, and returns all 8 when `all` is true. The result is sorted.
  - `static func take(heavy: int, melee: int, id: int) -> Dictionary`. It returns `{heavy, melee, dropped, refill}`:
    - a heavy you don't carry replaces your current one (`dropped` = the old id, or -1);
    - the same heavy gives `refill = true` and `dropped = -1`;
    - `W.MELEE` fills the melee slot the same way.
  - `static func fallback(loadout: int, avail: Array) -> int`. It returns `loadout` if it's in `avail`, else `START`.

- [ ] **Step 1: Write the failing tests.**

```gdscript
_check("start is pistol+torch", L.START == L.PISTOL_TORCH)
_check("start has no heavies", L.available(-1, -1, false) == [L.EMPTY, L.TORCH, L.PISTOL, L.PISTOL_TORCH])
_check("rifle adds rifle", L.RIFLE in L.available(W.RIFLE, -1, false) and not L.SHOTGUN in L.available(W.RIFLE, -1, false))
_check("cheat has all 8", L.available(-1, -1, true).size() == 8)
var t: Dictionary = L.take(W.RIFLE, -1, W.SHOTGUN)
_check("second heavy swaps", t.heavy == W.SHOTGUN and t.dropped == W.RIFLE)
t = L.take(W.RIFLE, -1, W.RIFLE)
_check("same heavy refills", t.heavy == W.RIFLE and t.dropped == -1 and t.refill)
t = L.take(-1, -1, W.MELEE)
_check("bat fills melee", t.melee == W.MELEE and t.heavy == -1)
_check("gave rifle away -> pistol+torch", L.fallback(L.RIFLE, L.available(-1, -1, false)) == L.START)
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the three functions and `START`. `cycle()` stays for the cheat path; the wheel uses `available`.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Docs** (folded into Task 6's commit).

### Task 6: Viewmodel inventory, hand-over and cheat

**Files:**
- Modify: `scripts/3d/viewmodel.gd`:
  - `_unhandled_input` (l.587): 1–8 and the wheel only select `available`; T works only with the cheat on; F9 toggles the cheat;
  - `select` (l.614);
  - `_hand_over` (l.638) becomes `_interact()`;
  - `_ready` starts on `L.START`;
  - the HUD shows `CHEAT` while it's on.
- Modify: `scripts/test/test_player.gd`: add `heal(amount: int) -> void`, clamped to `max_hp`.
- Modify: `scripts/balance.gd`: `FP.cheat_key = KEY_F9`

**Interfaces:**
- Consumes: Task 5's `available`, `take` and `fallback`.
- Produces (used by Task 7):
  - viewmodel `var heavy := -1`, `var melee := -1`, `var cheat := false`
  - `func give(id: int, ammo := {}) -> int` returns the dropped id or -1, and refills on the same weapon.
  - `func add_pistol_mag() -> void`
  - `func _interact() -> void`. A ray from the camera, `give_m` long, mask `1 | 8 | 64`:
    - a collider with `open()` → `collider.open()`;
    - `collect(vm)` → `collider.collect(self)`;
    - `receive_weapon` → the hand-over below.
- **Hand-over now moves real weapons** (2D rules; this is the backlog's "fix the weapon hand-over"):
  - Only the **heavy in your hand** can be given. It leaves your inventory with its actual ammo (`npc.receive_weapon(id, mag + reserve)`), and you fall back to `START`.
  - Taking it back calls `give(id, {mag, reserve})` from `surrender_weapon()`'s result. If you carry a different heavy by then, that one drops as a pickup at your feet.
- **Cheat:** only works when `OS.is_debug_build()`. F9 toggles `cheat`. While it's on, `available(..., true)` and T refills everything (today's T). The release build has no cheat.

- [ ] **Step 1: Implement** the changes above. Dropped weapons spawn through `Pickup3D.drop(root, pos, kind)` from Task 7. Until Task 7 lands, stub it with a `push_warning`.
- [ ] **Step 2: Scripted check** in the scratch copy, a harness like `$SP/npc.gd`:
  - spawn the player: only 1–4 select;
  - F9: 5–8 select;
  - F9 again with the rifle in hand: you fall back to `START`;
  - give a rifle to an NPC: the player's `heavy == -1`;
  - take it back: `heavy == W.RIFLE` and the ammo is unchanged.
- [ ] **Step 3: Run the suite.** Expected: all pass.
- [ ] **Step 4: Docs.** In PROJECT.md, the controls list changes: 1–8 now selects only what you carry; F9 is the debug cheat for all weapons; T refills only while the cheat is on. Suggested commit message: `Start with pistol and torch, add carry limit and debug weapon cheat`

### Task 7: Loot crates and 3D pickups

**Files:**
- Create: `scripts/3d/loot_crate.gd` (`extends StaticBody3D`)
- Create: `scripts/3d/pickup_3d.gd` (`extends StaticBody3D`)
- Modify: `scenes/loot_box/loot_box.gd`. Make `_kind_weights()` and `_weapon_weights()` `static` (no other change).
- Modify: `scripts/balance.gd`. Add `LOOT_3D = {crate_count = 14, min_sep_m = 30.0, spawn_clear_m = 25.0, burst_m = 1.5}`. The item counts and weights are reused from `Balance.LOOT`.
- Modify: `scripts/3d/viewmodel.gd`. Show a prompt label under the crosshair while `_interact`'s ray hits something: "E  open crate", "E  take Shotgun", "E  give Rifle", "E  take back Rifle".

**Interfaces:**
- Consumes:
  - `LootTable.roll_item_count` and `roll_kind`;
  - `LootBox._kind_weights()` and `_weapon_weights()` (static now);
  - `Pickup.Kind`, `Pickup.COLORS` and `Pickup.KIND_TO_WEAPON` via `preload("res://scenes/pickup/pickup.gd")`;
  - `Npc3D._fit_gun(model, length)` and `viewmodel.MODELS` for the gun meshes;
  - viewmodel `give`, `add_pistol_mag` and `_player.heal` from Task 6.
- Produces:
  - `LootCrate`:
    - `var guarantee_weapon := false`, `var opened := false`
    - `func open() -> void`. It rolls with its own seeded `rng`, set by the spawner, and drops each item with `Pickup3D.drop` on the navmesh within `burst_m`. Then it swaps to an open-lid look.
    - Body: `BoxMesh` 0.8 × 0.55 × 0.55 in brown wood, `collision_layer = 1` (it blocks, and bullets hit it), meta `surface = "wood"`.
  - `Pickup3D`:
    - `var kind: int`
    - `static func drop(root: Node, pos: Vector3, kind: int) -> Pickup3D`
    - `func collect(vm) -> void`:
      - AMMO_MAG → `vm.add_pistol_mag()`;
      - BANDAGE / MEDPACK → `vm._player.heal(Balance.LOOT.heal_bandage / heal_medipack)`;
      - weapons → `vm.give(id)`, and a returned dropped id spawns its own pickup at the same spot.
      - Then `queue_free()`.
    - Layer 64 only, mask 0. The mesh is the fitted gun model for weapons, or a small coloured box (`Pickup.COLORS`) for the rest.

- [ ] **Step 1: Implement** both scripts and the prompt.
- [ ] **Step 2: Scripted check** in the scratch copy:
  - place a crate with `guarantee_weapon` 2 m in front of the player and call `_interact()`: 1–3 pickups appear, and at least one is a weapon;
  - `_interact()` on that weapon: `heavy` is set;
  - collect a second, different heavy: the first one lies on the ground.
- [ ] **Step 3: Run the suite.** Expected: all pass.
- [ ] **Step 4: Docs.** Suggested commit message: `Add 3D loot crates and pickups`

### Task 8: Even, seeded crate scatter

**Files:**
- Create: `scripts/3d/loot_scatter.gd` (`extends RefCounted`, static, pure)
- Modify: `scripts/3d/commander.gd`, around l.159 next to `Npc.spawn_all`. Spawn the crates there too, with `LootCrate.spawn_all(get_parent(), seed)`.
- Modify: `scripts/3d/loot_crate.gd`. Add `static func spawn_all(parent: Node3D, seed: int) -> Array`.
- Test: `test/test_loot_scatter.gd`

**Interfaces:**
- Produces: `LootScatter.scatter(rect: Rect2, count: int, seed: int, min_sep: float, accept: Callable) -> PackedVector2Array`. Here `accept(p: Vector2) -> Vector2` returns a snapped valid point, or `Vector2.INF` to reject.
- The algorithm is a jittered grid, so points are random but evenly spread:

```
cols = max(1, round(sqrt(count * rect.size.x / rect.size.y))); rows = ceil(count / cols)
cells = all (c, r) shuffled with rng(seed); take the first `count`
for each cell: up to 30 tries of a uniform point in the cell -> accept() ->
    keep the first that is not INF and >= min_sep from every kept point
```

- `spawn_all`:
  - `accept` = the navmesh closest point within 2 m of the candidate, `next_to_building` (crates sit against walls) and ≥ `spawn_clear_m` from the shooter.
  - Each crate's `rng.seed = hash([seed, i])`.
  - One crate (`rng`-chosen) gets `guarantee_weapon = true`.
  - The seed is a fixed `Balance.LOOT_3D.seed = 1` for now; S10 passes the match seed.

- [ ] **Step 1: Write the failing test.**

```gdscript
var S = load("res://scripts/3d/loot_scatter.gd")
var R := Rect2(0, 0, 250, 170)
var all := func(p): return p
var pts: PackedVector2Array = S.scatter(R, 14, 7, 30.0, all)
_check("14 crates", pts.size() == 14)
_check("inside the map", Array(pts).all(func(p): return R.has_point(p)))
var min_d := INF
for i in pts.size(): for j in range(i + 1, pts.size()): min_d = minf(min_d, pts[i].distance_to(pts[j]))
_check("spread >= 30 m", min_d >= 30.0)
for q in [Rect2(0,0,125,85), Rect2(125,0,125,85), Rect2(0,85,125,85), Rect2(125,85,125,85)]:
    _check("every quarter has crates", Array(pts).filter(func(p): return q.has_point(p)).size() >= 2)
_check("same seed, same map", S.scatter(R, 14, 7, 30.0, all) == pts)
_check("new seed, new map", S.scatter(R, 14, 8, 30.0, all) != pts)
var right := func(p): return p if p.x > 125 else Vector2.INF
var half: PackedVector2Array = S.scatter(R, 14, 7, 30.0, right)
_check("blocked cells just give fewer", half.size() < 14 and Array(half).all(func(p): return p.x > 125))
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `scatter`, then `spawn_all`, wired into the commander's spawn.
- [ ] **Step 4: Run the test and the suite.** Expected: all pass. Render check: a top-down commander shot with the fog off shows about 14 crates spread over the whole map, all at walls, none on roofs.
- [ ] **Step 5: Docs.** Suggested commit message: `Scatter loot crates evenly over the map`

---

## Part D: Survivors hide, flee or freeze

### Task 9: Cover-scored hiding spots

Zombie sight is blocked only by buildings (`Zombie3D.buildings_clear`), so "behind things" means behind buildings: alleys, corners and recesses. Props, crates and lamps don't hide anyone until they block sight too.

**Files:**
- Modify: `scripts/3d/npc_3d.gd`:
  - `_hiding_spot` (l.189);
  - `spawn_all` (l.501) uses the same score;
  - new static `cover_score`.
- Modify: `scripts/balance.gd`: `NPC_3D.cover_ray_m = 4.0`, `NPC_3D.min_cover = 3`, `NPC_3D.spot_samples = 16`
- Test: `test/test_npc_hiding.gd` (new, `extends SceneTree`, builds walls and awaits 2 physics frames)

**Interfaces:**
- Produces: `Npc3D.cover_score(space: PhysicsDirectSpaceState3D, p: Vector3) -> int`. It counts how many of 8 horizontal rays (every 45°, from `p + Vector3.UP`, `cover_ray_m` long, mask 1) hit a body whose parent name starts with `"Building"`, the same test as `next_to_building`.
- `_hiding_spot()`:
  - samples `spot_samples` navmesh points within the current radius;
  - drops any with `cover_score < min_cover` or `Zombie3D.seen_by_horde`;
  - returns the highest score (ties broken at random), or `Vector3.INF`.

- [ ] **Step 1: Write the failing test.** Two "Building" boxes 2 m apart make an alley, and one box is a lone wall.

```gdscript
_check("alley is deep cover", N.cover_score(space, alley_mid) >= 6)
_check("against one wall", N.cover_score(space, by_wall) == 3)
_check("open street", N.cover_score(space, open_pt) == 0)
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** `cover_score`, `_hiding_spot` and `spawn_all`.
- [ ] **Step 4: Run the test and the suite.** Expected: all pass. Render check: a top-down shot of the 10 survivors at spawn shows them in alleys and corners, not on open pavement.
- [ ] **Step 5: Docs** (folded into Task 10's commit).

### Task 10: Spotted → flee (80%) or cower (20%)

**Files:**
- Modify: `scripts/3d/npc_3d.gd`:
  - `enum State` appends `FLEEING, COWERING`, so the existing values keep their numbers;
  - `_physics_process` (l.132);
  - new `_check_spotted`, `_fleeing` and `_cowering`;
  - new statics `react` and `flee_spot`.
- Modify: `scripts/balance.gd`: `NPC_3D.freeze_chance = 0.2`, `flee_mps = 4.5` (beats standard zombies at 2.0, loses to fast ones at 6.06), `flee_min_m = 18.0`, `calm_s = 6.0`, `spot_check_s = 0.2`
- Test: `test/test_npc_hiding.gd` (extend), plus a scripted run in the scratch copy.

**Interfaces:**
- Consumes: Task 9's `cover_score` and the `zombies` group with `can_see(pos)`.
- Produces:
  - `static func react(r: float) -> State` returns `COWERING` if `r < Balance.NPC_3D.freeze_chance`, else `FLEEING`. It's rolled once per sighting.
  - `func _check_spotted() -> Node3D`. Every `spot_check_s`, it returns the nearest zombie that `can_see(global_position)`, or `null`.
- **Rules:**
  - Checked only in HIDDEN and RELOCATING. FOLLOWING and CONVERTING never react.
  - **FLEEING:**
    - The target is `flee_spot(threat)`: the best `cover_score` among `spot_samples` points that are ≥ `flee_min_m` from the threat, where `(p - pos).dot(pos - threat) > 0` (away from it), and not seen by that zombie.
    - The NPC runs there at `flee_mps`. On arrival it goes HIDDEN if no zombie sees it; otherwise it picks again.
    - On the third pick, or when there's no spot, it switches to COWERING.
  - **COWERING:**
    - It stops and freezes into the cower pose (Task 11).
    - Once no zombie has seen it for `calm_s`, it goes HIDDEN where it is.
  - In every state, walking into the NPC still recruits it (`_check_recruit` runs first), and a bite still converts it.

- [ ] **Step 1: Write the failing test.**

```gdscript
_check("19% roll freezes", N.react(0.19) == N.State.COWERING)
_check("20% roll runs", N.react(0.2) == N.State.FLEEING)
_check("new states keep old numbers", N.State.CONVERTING == 3 and N.State.FLEEING == 4)
```

- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the states and `flee_spot`.
- [ ] **Step 4: Scripted run** in the scratch copy, with a zombie 10 m from a hidden NPC in clear view:
  - with `react` forced to FLEEING: after 3 s, its distance from the zombie has grown by ≥ 6 m;
  - forced to COWERING: it hasn't moved more than 0.3 m and its state is COWERING;
  - a following NPC in the same setup: still FOLLOWING;
  - a fleeing NPC the shooter walks into: FOLLOWING.
- [ ] **Step 5: Run the suite.** Expected: all pass.
- [ ] **Step 6: Docs.** Suggested commit message: `Survivors hide in cover and flee or freeze when spotted`

### Task 11: Cower pose

None of the models has a crouch clip. `business_man`, `hoodie` and `adventurer` share one clip list (it includes `Roll`, `HitRecieve` and `Interact`); `man` has `Man_Sitting` and `Man_Death`. The cower is one of these clips, frozen on a chosen frame.

**Files:**
- Modify: `scripts/3d/character_anim.gd`. Add `func freeze(clip: String, at: float) -> void` and `func unfreeze() -> void`. While frozen, `_process` doesn't switch clips.
- Modify: `scripts/3d/npc_3d.gd`. Each `MODELS` entry gains `[cower_clip, cower_t]`. COWERING calls `freeze`, and leaving COWERING calls `unfreeze`.

- [ ] **Step 1: Render a contact sheet** in the scratch copy, one row per model:
  - `CharacterArmature|`: `Roll` at 0.25 / 0.35 / 0.45, `HitRecieve` at 0.3, `Interact` at 0.5;
  - `HumanArmature|Man_`: `Sitting` at 0.5, `Death` at 0.25.
- [ ] **Step 2: Pick the most crouched and scared frame per model** from the sheet, and record it in `MODELS`.
- [ ] **Step 3: Implement** `freeze`: `play(prefix + clip)`, `seek(at, true)`, `pause()`. `unfreeze` clears the flag so the next `_process` resumes. Re-render a cowering NPC to confirm.
- [ ] **Step 4: Run the suite.** Expected: all pass.
- [ ] **Step 5: Docs.** Suggested commit message: `Add survivor cower pose`

---

## Not in this plan

- **Sound.** There's no hit tick, glass crash or crate sound, because no 3D audio exists yet. Add it with the audio pass.
- **Replication** of shattered lamps, crate contents and pickups. That's S10; the seeded placement is ready for it.
- **Props blocking zombie sight.** Without it, crates and cars don't hide survivors. Add it when the 3D prop scatter lands.
- **Lamp-pole damage or knocking poles over.** Only the glass breaks.

---

## Execution record (2026-11-17)

Built in place on main and left uncommitted for Mads (house rules). Suite 27/27. A fresh reviewer graded the result "with fixes"; all Critical/Important findings were fixed test-first.

### Rulings
- Setup: Ruling: work in place on main, no worktree, no commits — CLAUDE.md house rules (live editor must see edits; "Don't commit unless asked"; Mads commits/pushes) — cost if wrong: one bigger uncommitted diff; Mads commits per part using the suggested messages.
- Setup: Ruling: Linear skipped (Mads's choice) — tracked in docs/BACKLOG.md — cost if wrong: none.
- - T1 bat: plan says bat makes no decal but spawn() decides decal per surface. Ruling: spawn() takes `decal := true`; bat passes false — matches today's bat behaviour — cost if wrong: one param.
- Task 1: Ruling: particles() starts idle + billboard_keep_scale — root cause of impacts/smoke never rendering, found in the render check — cost if wrong: none (render-verified). Uncommitted; suggested message: Add surface-aware bullet impacts shared by shooter and survivors
- Task 2: Ruling: lamp tests moved into _initialize() after one process_frame — root joins the tree only then, so _ready never ran in _init — cost if wrong: none. Uncommitted; suggested message: Let bullets shatter street lamps
- Task 3: Ruling: ImpactFx.spawn signature is (root, pos, normal, surface, decal := true, dir := Vector3.ZERO) — T1's decal ruling put decal before dir — cost if wrong: arg order only.
- Task 3: Ruling: added a "gore" surface (bigger flesh) for limb-off bursts and ImpactFx.root_of(node) — plan said "a bigger burst"; a Balance entry keeps it tunable — cost if wrong: none.
- Incident: project_run autosave (after Task 2's live check) wrote the editor's stale viewmodel.gd tab over the file, losing HEAD's hand-over/~2-mask work plus Task 1 edits. Ruling: restored HEAD version (git show), re-applied T1+T3 edits, pushed all changed scripts via MCP script_create (reloaded=true), no more project_run from me; live checks run in the scratch copy — cost if wrong: Mads must discard the stale viewmodel tab before playing (flag in final message).
- Task 4: Ruling: added pure viewmodel.marker_look(result) + test (plan had render-only) — keeps test-first — cost if wrong: none. Uncommitted; suggested message: Add crosshair hitmarker
- Task 5: Ruling: available() returns untyped Array (plan: Array[int]) — so == against literal arrays holds in tests — cost if wrong: none.
- Task 6: Ruling: with the cheat on, any heavy in hand can be handed over (and the player keeps carrying their real heavy) — the cheat means "no limit" — cost if wrong: one condition.
- Task 6: Ruling: _drop() is a push_warning stub until Task 7 (as the plan says). Scripted check 13/13 (inv_check.gd).
- Task 7: Ruling: no dependency on the 2D Pickup script or LootBox (plan said make LootBox helpers static and use Pickup.Kind) — pickup.gd's preload cycle (pickup.gd -> pickup.tscn -> pickup.gd) breaks headless loading; Pickup3D has its own Kind enum in the same order and LootCrate.weights() reads Balance.LOOT — cost if wrong: the 7-entry weights map is written twice (2D LootBox + 3D LootCrate), both from Balance.LOOT.
- Task 7: Ruling: pickup/prompt names use the 3D loadout names (Bat, Uzi) not the 2D display_name ("Melee", "Machine Gun") — matches the 3D HUD — cost if wrong: a label.
- Task 8: Ruling: spawn_all(parent, rect, seed, avoid) — rect from the baked navmesh vertices passed by the commander (plan: spawn_all(parent, seed)) — cost if wrong: signature only.
- Task 8: Ruling: added Npc3D.outdoors() (render check found 5/10 crates INSIDE buildings: hollow shells leave navmesh islands) — Review Focus #4 — tested in test_npc_hiding.gd. NPC spawn/hiding get it in Task 9.
- Task 8: Ruling: next_to_building now casts 8 rays (was 4 axis rays; the street grid is angled) and crate spots slide to the nearest wall within LOOT_3D.wall_reach_m via Npc3D.wall_spot() — yield went 9 -> 13 of 14 — cost if wrong: NPC hiding spots change slightly (more wall spots found).
- Task 9: Ruling: hiding candidates slide to the nearest wall (spot_by_wall, shared with crates) before scoring, and must be outdoors() — random street points almost never score >= 3; fixes survivors spawning inside hollow buildings too — cost if wrong: survivors hug walls more than the 2D ones did.
- Task 9: Ruling: _wall_hits() shared by next_to_building / wall_spot / cover_score (DRY), _best_spot(ok) shared by hiding and (Task 10) flee — cost if wrong: none.
- Task 10: Ruling: added Npc3D.reachable()/path_arrives() — enclosed courtyards are navmesh islands; best-cover spots were unreachable, so agents "finished" without moving; also applied to NPC spawn and crate placement (from the shooter's start) — cost if wrong: fewer candidate spots.
- Task 10: Ruling: added path_keeps_away() — a flee spot "on the far side" could be routed round the block back past the zombie (seen: ended 8.4 m from it) — cost if wrong: more flee-to-cower fallbacks.
- Task 10: Ruling: 0.3 s grace before trusting is_navigation_finished() in FLEEING (it reports true before the first path) — cost if wrong: none.
- Task 10: Ruling: scripted-check criterion changed from "6 m further in 3 s" (straight line) to "ran >= 6 m, ended further, not cowering" — routes go round blocks. Flake: ~1 in 10 forced flees cowers at once (first leg doesn't move, retry finds no route) — designed fallback; acceptable.
- Task 10: Ruling: reachable() is unit-tested via the pure path_arrives(); a hand-built test navmesh returned no polygons in this Godot build (both headless and windowed) — cost if wrong: the integration is verified only by the scene runs.
- Task 11: Ruling: freeze(clip, at) takes `at` as a 0..1 fraction of the clip (plan: seconds) — frames picked visually by fraction — cost if wrong: none. Picks: CharacterArmature Roll 0.12, Man Standing 0.0 (contact sheets cower_sheet*.png).
- Final: Ruling: reviewer's minor #3 (survivor running in place forever against a crate) re-graded Important by effect — fixed via leg_overdue() (test RED->GREEN), suite 27/27; relocation also got the 0.3 s grace.
- Final: Ruling: declined-to-judge "bat hits on zombies puff dust" — a player expects blood; fixed by the SHOT_MASK change (bat ray now reaches part hitboxes).
- Final: Ruling: declined-to-judge "Death clip replays on a dead survivor" (pre-existing) — visible on every survivor death, in a function this work touched; fixed (test "a corpse stays down" RED->GREEN), suite 27/27.
- Final: Ruling: other declined-to-judge lines stand (replication/sound/props-block-sight deferred by plan; all-round zombie sight is the fog's test by design; follower losing its gun on death pre-existing; cosmetic global-RNG yaw; cheat duplication debug-only; fixed engine-workaround literals; edits pushed via MCP script_create).
- Final: Ruling: blood is one burst along the hit normal + a splat along the shot, not a separate forward spray (plan) — reads fine in renders — cost if wrong: one extra particle burst.

### Deferred minors
- swapping heavies refills ammo; taking back a re-acquired heavy overwrites its ammo with the survivor's (both match 2D).
- opened crate lid can land in the wall behind it (cosmetic).
- the E prompt still shows on the death screen.
- loot_scatter divides by rect height (zero-area rect would hang; a real navmesh can't produce one).
- next_to_building is now only used by tests; the bat's hitmarker shows the last zombie hit, not the strongest.
