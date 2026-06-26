# Phase 5: weapon visuals

Date: 2026-06-26
Status: approved, pre-implementation

Show the equipped weapon as a sprite — on the player, on armed NPCs, on floor
pickups, and in the HUD — using the five weapon PNGs the user drew. This is the
visual half of the user's "Phase 5" (the bullet tweak shipped already). Mechanics
phase only: **static sprites, no firing animation / recoil / muzzle flash** — those
are deferred.

## Problem

The player is a square sprite that never shows what it's holding; armed NPCs are
plain squares; weapon pickups are colored squares; the HUD shows the weapon as text.
The art now exists (`sprites/Gun.png`, `Shotgun.png`, `Rifle.png`, `Machinegun.png`,
`Club.png`), so we can render the actual weapon everywhere it matters.

## Goals

- A **single weapon→texture map** read by every consumer.
- **Player:** a gun sprite mounted on the shooter that points where you aim and
  swaps to match the equipped weapon (1/2/3).
- **NPC:** a gun sprite on an armed NPC, matching its weapon, visible on both peers.
- **Floor pickups:** weapon pickups show their PNG instead of a colored square.
- **HUD:** a small icon of the equipped weapon next to the ammo readout.

## Non-goals (deferred)

- Any animation: firing, swinging, recoil kick, muzzle flash, reload.
- Precise NPC gun aim-rotation on clients (the NPC gun shows but doesn't track the
  target per-frame across the wire yet).
- Distinct HUD-vs-world art, and art for ammo-mag / medpack pickups (keep squares).
- The club on NPCs (NPCs are firearms-only).

## Components

- **`scripts/weapon_visuals.gd`** (`class_name WeaponVisuals`) — the single source of
  truth: `static func texture(weapon_id: int) -> Texture2D` returning the preloaded
  PNG for `PISTOL→Gun`, `SHOTGUN→Shotgun`, `RIFLE→Rifle`, `MACHINEGUN→Machinegun`,
  `MELEE→Club` (and `null`/none otherwise). Pickups map their kind→weapon id to reuse
  it.
- **`scenes/shooter/shooter.tscn` + `shooter.gd`** — add a `WeaponSprite` (Sprite2D)
  child mounted at a small forward offset (drawn pointing +X, so it inherits the
  shooter's aim rotation). `equipped` becomes a setter that refreshes
  `WeaponSprite.texture = WeaponVisuals.texture(equipped)` (null-guarded; also called
  in `_ready`). Because the synchronizer assigns `equipped` on every peer, the sprite
  updates on the controlling client *and* the other window.
- **`scenes/npc/npc_human.tscn` + `npc_human.gd`** — add a `WeaponSprite` child; a
  `weapon_id` setter shows/hides it and sets its texture (firearms only). Add
  `weapon_id` to the NPC's `MultiplayerSynchronizer` so the gun shows on both peers.
  Mounted at a fixed local offset (no per-frame aim rotation this phase).
- **`scenes/pickup/pickup.gd`** — for weapon kinds, set the pickup `Sprite2D.texture`
  to the weapon PNG (and clear the color modulate); ammo/medpack keep their tinted
  squares.
- **`scenes/world/world.tscn` (HUD) + `scenes/ui/hud.gd`** — a `WeaponIcon`
  (TextureRect) in the HUD; `hud.gd` sets it from `WeaponVisuals.texture(shooter.equipped)`
  each update.
- **Import:** the five PNGs need a one-time Godot reimport (they have no `.import`
  yet); set the texture filter to nearest (project default) for crisp pixels.

## Data flow

```
equipped (synced int)  -> shooter WeaponSprite texture (all peers) + HUD icon (human)
npc.weapon_id (newly synced) -> NPC WeaponSprite texture + visibility (all peers)
pickup.kind -> WeaponVisuals texture on the floor sprite
```

## Multiplayer

`equipped` is already synced, so the player's gun shows on both windows with no new
state. The only addition is syncing the NPC's `weapon_id` (one int, on-change) so its
gun renders on the non-server peer. All textures are resolved locally from those
synced ids via `WeaponVisuals`; no texture data crosses the wire.

## Testing

Visual, via the godot-ai MCP: screenshots confirming the gun appears on the player
and rotates as you aim; swaps with 1/2/3 (pistol→Gun, heavy→its PNG, melee→Club); the
floor pickups show their PNGs; an armed NPC shows its gun; the HUD icon matches the
equipped weapon. Existing unit suites (`aim_model`, `npc_aim`, `melee`) still pass;
compile-check clean.

## Known limitations / deferred

- No animation/recoil/muzzle flash; NPC gun doesn't aim-track on clients yet.
- Ammo/medpack pickups stay colored squares.
- One mount offset for all weapons (not per-weapon tuned) — revisit with art polish.
