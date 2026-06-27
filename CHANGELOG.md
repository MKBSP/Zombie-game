# Changelog

Phase-organized history (newest first), reconstructed from git. Append a line
here as part of finishing any meaningful change.

## Phase 5 — Weapon visuals + flashlight fog
- Gun sprite on armed NPCs, synced across the network.
- Weapon icon in the HUD.
- Weapon PNGs shown on floor pickups.
- Equipped gun sprite on the player.
- `WeaponVisuals` texture map (id → PNG) + imported weapon PNGs.
- In progress: sprite fixes (`8877b33`).
- Shooter fog-of-war rebuilt on Godot 2D lighting: dark `CanvasModulate` fog,
  hard-edged flashlight cone + personal halo (each a `PointLight2D` parented to
  the shooter), real straight-line shadows from buildings, props, zombies, and
  NPCs (`LightOccluder2D` on all moving entities). New file:
  `scripts/shooter_lighting.gd` (`ShooterLighting`), assembled from
  `world.gd::_setup_fog()` for the HUMAN role only. Tunables in
  `Balance.FOG_SHOOTER` (ambient darkness, beam range/angle/energy/color, halo
  radius/energy/color, shadow toggles). Removed: `FogShooter`
  (`scripts/fog_shooter.gd`), `shader/fog_of_war.gdshader`, the `ShooterFogRect`
  overlay node, and the per-frame fog-texture update in `world.gd`. The
  zombie-controller fog (`FogZombieController` / `fog_zc.gdshader`) is unchanged.

## Phase 4 — Inventory, machine gun & melee
**4a — inventory + machine gun**
- 3-slot inventory selection: `1` pistol / `2` heavy / `3` melee.
- Full-auto machine gun (heavy slot) with pickup + world spawn.

**4b — melee**
- `MELEE` weapon data + `Balance.MELEE` tuning.
- `Melee.forward_strike` cone + recent-hit/fatigue math (unit-tested).
- Swing + fatigue + drop + HUD readout; aim ring hidden for melee (dot only).
- Melee pickup + world spawn.
- Bullet tweaks: 2× faster, ~2px tiny bullets. Fixes to bullets, NPC shooting,
  melee and gun slots.

## Phase 3 — Armed NPC shooting
- `Balance.NPC` accuracy + engagement knobs.
- `NpcAim` debuff + recoil math (unit-tested).
- Engagement latch + spread + recoil + 1.5 shots/sec cap.

## Phase 2 — Headshots
- `AimModel.is_headshot` ray-distance + unit test.
- Center-mass crit damage on zombies (4×, range-scaled).
- "HEADSHOT!" toast on player crits.

## Phase 1 (shooting) — Player aiming core
- `AimModel` spread/falloff math + headless unit test.
- Weapon aiming, per-weapon spread + range fields/values.
- `focus_aim` (Ctrl) input action.
- Bullet range→damage falloff + max-range despawn.
- Visible custom aim cursor (cone radius = spread, opacity = range fade, focus
  tint); server-synced aim state (running/injured/recoil debuffs + focus).

## Multiplayer
- Local multiplayer working; dedicated server deploy (Railway, first attempt).
- Room logic + codes; sequential room reuse so games run one after another.
- Weapon swap by dropping the held weapon; stopped tracking screen recordings.

## Phase 1–2 (foundation) — Core game
- Initial zombie game; first playable map + HUD; win/lose conditions.
- New map; props/scenery scatter (cars, fences, etc.).
- Shooter fog-of-war; zombie controller + visuals.
- Zombie merging (standard/fast/fat/master variants); NPCs; start menu +
  selection; special weapons.
