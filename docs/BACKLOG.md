# Backlog

Open work only, grouped by theme. Completed items live in [CHANGELOG.md](../CHANGELOG.md).
Keep this current: check items off here, move finished ones to the changelog.

## A. Zombie commander experience (current pain points — Phase 9b)

- [x] **Zombie fog rework** (2026-07-10) — shooter-style lighting fog with
      per-zombie LOS vision lights + unexplored-black explored memory
      (`ZombieLighting`, `FogZombieController.tile_line_clear`).
    - [x] The order ping when ordering a zombie renders **on top of** the fog (already fixed — z 150 over fog z 100).
- [x] **Right-click attack targeting** (2026-07-10) — right-click an NPC/shooter
      snaps selected zombies onto it (`attack_target`, red ping); lock holds
      while any zombie sees the target, then degrades to last-seen move.
- [ ] Right-click another zombie → follow it. If the target is large, small
      zombies form a line behind it (cover from bullets) and slow to match speed.
      Multiple followers extend the line.
- [ ] Click on the minimap/map to send selected zombies there.
- [ ] Zombie AI (consider [LimboAI](https://github.com/limbonaut/limboai)).
- [ ] Better pathfinding for zombies.
- [ ] Zombie HUD (commander overlay parity with shooter HUD polish).

### New zombie skills
- [ ] Big zombie: bash / splash attack.
- [ ] Big zombie: throw a normal zombie forward (gap-closer; thrown zombie loses 10 hp).
- [ ] Master zombie: summon skeletons/zombies in open fields / cemetery.
- [ ] Control zombie rats.
- [ ] Control zombie bird.
- [ ] Zombies can convert dogs.
- [ ] Zombies can drag boxes.
- [ ] Zombies can hide in dumpsters.

## B. NPC behavior

- [x] **Follow pathing fix** (2026-07-10) — NPCs retrace the shooter's breadcrumb
      trail single-file (`NpcFollow.trail_point`).
- [x] Formation (2026-07-10): NPCs stand *behind* the shooter, never between
      shooter and zombies (`NpcFollow.formation_slot`).
    - [x] 1 armed NPC → behind player, offset to one side; unarmed NPCs stack behind.
    - [x] 2 armed NPCs → one on each side of the player.
- [ ] NPCs run away when spotted by zombies.
- [ ] Order menu: `E` near an NPC → Stay / Equip / Go to point / Hold ground &
      shoot on sight / Hide (don't shoot unless attacked).
- [ ] Fix the weapon "handover" to NPCs.
- [ ] NPC aim upgradeable in skill tree (base 20% aim debuff exists).
- [ ] Tooltip: "Press E to equip {weapon}" when near an NPC (box tooltip done).
- [ ] Humans can adopt dogs.

## C. Shooter feel & combat tuning

- [ ] Headshots: stop one-shotting zombies; too common. Options: smaller head
      hitbox / "tunnel" (bullet must fully cross the head box) / 5% proc chance
      on head hit, upgradeable via skill tree. (Smaller bullets alone didn't fix it.)
- [ ] Damage animation (hit feedback).
- [ ] Speed debuffs when injured: 50–99% hp → −10% speed; 1–49% hp → −20% speed.
- [ ] Carry limits: max 2 handguns + 1 two-handed (rifle/shotgun/MG). (Melee limit of 1 done.)
- [ ] Melee: knockback, combos, charge attacks.
- [ ] Fear system (impact TBD).

## D. Map & content

- [ ] **Bigger map** (~4× current size — ties into art v1, Phase 8).
- [ ] Map generation: random NPC/resource spawning on fixed map (Phase 5).
- [ ] Proper sprites & art v1: simple zombies/shooter/map, simple animation, smaller bullets (Phase 8).
- [ ] Art v2: animations, fire, light, parallax buildings, sound, reactions, blood trail (Phase 10).
- [ ] Sound.

## E. Meta / systems

- [ ] Menu: settings screen content (toggle tooltips — default ON, profile/user/stats,
      control remapping for shooter + zombie hotkeys), animations/background/art.
- [ ] Shooter AI (bot shooters).
- [ ] Levels: XP → level gain → skill tree upgrades.
- [ ] Online ranking + level-based matchmaking.
- [ ] Gear, saving, skill tree.

## Phases remaining

| Phase | Scope |
|-------|-------|
| 5 | Map generation (random NPC/resource spawning on fixed map) |
| 8 | Art v1 (simple sprites, 4× map, simple animation, smaller bullets) |
| 9a | Fix-list: shooter items (section C) |
| 9b | Fix-list: zombie items (section A) |
| 10 | Art v2 (animations, fire, light, parallax, sound, blood trails) |
| 11 | Playtest with real players |
| 12 | Landing page |
