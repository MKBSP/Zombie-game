# Loot Box System — Design

**Date:** 2026-06-27
**Status:** Approved, ready for implementation plan

## Summary

Replace the current scattered-item spawning with **loot boxes** (crates) placed
around the map. The player walks up to a closed crate, presses the interact key
to open it, and 1–3 items physically burst out onto the ground within ~1 tile.
Items render their own sprite on the floor and are collected by walking near and
pressing the same interact key. Box count, per-box item-count odds, and per-item
spawn weights are all tunable in `balance.gd`.

This reuses the existing `Pickup` (`Area2D`) pipeline, its replication via
`MultiplayerSpawner`, and the auto-swap-drop logic. It is server-authoritative;
the contested-loot dynamic ("first to grab wins") falls out of the server already
owning the pickup grant.

## Why jump-out, not a menu

This is real-time co-op. A selection menu would freeze one player while zombies
keep spawning and the co-op partner keeps moving, and it would conflict with the
aiming mouse (which drives the gun and flashlight). Jump-out + walk-near pickup
reuses the whole existing pipeline, keeps the game real-time, and fits the genre
(Risk of Rain 2, Left 4 Dead, Helldivers all use world pickups, not menus). The
item sprite on the floor provides the "what is it" readability without a label.

## Boxes

- **`BOX_COUNT = 8`** in `balance.gd` (starting value; tune freely).
- Placed on walkable tiles only (`road`, `sidewalk`, `grass`, `parking`), never
  inside a building, never on top of another box, item, or prop.
- Replaces `world.gd:_spawn_items()` entirely. The old near-player "testing"
  bias for special weapons is **dropped** — boxes scatter uniformly.
- Closed crate renders `res://sprites/Crate_closed.png`. Opening swaps it to
  `res://sprites/Crate_opened.png`. An opened box remains as inert scenery.

## Opening and the jump-out animation

- Opening is triggered by the contextual `interact` key (see Interaction Layer).
- On open (server-authoritative), the box:
  1. Swaps to the opened sprite.
  2. Rolls the item count, then per-item type (see Probabilities).
  3. Spawns each item as an existing `Pickup` at the box center and **tweens it
     out** to its landing spot — ~0.3s arc/slide with a small scale-pop. This is
     a real burst animation, not a plain spawn.
- Each item lands **within ~1 tile** of the box. Each landing spot is validated:
  - not inside a building (`building_layer` cell present → reject),
  - not on a prop (tree/car/dumpster/etc.),
  - not on another already-placed item.
  Re-roll the angle/distance up to a fixed number of attempts; if all fail, drop
  at the box center as a fallback.
- An item becomes grabbable only **after** its tween lands (no mid-air pickup).
- A box can only be opened once; further interacts on an opened box do nothing.

## Probabilities

### Items per box

Rolled once per box:

| Items | Chance |
|-------|--------|
| 1     | 80%    |
| 2     | 19%    |
| 3     | 1%     |

Knobs: `BOX_CHANCE_TWO = 0.20`, `BOX_CHANCE_THREE = 0.01`.
Roll: `r < BOX_CHANCE_THREE` → 3, else `r < BOX_CHANCE_TWO` → 2, else 1.

### Item type — independent weighted roll per item slot

Each item the box drops rolls its type independently (a box can drop two of the
same type, e.g. two mags). Weights are relative; resulting odds shown:

| Item       | Weight | ≈ Chance | Effect            |
|------------|--------|----------|-------------------|
| Ammo mag   | 25     | 25%      | pistol mag refill |
| Bandage    | 30     | 30%      | heal **+10 HP**   |
| Medipack   | 10     | 10%      | heal **+50 HP**   |
| Melee      | 10     | 10%      | give melee        |
| Shotgun    | 10     | 10%      | give special      |
| Machinegun | 10     | 10%      | give special      |
| Rifle      | 5      | 5%       | give special      |

Each weight is its own `balance.gd` variable (`BOX_WEIGHT_AMMO_MAG`,
`BOX_WEIGHT_BANDAGE`, `BOX_WEIGHT_MEDIPACK`, `BOX_WEIGHT_MELEE`,
`BOX_WEIGHT_SHOTGUN`, `BOX_WEIGHT_MACHINEGUN`, `BOX_WEIGHT_RIFLE`). The table is
structured so a future item (`battery`, `health_kit`, `bat`) is added with one
new `Kind` plus one new weight line — no re-summing required.

### New item: Bandage

- `Pickup.Kind` gains a **`BANDAGE`** value.
- Bandage heals **+10 HP**; Medipack continues to heal **+50 HP**.
- Bandage and Medipack now render their **sprites** (`res://sprites/bandage.png`,
  `res://sprites/Medipack.png`) instead of color tints. Weapon pickups keep
  rendering their weapon PNGs as today.

## Interaction Layer (contextual `E`)

Today `give_weapon_to_npc` is bound to `E` with **no distance check** — it gives
to any following NPC instantly, which is how accidental gives happen. We replace
this with a single contextual interact.

- New input action **`interact`** bound to `E`. `give_weapon_to_npc` is removed
  as a standalone binding and folded into `interact`.
- `interact` resolves to the **nearest interactable the player is within range
  of**. Each interactable type advertises its own interaction radius:
  - **Box open / item grab** → normal radius (~1 tile).
  - **NPC give weapon** → *tight* radius (~⅓ tile). Because the radius is so
    small, an NPC-give is only chosen when the player is practically on top of
    the NPC; standing near both a box and an NPC at arm's length picks the box.
    The accidental-give buffer falls out of nearest-wins for free.
  - **NPC take-back** → if the targeted NPC is already armed, `interact`
    retrieves the weapon + remaining ammo, re-equipping the player (auto-dropping
    the player's current special if different). Non-destructive → normal radius.
- Giving is now both hard to trigger accidentally **and** instantly reversible.
- Contested grabs/opens are server-validated: first valid request wins, no new
  netcode arbitration needed beyond what the server already does for pickups.

### Take-back mechanics

- NPC stores `(weapon_id, ammo)` via the existing `receive_weapon`. Add an
  inverse `surrender_weapon()` returning `(weapon_id, ammo)` and leaving the NPC
  unarmed.
- On take-back the shooter re-equips like `_take_special`: if already holding a
  different special, drop the old one as a world pickup first.

## Tuning surface (`balance.gd`)

- `BOX_COUNT` — number of crates spawned.
- `BOX_CHANCE_TWO`, `BOX_CHANCE_THREE` — items-per-box odds.
- `BOX_WEIGHT_*` — one per item type.

The entire loot economy is tunable here without touching logic.

## Components & boundaries

- **Crate** (`scenes/loot_box/loot_box.tscn` + `.gd`) — a new scene: closed/open
  sprite, an interaction radius, server-side open logic that rolls loot and
  spawns/tweens `Pickup` nodes. Server-authoritative; open-state replicates.
- **Pickup** (`scenes/pickup/pickup.gd`) — extended: add `BANDAGE` kind, sprite
  rendering for bandage/medpack, bandage heal effect, optional spawn tween, and
  (with the interaction layer) grab-on-interact instead of grab-on-overlap.
- **World** (`scenes/world/world.gd`) — `_spawn_items()` replaced by
  `_spawn_loot_boxes()`; box placement validation (walkable, not building, clear
  of other loot/props).
- **Shooter** (`scenes/shooter/shooter.gd`) — `give_weapon_to_npc` input replaced
  by contextual `interact`; nearest-interactable resolution; NPC take-back.
- **NPC** — add `surrender_weapon()`.
- **balance.gd** — new loot tuning block.

## Out of scope (future)

- Max carry slots / inventory cap (will revisit grab behavior then).
- Future items: `battery`, `health_kit`, `bat` (table is ready for them).
- Floating item labels (the floor sprite is sufficient readability for now).

## Testing

- Headless tests (`test/`, run via godot-ai `test_run`):
  - Item-count roll honors `BOX_CHANCE_TWO` / `BOX_CHANCE_THREE` over many rolls.
  - Weighted type roll matches configured weights over many rolls.
  - Landing-spot validation rejects building/prop/occupied tiles.
  - Bandage heals 10, medipack heals 50.
  - NPC give requires tight radius; take-back returns weapon + ammo and unarms
    the NPC.
- Manual: open a crate, confirm the burst animation, grab items via `interact`,
  give/take-back a weapon to/from an NPC.
