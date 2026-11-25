# ZOMBIE COMMAND — design system

Source: Figma Make export ("Game HUD for Zombie Strategy 2", July 2026). This doc is the
in-repo condensation; `scripts/ui_style.gd` holds the same tokens as code and is the
single source of truth for UI styling (like `balance.gd` is for gameplay numbers).
The project-wide theme is built in code by the `UITheme` autoload (`scripts/ui_theme.gd`)
and applied to the root window at startup.

**Voice: BRUTAL · TACTICAL · INFECTED** — old CRT military terminal meets biohazard ops
center. No softness, nothing decorative, data-first.

## Palette (v2: the HUD kit mockup, Nov 2026)

The HUD kit mockup (https://claude.ai/artifact/5hAuRpAShsPkGvKjN127Mc) moved the
grounds and text from green-black to warm brown-black and ash. `UIStyle` holds
these values.

| Token | Hex | Use |
|---|---|---|
| ABYSS | `#080603` | page / screen ground |
| BUNKER | `#0e0a06` | panel surface |
| TRENCH | `#1c1409` | secondary surface |
| PANEL_DARK | `#120d05` | recessed panel |
| BAR_BG | `#060402` | HUD bars, modals |
| ASH | `#c4b48a` | body text |
| MOSS | `#7a6448` | muted labels |
| DIM | `#4a3820` | faint micro labels |
| INFECTION | `#39ff14` | you can press it, it's selected, or it's the zombie side |
| HEMORRHAGE | `#c0141a` | damage and nothing else |
| FAT_AMBER | `#d4780a` | fat zombie, merge→fat |
| FAST_CYAN | `#00b4c8` | fast zombie, shooter role |
| HOLD_BLUE `#5a9af0` / LURE_YELLOW `#c8920a` / PATROL_PURPLE `#a070e0` | | stance colours |
| WARN_YELLOW | `#c8920a` | 30–60% HP |
| BLOOD `#8b0000` / RUST `#7a3010` | | stains, rust accents |

Borders: a 1 px amber hairline, `rgba(160,100,30,0.32)` for dividers and
`0.16` for card edges.

## Typography

- **Share Tech Mono** (`resources/fonts/ShareTechMono-Regular.ttf`): numbers and
  labels, in caps with wide tracking (FontVariation glyph spacing ~3).
- **Rajdhani** (Regular/Medium/SemiBold/Bold): sentences only.
- **Special Elite**: titles only, never data.

## Rules

- **Colour:** green means you can press it, you have it selected, or it's the
  zombie side. Red means damage. Every other colour belongs to a zombie type, a
  stance or a kind of message.
- **Shape:** corners are sharp or cut, never round. Borders are 1 px hairlines.
- **Selected state:** a coloured 1 px border, a ~8% fill of the same colour and a
  soft glow. Inactive: a dim border and MOSS text.
- **HP colour:** >60% INFECTION, 30–60% WARN_YELLOW, <30% HEMORRHAGE
  (`UIStyle.hp_color`).
- **Placement:** alerts on the left, prompts under the crosshair or cursor in both
  roles. The shooter's map is top right. The commander's map sits in the bottom
  panel, as in Age of Empires II.
- **Survivor HUD (quiet):** health and hands are always on. The carried-weapons
  row stays small until you switch.
- **Command HUD (boxed):** everything is boxed. The bottom panel has three fixed
  slots: commands, selection, map. Changing the selection only changes the middle
  slot. Help is behind F1.
- **Commander map:** always the whole city. Black is unexplored and fills in as
  zombies see it. Lettered columns and numbered rows (A–F, 1–4), so messages
  and units can say where they are.
- **Debug:** the tuning sliders stay in the game, hidden. H brings them back.

## Building blocks

- `UIStyle.box(bg, border, glow, glow_size)` → sharp StyleBoxFlat.
- `UIStyle.font(path)` / `UIStyle.mono_spaced()` → cached fonts (work pre-import).
- Theme type variations (set `theme_type_variation` on a Control):
  `TitleLabel`, `HeadingLabel`, `MonoLabel`, `MicroLabel`, `BodyLabel`,
  `MenuItemButton`, `DangerButton`, `CardPanel`, `ModalPanel`.
- `UIStyle.cut_box(...)`: the cut-corner panel. `UIStyle.rough_fill(color)`: the
  jagged HP and ammo bar fill.
- `GameBg` (`scenes/ui/game_bg.gd`): full-screen ABYSS + 48 px grid + vignette.
- `LogoLockup` (`scenes/ui/logo_lockup.gd`) — ☣ mark + ZOMBIE/COMMAND wordmark, sm/md/lg.

## Screen inventory (mockup reference)

01 loading · 02 logo · 03 main menu · 04 single-player role select · 05 multiplayer hub ·
06 host (private/public) · 07 join (public/code) · 08 MP role select · 09 stance panel ·
10 zombie commander HUD · 11 shooter HUD · 12 settings (profile/controls/ui-hud/tooltips) ·
13 pause menu. Happy-path flows in the mockup's FLOW tab.
