# ZOMBIE COMMAND — design system

Source: Figma Make export ("Game HUD for Zombie Strategy 2", July 2026). This doc is the
in-repo condensation; `scripts/ui_style.gd` holds the same tokens as code and is the
single source of truth for UI styling (like `balance.gd` is for gameplay numbers).
The project-wide theme is built in code by the `UITheme` autoload (`scripts/ui_theme.gd`)
and applied to the root window at startup.

**Voice: BRUTAL · TACTICAL · INFECTED** — old CRT military terminal meets biohazard ops
center. No softness, nothing decorative, data-first.

## Palette

| Token | Hex | Use |
|---|---|---|
| ABYSS | `#0d0f0b` | page/screen ground |
| BUNKER | `#1a1e16` | panel surface |
| TRENCH | `#2a2e22` | secondary surface |
| PANEL_DARK | `#0a0c09` | recessed panel |
| BAR_BG | `#0b0d0a` | HUD bars, modals |
| ASH | `#c8d4b8` | body text |
| MOSS | `#6b7a5a` | muted labels |
| DIM | `#3a4a30` | faint micro labels |
| INFECTION | `#39ff14` | primary accent — interactive/selected ONLY |
| FAT_AMBER | `#ff8c00` | fat zombie, merge→fat |
| FAST_CYAN | `#00e5ff` | fast zombie, shooter role |
| HEMORRHAGE | `#b00020` | damage, death, destructive actions |
| WOUND `#f87171` / HOLD `#60a5fa` / LURE `#facc15` / PATROL `#c084fc` | | stance colors |
| WARN_YELLOW | `#ffcc00` | 30–60% HP |

Borders: 1px hairline green — `rgba(57,255,20,0.18)` panel divider, `0.10` card edge.

## Typography

- **Share Tech Mono** (`resources/fonts/ShareTechMono-Regular.ttf`) — ALL data, labels,
  headings, counters, buttons. Wide tracking (FontVariation glyph spacing ~3).
- **Rajdhani** (Regular/Medium/SemiBold/Bold) — body copy and descriptions only.
- Type scale (mockup): 36 hero · 20 screen heading · 13 menu item · 11 stat value ·
  10 button label · 9 HUD caption · 8 micro label. ALL-CAPS for mono text.

## Rules (do / don't)

- **0px corner radius everywhere. Always sharp.**
- Active/selected state = colored 1px border + ~8% same-color bg fill + soft glow
  (StyleBoxFlat shadow). Inactive = dim border + MOSS text.
- Acid green only for interactive/focus states — never for passive body text.
- Mono font for every number; never Rajdhani for data.
- No white backgrounds, no gradients (except the screen vignette), no drop shadows
  (except border glows).
- HP color rule: >60% INFECTION, 30–60% WARN_YELLOW, <30% HEMORRHAGE (`UIStyle.hp_color`).
- Minimap: uniform green dots for all zombie types (no per-type colors there);
  buildings ash rects; fog-of-war ~70% black.
- Role colors: shooter = FAST_CYAN, zombie = INFECTION.

## Building blocks

- `UIStyle.box(bg, border, glow, glow_size)` → sharp StyleBoxFlat.
- `UIStyle.font(path)` / `UIStyle.mono_spaced()` → cached fonts (work pre-import).
- Theme type variations (set `theme_type_variation` on a Control):
  `TitleLabel`, `HeadingLabel`, `MonoLabel`, `MicroLabel`, `BodyLabel`,
  `MenuItemButton`, `DangerButton`, `CardPanel`, `ModalPanel`.
- `GameBg` (`scenes/ui/game_bg.gd`) — full-screen ABYSS + 48px green grid + vignette.
- `LogoLockup` (`scenes/ui/logo_lockup.gd`) — ☣ mark + ZOMBIE/COMMAND wordmark, sm/md/lg.

## Screen inventory (mockup reference)

01 loading · 02 logo · 03 main menu · 04 single-player role select · 05 multiplayer hub ·
06 host (private/public) · 07 join (public/code) · 08 MP role select · 09 stance panel ·
10 zombie commander HUD · 11 shooter HUD · 12 settings (profile/controls/ui-hud/tooltips) ·
13 pause menu. Happy-path flows in the mockup's FLOW tab.
