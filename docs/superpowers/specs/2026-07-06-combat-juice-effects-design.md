# Combat Juice Effects — Design

**Date:** 2026-07-06
**Status:** Approved (design), pending implementation plan

## Goal

Add visual "juice" to combat so hits, shots, and impacts feel impactful:

1. **Red blood** spurts when zombies land a bite on the player or an NPC.
2. **Permanent bleed trail** — once the player is wounded, he drips blood on the
   ground as he runs; the trail never fades.
3. **Green blood** spurts when the shooter (bullet or melee) hits a zombie.
4. **Sparks** when a bullet hits a wall (`TileMapLayer`) or a prop (`StaticBody2D`).
5. **Muzzle flash** on every shot, casting a brief bit of light around the shooter.

## Approach (A): shared world-level FX service

All effects are **server-authored** and shown on every peer via `call_local`
RPCs, mirroring the existing cosmetic patterns (`world.rpc_noise_event`,
`shooter._swing_fx`). No MultiplayerSpawner entities and no new synced state.

Renderer is **GL Compatibility**, so particles use `CPUParticles2D` for safety.

All tunable numbers live in a new `Balance.FX` dictionary (single source of truth,
per repo convention).

### Components

#### 1. Reusable hit burst — `scenes/fx/hit_burst.tscn`

A one-shot, self-freeing `CPUParticles2D`. Spawned with `(position, direction,
preset)`. Presets defined in `Balance.FX`:

| Preset        | Color        | Shape / feel                              | Direction              |
|---------------|--------------|-------------------------------------------|------------------------|
| `RED_BLOOD`   | red          | medium spread, ~0.4 s                     | away from attacker     |
| `GREEN_BLOOD` | green        | same shape as red                         | along bullet travel    |
| `SPARKS`      | yellow/white | faster, shorter (~0.2 s)                  | back from impact surface |

The scene emits once on spawn and frees itself when its lifetime elapses.

#### 2. World FX helper + RPC

`world.spawn_hit_fx(preset: int, pos: Vector2, dir: Vector2)` — server-only guard,
then calls `rpc_spawn_hit_fx.rpc(...)`:

```
@rpc("authority", "call_local", "unreliable")
func rpc_spawn_hit_fx(preset, pos, dir) -> void:
    # each peer instantiates hit_burst under a local, non-replicated Effects node
```

Ephemeral bursts live under a dedicated `Effects` `Node2D` in the world (NOT under
`Entities`, so they are not replicated — each peer spawns its own via the RPC).

#### 3. Triggers (each a one-line call to `world.spawn_hit_fx`)

- `bullet.gd`, hit zombie ⇒ `GREEN_BLOOD` at impact, dir = bullet direction.
- `bullet.gd`, hit `TileMapLayer` (wall) or `StaticBody2D` (prop) ⇒ `SPARKS` at
  impact, dir = reversed bullet direction.
- `zombie._check_contact_damage`, bite lands on player/NPC ⇒ `RED_BLOOD` at the
  target, dir = (target − attacker).normalized().
- `shooter._swing`, melee lands on a zombie ⇒ `GREEN_BLOOD` at the zombie,
  dir = facing.

#### 4. Muzzle flash — `scenes/fx/muzzle_flash.tscn`

A flash `Sprite2D` + a brief `PointLight2D`. A `_muzzle_fx()`
`@rpc("authority", "call_local")` on the shooter (modeled on `_swing_fx`), fired
inside `shoot()`. The flash sprite pops and a short (~0.05 s) light pulse at
`gun_tip` lights the area around the shooter.

NPCs fire through the same weapon path, so they get the flash sprite too; their
light pulse is smaller/optional (tunable in `Balance.FX`).

#### 5. Bleed trail — baked blood canvas (permanent)

One world-sized `Image` → `ImageTexture` on a node placed z-wise between the
ground and the entities, using the same technique as `fog_zombie_controller`
(image built at runtime, texture assigned to a `TextureRect`/`Sprite2D` covering
the world).

- Taking damage puts the shooter in a **bleeding** state, refreshed on each hit,
  lasting `Balance.FX.bleed_seconds`.
- While bleeding **and** moving, the server emits a drip every
  `Balance.FX.bleed_drip_px` of travel via `rpc_bleed_drop(pos)` (`call_local`).
- Each peer blits a small blood stamp onto its own local canvas at the mapped
  image coordinate. The canvas is never cleared → the trail is permanent.
- One texture = one draw call, bounded memory (no per-drip nodes).

Only the **player** leaves a permanent baked trail. Blood/spark bursts are
ephemeral particles.

#### 6. `Balance.FX`

Holds every number: preset colors, particle counts / speeds / lifetimes / spread,
muzzle-flash duration + light energy/range (player and NPC), bleed window, drip
spacing, and canvas resolution.

## Networking summary

Every effect originates from a server-detected event (bullet collision,
`take_damage`, `shoot`, shooter movement) and replicates via `call_local` RPCs.
No new synced properties, no spawner entities. Both peers accumulate identical
bleed canvases because drips are server-authored.

## Testing

Pure-logic pieces get `test/` helpers following the repo's `RefCounted`-static
convention (referenced via `load("res://...")`, not bare `class_name`):

- World → blood-canvas image coordinate mapping.
- Drip spacing: given a movement path, drips fire at the right intervals.

Visual confirmation is by owner playtest + `logs_read` (clean boot, zero
`SCRIPT ERROR`), per the repo's MCP-capture gotchas.

## Scope boundaries

- Ephemeral particles for all blood/sparks; permanent baked decal for the player
  trail only.
- No GPUParticles (Compatibility-renderer risk).
- No new gameplay behavior — purely cosmetic; damage/combat logic unchanged.
