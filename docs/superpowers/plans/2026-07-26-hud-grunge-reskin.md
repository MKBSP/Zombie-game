# HUD Grunge Reskin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the new "Game HUD for Zombie Strategy v2" Figma Make design (distressed blood/rust palette, Special Elite display font, cut-corner panels, grain/blood/crack/torn-edge decorations) into the live game's HUD, replacing the current clean cyberpunk-green look, with full visual fidelity including the mockup's grunge texture layer.

**Architecture:** `scripts/ui_style.gd` is already the single source of truth for every HUD color/font token (populated from the *previous* mockup export). This plan (1) swaps its tokens to the v2 palette and adds a Special Elite display font, (2) adds two new reusable visual primitives — a custom cut-corner `StyleBox` and a jagged-edge progress-bar `StyleBox` — and (3) adds a `Grunge` helper class with procedurally-drawn decorations (grain, blood, cracks, torn edges, hazard tape) that get wired into the two places the real HUD lives: `scenes/ui/hud.gd` (shooter bottom bar) and `scripts/zombie_controller.gd` (zombie-commander bottom bar, buttons, portraits, minimap frame).

**Tech Stack:** Godot 4.6.3 GDScript, Control-node UI (no external UI libraries). No new image assets — every decoration is either a procedurally generated texture (grain) or a custom `_draw()` call, to sidestep the project's "new PNG needs editor re-import" friction (see CLAUDE.md Gotchas).

## Global Constraints

- **All game-file edits go through the godot-ai MCP** (`script_create`, `script_patch`) — never write `.gd` files with a raw filesystem tool. The live Godot editor must stay in sync.
- **Never run headless Godot** (`--import`, `--script test/x.gd`) while the live editor is open — see CLAUDE.md Gotchas. Verification in this plan uses `project_run` + `logs_read` + `editor_screenshot` via the MCP, or an owner playtest.
- **Do not commit or push.** Do not run `git commit`/`git push` as part of any task in this plan. When the whole reskin is done and verified, suggest a short commit message and stop — the user (Mads) commits and pushes.
- **No `Co-Authored-By` / Claude attribution** anywhere (not applicable here since we aren't committing, but keep in mind if asked to commit later).
- Every new color must come from `UIStyle` constants — never hardcode a hex color directly in `hud.gd` / `zombie_controller.gd` (matches existing codebase convention).
- Source reference for exact values: `/Users/MadsTrundte/Downloads/Game HUD for Zombie Strategy v2/src/app/App.tsx` (the mockup). Do not edit anything under that Downloads path — it's the user's design reference, not part of this repo.
- Known, accepted scope cuts (don't re-litigate these mid-implementation):
  - No pixel-perfect per-panel `Stamp`/`BloodStain` placement inside dynamically-laid-out `HBoxContainer`/`VBoxContainer` rows (e.g. inside the MERGE OPS panel) — those rows resize at runtime and a hardcoded overlay rect would drift. Grunge decoration is applied at the bottom-bar level (grain + torn edge across the whole bar) and at elements with a *known static rect* (portraits, minimap frame) instead.
  - Buttons (`_add_btn`, `_style_merge_button`, rally button) get the new palette + cut-corner shape only, not a `BoxCracks` overlay — a Control added as a child of a `Button` draws *on top of* the button's own label (Godot draws parent-then-children, unlike the mockup's DOM stacking), which would visually interfere with legibility.
  - The mockup's `ControlGroupBar` (1–9 slot squares) has no corresponding visual widget in the live game yet (only the save/recall keybinding logic exists) — that's a missing *feature*, not a style gap, so it's out of scope here.

---

### Task 1: Source the Special Elite display font

**Files:**
- Create: `resources/fonts/SpecialElite-Regular.ttf`

**Interfaces:**
- Produces: a font file at `res://resources/fonts/SpecialElite-Regular.ttf` that Task 2's `UIStyle.FONT_DISPLAY` constant points to.

- [ ] **Step 1: Download the font**

Special Elite is an open-source Google Font (already how `Rajdhani-*.ttf` and `ShareTechMono-Regular.ttf` got into `resources/fonts/` previously). Fetch it from the Google Fonts GitHub mirror, trying both license subfolders since the exact one isn't certain ahead of time:

```bash
cd "/Users/MadsTrundte/Desktop/zombie-game"
curl -fsSL -o resources/fonts/SpecialElite-Regular.ttf \
  "https://raw.githubusercontent.com/google/fonts/main/apache/specialelite/SpecialElite-Regular.ttf" \
  || curl -fsSL -o resources/fonts/SpecialElite-Regular.ttf \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/specialelite/SpecialElite-Regular.ttf"
```

Expected: the command exits 0 and `resources/fonts/SpecialElite-Regular.ttf` exists and is a nonzero-size binary file (a few hundred KB).

- [ ] **Step 2: Verify the file is a real TTF, not an HTML error page**

```bash
file resources/fonts/SpecialElite-Regular.ttf
```

Expected output contains `TrueType Font data` (not `HTML document` or `ASCII text` — that would mean both URLs 404'd and curl saved an error body).

- [ ] **Step 3: Let the live editor import it**

No `.import` file is strictly required — `UIStyle.font()` (see Task 2) falls back to `FontFile.load_dynamic_font()` for any TTF that Godot hasn't imported yet, so the font works immediately at runtime either way. Still, switch focus to the Godot editor window once (or call `mcp__godot-ai__filesystem_manage` with `op="reimport"` targeting the new path) so the editor picks it up for its own previews and generates the `.import` sidecar file to commit later. Do **not** run a headless `--import`.

- [ ] **Step 4: Confirm via editor_state that the project is still ready**

Call the MCP `editor_state` tool. Expected: `"readiness": "ready"` (no import/crash loop triggered by the new file).

---

### Task 2: Rewrite `scripts/ui_style.gd` color/font tokens

**Files:**
- Modify: `scripts/ui_style.gd:8-38` (grounds/text/accents/border constants + fonts section)
- Modify: `scripts/ui_style.gd` (append `cut_box()` and `rough_fill()` after the existing `box()` function)

**Interfaces:**
- Consumes: `CutCornerStyleBox` (Task 3), `RoughFillStyleBox` (Task 4) — referenced by class name only, no `preload()` needed (both get a `class_name`, which Godot resolves as a global identifier, same pattern as every other `class_name` script in this project).
- Produces: `UIStyle.BLOOD`, `UIStyle.RUST`, `UIStyle.FONT_DISPLAY`, `UIStyle.cut_box(bg, border, glow := Color.TRANSPARENT, glow_size := 0, cut_size := 5.0) -> CutCornerStyleBox`, `UIStyle.rough_fill(color: Color) -> RoughFillStyleBox`. All existing constant *names* (`ABYSS`, `BUNKER`, `TRENCH`, `PANEL_DARK`, `BAR_BG`, `ASH`, `MOSS`, `DIM`, `INFECTION`, `FAT_AMBER`, `FAST_CYAN`, `HEMORRHAGE`, `WOUND`, `HOLD_BLUE`, `LURE_YELLOW`, `PATROL_PURPLE`, `WARN_YELLOW`, `BORDER`, `BORDER_DIM`) are unchanged — only their *values* change — so every existing call site across the codebase keeps compiling untouched.

- [ ] **Step 1: Patch the color tokens**

Use the MCP `script_patch` tool on `res://scripts/ui_style.gd`:

old_text:
```gdscript
# ── Grounds ─────────────────────────────────────────────────────────────────
const ABYSS := Color("0d0f0b")        # page / screen ground
const BUNKER := Color("1a1e16")       # panel surface
const TRENCH := Color("2a2e22")       # secondary surface
const PANEL_DARK := Color("0a0c09")   # recessed panel
const BAR_BG := Color("0b0d0a")       # HUD top/bottom bars, modals

# ── Text ────────────────────────────────────────────────────────────────────
const ASH := Color("c8d4b8")          # body text
const MOSS := Color("6b7a5a")         # muted labels
const DIM := Color("3a4a30")          # faint micro labels

# ── Accents ─────────────────────────────────────────────────────────────────
const INFECTION := Color("39ff14")    # primary accent / interactive / selected
const FAT_AMBER := Color("ff8c00")    # fat zombie / merge fat
const FAST_CYAN := Color("00e5ff")    # fast zombie / shooter role
const HEMORRHAGE := Color("b00020")   # damage / death / destructive
const WOUND := Color("f87171")        # damage stat / aggressive stance
const HOLD_BLUE := Color("60a5fa")    # hold-ground stance
const LURE_YELLOW := Color("facc15")  # lure stance
const PATROL_PURPLE := Color("c084fc")# patrol stance
const WARN_YELLOW := Color("ffcc00")  # mid HP warning

# ── Borders (hairline green) ────────────────────────────────────────────────
const BORDER := Color(0.224, 1.0, 0.078, 0.18)      # panel divider
const BORDER_DIM := Color(0.224, 1.0, 0.078, 0.10)  # card edge
```

new_text:
```gdscript
# ── Grounds ─────────────────────────────────────────────────────────────────
const ABYSS := Color("080603")        # page / screen ground
const BUNKER := Color("0e0a06")       # panel surface
const TRENCH := Color("1c1409")       # secondary surface
const PANEL_DARK := Color("120d05")   # recessed panel
const BAR_BG := Color("060402")       # HUD top/bottom bars, modals

# ── Text ────────────────────────────────────────────────────────────────────
const ASH := Color("c4b48a")          # body text
const MOSS := Color("7a6448")         # muted labels
const DIM := Color("4a3820")          # faint micro labels

# ── Accents ─────────────────────────────────────────────────────────────────
const INFECTION := Color("39ff14")    # primary accent / interactive / selected
const FAT_AMBER := Color("d4780a")    # fat zombie / merge fat
const FAST_CYAN := Color("00b4c8")    # fast zombie / shooter role
const HEMORRHAGE := Color("c0141a")   # damage / death / destructive
const WOUND := Color("c0141a")        # damage stat / aggressive stance
const HOLD_BLUE := Color("5a9af0")    # hold-ground stance
const LURE_YELLOW := Color("c8920a")  # lure stance
const PATROL_PURPLE := Color("a070e0")# patrol stance
const WARN_YELLOW := Color("c8920a")  # mid HP warning
const BLOOD := Color("8b0000")        # deep blood — stains, splats, drips
const RUST := Color("7a3010")         # rust accent

# ── Borders (hairline rust) ─────────────────────────────────────────────────
const BORDER := Color(0.627, 0.392, 0.118, 0.32)      # panel divider
const BORDER_DIM := Color(0.627, 0.392, 0.118, 0.16)  # card edge
```

- [ ] **Step 2: Add the display font constant**

old_text:
```gdscript
# ── Fonts ───────────────────────────────────────────────────────────────────
const FONT_MONO := "res://resources/fonts/ShareTechMono-Regular.ttf"
const FONT_BODY := "res://resources/fonts/Rajdhani-Medium.ttf"
const FONT_BODY_BOLD := "res://resources/fonts/Rajdhani-Bold.ttf"
```

new_text:
```gdscript
# ── Fonts ───────────────────────────────────────────────────────────────────
const FONT_MONO := "res://resources/fonts/ShareTechMono-Regular.ttf"
const FONT_BODY := "res://resources/fonts/Rajdhani-Medium.ttf"
const FONT_BODY_BOLD := "res://resources/fonts/Rajdhani-Bold.ttf"
const FONT_DISPLAY := "res://resources/fonts/SpecialElite-Regular.ttf"
```

- [ ] **Step 3: Append `cut_box()` and `rough_fill()`**

old_text:
```gdscript
	if glow_size > 0:
		sb.shadow_color = glow
		sb.shadow_size = glow_size
	return sb
```

new_text:
```gdscript
	if glow_size > 0:
		sb.shadow_color = glow
		sb.shadow_size = glow_size
	return sb


## Cut-corner ("clip-path octagon") panel background — the mockup's signature
## button/portrait/badge shape. Same call signature as box(); `cut_size` is
## the corner notch depth in px.
static func cut_box(bg: Color, border: Color, glow := Color.TRANSPARENT, glow_size := 0, cut_size := 5.0) -> CutCornerStyleBox:
	var sb := CutCornerStyleBox.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width = 1.0
	sb.cut = cut_size
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	if glow_size > 0:
		sb.shadow_color = glow
		sb.shadow_size = glow_size
	return sb


## Jagged-leading-edge fill for HP/ammo progress bars (mockup's RoughBar).
static func rough_fill(color: Color) -> RoughFillStyleBox:
	var sb := RoughFillStyleBox.new()
	sb.bg_color = color
	return sb
```

- [ ] **Step 4: Verify the project still boots clean**

This task references `CutCornerStyleBox`/`RoughFillStyleBox`, which don't exist yet until Tasks 3–4 — so **do this task's verification only after Tasks 3 and 4 are also applied** (or apply Tasks 2, 3, 4 together before the first verification pass). Then call MCP `project_run` (mode `"main"`) and `logs_read` (`source="editor"`, then `source="game"`): expect zero `SCRIPT ERROR` / `Parse Error` lines. Stop the run afterward with `project_manage(op="stop")`.

---

### Task 3: Create `CutCornerStyleBox`

**Files:**
- Create: `scripts/ui/cut_corner_stylebox.gd`

**Interfaces:**
- Produces: `class_name CutCornerStyleBox extends StyleBox` with properties `bg_color: Color`, `border_color: Color`, `border_width: float`, `cut: float`. Consumed by `UIStyle.cut_box()` (Task 2).

- [ ] **Step 1: Create the file via the MCP `script_create` tool**

Path: `res://scripts/ui/cut_corner_stylebox.gd`

```gdscript
class_name CutCornerStyleBox
extends StyleBox
## Octagonal "cut corner" panel background — GDScript port of the mockup's
## `clip-path: polygon(...)` panels (CUT_SM/CUT_MD in App.tsx). Godot's
## StyleBoxFlat only supports rounded corners, not angled cuts, so this
## draws the octagon directly via the low-level CanvasItem polygon API.

var bg_color: Color = Color.BLACK
var border_color: Color = Color.TRANSPARENT
var border_width: float = 1.0
var cut: float = 5.0

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var c: float = minf(cut, minf(rect.size.x, rect.size.y) * 0.5)
	var p := rect.position
	var s := rect.size
	var points := PackedVector2Array([
		p + Vector2(c, 0),         p + Vector2(s.x - c, 0),
		p + Vector2(s.x, c),       p + Vector2(s.x, s.y - c),
		p + Vector2(s.x - c, s.y), p + Vector2(c, s.y),
		p + Vector2(0, s.y - c),   p + Vector2(0, c),
	])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([bg_color]))
	if border_width > 0.0 and border_color.a > 0.0:
		var loop := points.duplicate()
		loop.append(points[0])
		RenderingServer.canvas_item_add_polyline(
			to_canvas_item, loop, PackedColorArray([border_color]), border_width, true)

func _get_minimum_size() -> Vector2:
	return Vector2(cut * 2.0, cut * 2.0)
```

- [ ] **Step 2: Verify no parse error on this file alone**

The MCP `script_create`/`script_patch` response includes a `diagnostics` field — expect an empty `diagnostics` array (or `diagnostics_status: "checked"` with no error entries) in the tool result for this call.

---

### Task 4: Create `RoughFillStyleBox`

**Files:**
- Create: `scripts/ui/rough_fill_stylebox.gd`

**Interfaces:**
- Produces: `class_name RoughFillStyleBox extends StyleBox` with property `bg_color: Color`. Consumed by `UIStyle.rough_fill()` (Task 2) and applied as a `ProgressBar`'s `"fill"` theme stylebox override (Godot passes this StyleBox only the *currently filled* sub-rect, already scaled to the bar's value — so drawing a jagged point at the rect's right edge is enough to get the mockup's "lumpy, degraded" leading edge).

- [ ] **Step 1: Create the file via the MCP `script_create` tool**

Path: `res://scripts/ui/rough_fill_stylebox.gd`

```gdscript
class_name RoughFillStyleBox
extends StyleBox
## Jagged-leading-edge progress-bar fill — GDScript port of the mockup's
## <RoughBar>. Godot gives a "fill" StyleBox only the currently-filled
## sub-rect (already sized to the bar's value), so a triangular notch on
## the right edge reproduces the mockup's lumpy fill silhouette.

var bg_color: Color = Color.WHITE

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var w := rect.size.x
	var h := rect.size.y
	var jag := minf(h * 0.6, 4.0)
	var p := rect.position
	var points := PackedVector2Array([
		p,
		p + Vector2(w, 0),
		p + Vector2(w + jag, h * 0.5),
		p + Vector2(w, h),
		p + Vector2(0, h),
	])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, points, PackedColorArray([bg_color]))
	# Leading-edge highlight sliver, matching the mockup's white glint.
	var hi := PackedVector2Array([p + Vector2(w - 1.0, 0), p + Vector2(w, 0),
		p + Vector2(w, h), p + Vector2(w - 1.0, h)])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, hi, PackedColorArray([Color(1, 1, 1, 0.12)]))
```

- [ ] **Step 2: Verify no parse error, then run the combined Task 2+3+4 verification**

Now that `CutCornerStyleBox` and `RoughFillStyleBox` both exist, run the Task 2 Step 4 verification (project_run → logs_read → project_manage stop). Expect a clean boot with zero script errors — `UIStyle` compiling successfully is what confirms all three tasks wired together correctly.

---

### Task 5: Create the `Grunge` decorator library

**Files:**
- Create: `scripts/ui/grunge.gd`

**Interfaces:**
- Produces: `class_name Grunge extends RefCounted` with:
  - `static func grain_texture() -> ImageTexture` (cached 64×64 noise texture)
  - `static func grain_overlay(opacity: float = 0.13) -> TextureRect` (tiled grain, `MOUSE_FILTER_IGNORE`)
  - Nested classes, each `extends Control`, each self-contained (draws using only its own `size`, safe to add to any container): `CrackLines.new(opacity := 0.12)`, `BoxCracks.new(opacity := 0.18)`, `Scratches.new(opacity := 0.05)`, `WornEdge.new(side := "bottom")`, `HazardTape.new()`, `BloodSplat.new(opacity := 0.28)`, `BloodStain.new(opacity := 0.1)`, `BloodDrip.new(x_pct := 0.5, h := 18.0, opacity := 0.5)` (also exposes `set_pct(p: float)` for live repositioning), `BulletHole.new()`. Plus `Stamp.new(text: String, color := Grunge.BLOOD)` which `extends Label`.
- Consumes: nothing outside core Godot classes (self-contained, no dependency on `UIStyle` — keeps this file reusable/testable independent of the theme singleton).

- [ ] **Step 1: Create the file via the MCP `script_create` tool**

Path: `res://scripts/ui/grunge.gd`

```gdscript
class_name Grunge
extends RefCounted
## Distress/decay decorators ported from the "Game HUD for Zombie Strategy v2"
## Figma Make mockup (src/app/App.tsx): <Grain>, <CrackLines>, <BloodSplat>,
## etc. Each nested class is a small custom-draw Control — add as a child of
## a panel. Everything here is generated or drawn procedurally (no image
## assets, so no .import step — see CLAUDE.md's "new image assets" gotcha).

const BLOOD := Color("8b0000")
const INK := Color("120d05")

static var _grain_tex: ImageTexture = null


## 64×64 tileable monochrome noise — approximates the mockup's feTurbulence
## film-grain filter. Built once and cached for reuse across every panel.
static func grain_texture() -> ImageTexture:
	if _grain_tex != null:
		return _grain_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in size:
		for x in size:
			var v := rng.randf()
			img.set_pixel(x, y, Color(v, v, v, v))
	_grain_tex = ImageTexture.create_from_image(img)
	return _grain_tex


## A TextureRect that tiles grain_texture() at low opacity across whatever
## rect it's given — the mockup's `<Grain opacity=.. />`.
static func grain_overlay(opacity: float = 0.13) -> TextureRect:
	var t := TextureRect.new()
	t.texture = grain_texture()
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate = Color(1, 1, 1, opacity)
	return t


## Faint diagonal crack lines across a panel — mockup's <CrackLines>.
class CrackLines:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.12) -> void:
		draw_color = Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.15, 0), Vector2(w * 0.22, h * 0.18), Vector2(w * 0.18, h * 0.26),
			Vector2(w * 0.28, h * 0.55), Vector2(w * 0.24, h)]), draw_color, 0.7)
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.85, h * 0.08), Vector2(w * 0.80, h * 0.35),
			Vector2(w * 0.84, h * 0.48), Vector2(w * 0.76, h)]), draw_color, 0.5)


## Smaller cracks for individual buttons/boxes — mockup's <BoxCracks>.
class BoxCracks:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.18) -> void:
		draw_color = Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.05, h * 0.2), Vector2(w * 0.18, h * 0.35),
			Vector2(w * 0.12, h * 0.55), Vector2(w * 0.20, h * 0.8)]), draw_color, 0.5)
		draw_polyline(PackedVector2Array([
			Vector2(w * 0.8, h * 0.1), Vector2(w * 0.75, h * 0.4), Vector2(w * 0.8, h * 0.6)]), draw_color, 0.4)


## Fine surface scratches — mockup's <Scratches>.
class Scratches:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.05) -> void:
		draw_color = Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_line(Vector2(w * 0.07, h * 0.02), Vector2(w * 0.10, h * 0.98), draw_color, 0.6)
		draw_line(Vector2(w * 0.41, 0), Vector2(w * 0.38, h * 0.6), draw_color, 0.4)
		draw_line(Vector2(w * 0.72, h * 0.18), Vector2(w * 0.75, h * 0.88), draw_color, 0.5)


## Jagged torn-paper edge on one side — mockup's <WornEdge side="top|bottom">.
class WornEdge:
	extends Control
	var edge_side: String
	func _init(side: String = "bottom") -> void:
		edge_side = side
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		var pts := PackedVector2Array()
		var n := 24
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in range(n + 1):
			var x := w * float(i) / float(n)
			var jag := rng.randf_range(0.0, h * 0.6)
			var y := jag if edge_side == "bottom" else h - jag
			pts.append(Vector2(x, y))
		draw_polyline(pts, Color(Grunge.INK.r, Grunge.INK.g, Grunge.INK.b, 0.9), 2.0)


## Repeating diagonal hazard-tape stripe — mockup's <HazardTape>.
class HazardTape:
	extends Control
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := maxf(size.y, 1.0)
		var stripe := 18.0
		var x := -stripe
		while x < w + stripe:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x, h), Vector2(x + h, 0), Vector2(x + h + 8.0, 0), Vector2(x + 8.0, h)]),
				Color("c8920a", 0.55))
			x += stripe


## Irregular blood-splatter blob — mockup's <BloodSplat>.
class BloodSplat:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.28) -> void:
		draw_color = Color(Grunge.BLOOD.r, Grunge.BLOOD.g, Grunge.BLOOD.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := minf(w, h) * 0.32
		if r <= 0.0:
			return
		draw_circle(Vector2(w * 0.55, h * 0.5), r, draw_color)
		draw_circle(Vector2(w * 0.78, h * 0.72), r * 0.28, draw_color)
		draw_circle(Vector2(w * 0.26, h * 0.8), r * 0.2, draw_color)


## Flat irregular stain with its own fixed size (independent of parent
## layout) — mockup's <BloodStain>.
class BloodStain:
	extends Control
	var draw_color: Color
	func _init(opacity: float = 0.1) -> void:
		draw_color = Color(Grunge.BLOOD.r, Grunge.BLOOD.g, Grunge.BLOOD.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(80, 50)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0 or h <= 0.0:
			return
		draw_colored_polygon(PackedVector2Array([
			Vector2(w * 0.12, h * 0.16), Vector2(w * 0.32, h * 0.02), Vector2(w * 0.7, h * 0.06),
			Vector2(w * 0.94, h * 0.28), Vector2(w * 0.9, h * 0.66), Vector2(w * 0.58, h * 0.94),
			Vector2(w * 0.22, h * 0.88), Vector2(w * 0.03, h * 0.58)]), draw_color)


## A drip hanging below a bar — mockup's <BloodDrip>. `set_pct()` lets a
## caller reposition it live (e.g. tracking a health bar's current fill).
class BloodDrip:
	extends Control
	var x_pct: float
	var drip_h: float
	var draw_color: Color
	func _init(x_pct_in: float = 0.5, h: float = 18.0, opacity: float = 0.5) -> void:
		x_pct = x_pct_in
		drip_h = h
		draw_color = Color(Grunge.BLOOD.r, Grunge.BLOOD.g, Grunge.BLOOD.b, opacity)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, h)
	func set_pct(p: float) -> void:
		x_pct = p
		queue_redraw()
	func _draw() -> void:
		var x := size.x * x_pct
		draw_rect(Rect2(x - 1.0, 0, 2.0, drip_h * 0.6), draw_color)
		draw_circle(Vector2(x, drip_h * 0.8), 2.5, draw_color)


## Small rotated stenciled badge — mockup's <Stamp text="...">.
class Stamp:
	extends Label
	func _init(stamp_text: String, color: Color = Grunge.BLOOD) -> void:
		text = stamp_text
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		theme_type_variation = "MicroLabel"
		add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.4))
		rotation_degrees = -9.0


## Small bullet-hole decal — mockup's <BulletHole>.
class BulletHole:
	extends Control
	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_circle(Vector2(7, 7), 6.0, Color(0.07, 0.05, 0.02, 0.85))
		draw_circle(Vector2(7, 7), 2.5, Color.BLACK)
		draw_line(Vector2(7, 1), Vector2(4.5, 4), Color(0, 0, 0, 0.7), 0.6)
		draw_line(Vector2(7, 1), Vector2(9.5, 3), Color(0, 0, 0, 0.7), 0.6)
```

- [ ] **Step 2: Verify no parse error**

Check the `script_create` tool result's `diagnostics` field is empty.

---

### Task 6: Reskin `scenes/ui/hud.gd` (shooter bottom bar)

**Files:**
- Modify: `scenes/ui/hud.gd:11-15` (member vars)
- Modify: `scenes/ui/hud.gd:103-112` (`_on_hp_changed`)
- Modify: `scenes/ui/hud.gd:186-198` (HEALTH section build, inside `_apply_zc_style`)
- Modify: `scenes/ui/hud.gd:233-237` (tail of `_apply_zc_style`)

**Interfaces:**
- Consumes: `UIStyle.rough_fill()` (Task 2), `UIStyle.box()` (existing), `Grunge.grain_overlay()`, `Grunge.WornEdge`, `Grunge.BloodDrip` + its `set_pct()` (Task 5).
- Produces: no new public interface — visual-only change to the existing shooter HUD.

- [ ] **Step 1: Add a member var to hold the HP bar's blood drip**

old_text:
```gdscript
var shooter: Node2D = null
var master_zombie: Node2D = null
var debug_visible: bool = true
var _toast_tween: Tween = null
var _ammo_blocks: AmmoBlocks = null
```

new_text:
```gdscript
var shooter: Node2D = null
var master_zombie: Node2D = null
var debug_visible: bool = true
var _toast_tween: Tween = null
var _ammo_blocks: AmmoBlocks = null
var _hp_drip: Grunge.BloodDrip = null
```

- [ ] **Step 2: Swap the HP bar fill to the jagged RoughFillStyleBox, and show the drip below 30% HP**

old_text:
```gdscript
func _on_hp_changed(new_hp: int) -> void:
	hp_bar.value = new_hp
	hp_label.text = str(new_hp)
	# HP color rule (>60% green / 30-60% warn / <30% crit) on bar + number.
	var c := UIStyle.hp_color(new_hp / float(hp_bar.max_value))
	var fill := StyleBoxFlat.new()
	fill.bg_color = c
	fill.set_corner_radius_all(0)
	hp_bar.add_theme_stylebox_override("fill", fill)
	hp_label.add_theme_color_override("font_color", c)
```

new_text:
```gdscript
func _on_hp_changed(new_hp: int) -> void:
	hp_bar.value = new_hp
	hp_label.text = str(new_hp)
	# HP color rule (>60% green / 30-60% warn / <30% crit) on bar + number.
	var pct := new_hp / float(hp_bar.max_value)
	var c := UIStyle.hp_color(pct)
	hp_bar.add_theme_stylebox_override("fill", UIStyle.rough_fill(c))
	hp_label.add_theme_color_override("font_color", c)
	# Mockup rule: a blood drip appears below the bar once HP < 30%.
	if _hp_drip != null:
		_hp_drip.visible = pct < 0.3
		_hp_drip.set_pct(pct)
```

- [ ] **Step 3: Give the HP bar an explicit background stylebox, and add the (initially hidden) drip node**

old_text:
```gdscript
	hp_bar.reparent(hp_row)
	hp_bar.custom_minimum_size = Vector2(150, 12)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_label.reparent(hp_row)
```

new_text:
```gdscript
	hp_bar.reparent(hp_row)
	hp_bar.custom_minimum_size = Vector2(150, 12)
	hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.add_theme_stylebox_override("background", UIStyle.box(UIStyle.PANEL_DARK, UIStyle.BORDER_DIM))
	hp_label.reparent(hp_row)
	# hp_section is a VBoxContainer (see _bar_section below), so adding the
	# drip here — as a sibling *after* hp_row, not a child of it — stacks it
	# directly below the HP bar instead of squeezing into the HBox layout.
	_hp_drip = Grunge.BloodDrip.new(0.0, 14.0, 0.8)
	_hp_drip.custom_minimum_size.x = 150
	_hp_drip.visible = false
	hp_section.add_child(_hp_drip)
```

- [ ] **Step 4: Add the grain + torn-edge overlay across the whole bottom bar**

old_text:
```gdscript
	# Toast + debug coords restyle (stay where they are).
	toast_label.add_theme_font_override("font", UIStyle.mono_spaced())
	toast_label.offset_top = -170.0
	toast_label.offset_bottom = -140.0
	debug_coords.theme_type_variation = "MicroLabel"
```

new_text:
```gdscript
	# Toast + debug coords restyle (stay where they are).
	toast_label.add_theme_font_override("font", UIStyle.mono_spaced())
	toast_label.offset_top = -170.0
	toast_label.offset_bottom = -140.0
	debug_coords.theme_type_variation = "MicroLabel"

	# Distress overlay — grain + torn top edge across the bottom bar, ported
	# from the mockup's <HUDSample>. Added last (drawn on top of `bar`) but
	# before toast/debug labels stay on top since those were created earlier
	# and are only repositioned here, not re-added.
	var grain := Grunge.grain_overlay(0.12)
	grain.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	grain.offset_top = -68.0
	add_child(grain)
	move_child(grain, bar.get_index() + 1)

	var worn := Grunge.WornEdge.new("top")
	worn.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	worn.offset_top = -68.0
	worn.offset_bottom = -60.0
	add_child(worn)
	move_child(worn, grain.get_index() + 1)
```

- [ ] **Step 5: Verify in the live editor**

Call MCP `project_run` (mode `"main"`), then `logs_read` (`source="all"`, `count=80`) — expect zero `SCRIPT ERROR` lines referencing `hud.gd`. This flow needs an active shooter to reach the HUD; if `game_capture_ready` is false for `editor_screenshot`, fall back to a `logs_read` clean-boot check (per CLAUDE.md's MCP-capture-bridge gotcha) and ask the user to eyeball the bottom bar in a quick playtest. Then `project_manage(op="stop")`.

---

### Task 7: Reskin `scripts/zombie_controller.gd` (bottom bar, buttons, portraits)

**Files:**
- Modify: `scripts/zombie_controller.gd:694-700` (end of `_build_bottom_panel` — append overlay)
- Modify: `scripts/zombie_controller.gd:766-773` (`PortraitStrip._draw()` — add crack line)
- Modify: `scripts/zombie_controller.gd:790-799` (`_add_btn`)
- Modify: `scripts/zombie_controller.gd:816-823` (`_style_merge_button`)
- Modify: `scripts/zombie_controller.gd:901-906` (`_create_rally_button`)

**Interfaces:**
- Consumes: `UIStyle.cut_box()` (Task 2), `Grunge.grain_overlay()`, `Grunge.WornEdge`, `Grunge.HazardTape` (Task 5).
- Produces: no new public interface — visual-only.

- [ ] **Step 1: Add the grain/torn-edge/hazard-tape overlay to the bottom bar**

old_text:
```gdscript
	# — Merge ops panel likewise —
	if fast_button:
		var merge_panel: Control = fast_button.get_parent()
		merge_panel.reparent(row)
		merge_panel.custom_minimum_size = Vector2(216, 0)
		if merge_panel is BoxContainer:
			merge_panel.alignment = BoxContainer.ALIGNMENT_CENTER
```

new_text:
```gdscript
	# — Merge ops panel likewise —
	if fast_button:
		var merge_panel: Control = fast_button.get_parent()
		merge_panel.reparent(row)
		merge_panel.custom_minimum_size = Vector2(216, 0)
		if merge_panel is BoxContainer:
			merge_panel.alignment = BoxContainer.ALIGNMENT_CENTER

	# Distress overlay — grain + torn top edge + a hazard-tape divider just
	# above the bar, ported from the mockup's <HUDSample>/<Section>. Added
	# to `overlay` (a sibling of `bar`, not a child of `row`) so it can't
	# disturb the HBoxContainer's button/label layout.
	var grain := Grunge.grain_overlay(0.1)
	grain.anchor_left = 0.0
	grain.anchor_right = 1.0
	grain.anchor_top = 1.0
	grain.anchor_bottom = 1.0
	grain.offset_left = m + sz + 12.0
	grain.offset_right = -0.0
	grain.offset_top = -BAR_H
	grain.offset_bottom = 0.0
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(grain)

	var worn := Grunge.WornEdge.new("top")
	worn.anchor_left = 0.0
	worn.anchor_right = 1.0
	worn.anchor_top = 1.0
	worn.anchor_bottom = 1.0
	worn.offset_left = m + sz + 12.0
	worn.offset_right = -0.0
	worn.offset_top = -BAR_H
	worn.offset_bottom = -BAR_H + 8.0
	overlay.add_child(worn)

	var tape := Grunge.HazardTape.new()
	tape.anchor_left = 0.0
	tape.anchor_right = 1.0
	tape.anchor_top = 1.0
	tape.anchor_bottom = 1.0
	tape.offset_left = m + sz + 12.0
	tape.offset_right = -0.0
	tape.offset_top = -BAR_H - 10.0
	tape.offset_bottom = -BAR_H
	overlay.add_child(tape)
```

- [ ] **Step 2: Add a weathering crack line to each selection portrait**

old_text:
```gdscript
			var x := i * (BOX + GAP)
			var box := Rect2(Vector2(x, 0), Vector2(BOX, BOX))
			draw_rect(box, UIStyle.fade(accent, 0.08))
			draw_rect(box, UIStyle.fade(accent, 0.7), false, 1.0)
```

new_text:
```gdscript
			var x := i * (BOX + GAP)
			var box := Rect2(Vector2(x, 0), Vector2(BOX, BOX))
			draw_rect(box, UIStyle.fade(accent, 0.08))
			draw_rect(box, UIStyle.fade(accent, 0.7), false, 1.0)
			# Weathering: a faint crack across the portrait frame.
			draw_polyline(PackedVector2Array([
				Vector2(x + BOX * 0.15, 0), Vector2(x + BOX * 0.22, BOX * 0.4),
				Vector2(x + BOX * 0.18, BOX * 0.6), Vector2(x + BOX * 0.28, BOX)]),
				UIStyle.fade(UIStyle.ASH, 0.14), 0.6)
```

- [ ] **Step 3: Switch mode/stance buttons to the cut-corner stylebox**

old_text:
```gdscript
	b.add_theme_stylebox_override("normal",
		UIStyle.box(UIStyle.fade(UIStyle.PANEL_DARK, 0.9), UIStyle.BORDER_DIM))
	var hot := UIStyle.box(
		UIStyle.fade(accent, 0.10), accent, UIStyle.fade(accent, 0.20), 5)
```

new_text:
```gdscript
	b.add_theme_stylebox_override("normal",
		UIStyle.cut_box(UIStyle.fade(UIStyle.PANEL_DARK, 0.9), UIStyle.BORDER_DIM))
	var hot := UIStyle.cut_box(
		UIStyle.fade(accent, 0.10), accent, UIStyle.fade(accent, 0.20), 5)
```

- [ ] **Step 4: Switch merge-op buttons to the cut-corner stylebox**

old_text:
```gdscript
	b.add_theme_stylebox_override("normal",
		UIStyle.box(UIStyle.fade(accent, 0.05), UIStyle.fade(accent, 0.6)))
	var hot := UIStyle.box(
		UIStyle.fade(accent, 0.12), accent, UIStyle.fade(accent, 0.25), 6)
	b.add_theme_stylebox_override("disabled",
		UIStyle.box(Color.TRANSPARENT, UIStyle.BORDER_DIM))
```

new_text:
```gdscript
	b.add_theme_stylebox_override("normal",
		UIStyle.cut_box(UIStyle.fade(accent, 0.05), UIStyle.fade(accent, 0.6)))
	var hot := UIStyle.cut_box(
		UIStyle.fade(accent, 0.12), accent, UIStyle.fade(accent, 0.25), 6)
	b.add_theme_stylebox_override("disabled",
		UIStyle.cut_box(Color.TRANSPARENT, UIStyle.BORDER_DIM))
```

- [ ] **Step 5: Switch the rally button to the cut-corner stylebox**

old_text:
```gdscript
	btn.add_theme_stylebox_override("normal",
		UIStyle.box(UIStyle.fade(UIStyle.PANEL_DARK, 0.9), UIStyle.fade(RALLY_GOLD, 0.5)))
	var hot := UIStyle.box(
		UIStyle.fade(RALLY_GOLD, 0.12), RALLY_GOLD, UIStyle.fade(RALLY_GOLD, 0.25), 5)
```

new_text:
```gdscript
	btn.add_theme_stylebox_override("normal",
		UIStyle.cut_box(UIStyle.fade(UIStyle.PANEL_DARK, 0.9), UIStyle.fade(RALLY_GOLD, 0.5)))
	var hot := UIStyle.cut_box(
		UIStyle.fade(RALLY_GOLD, 0.12), RALLY_GOLD, UIStyle.fade(RALLY_GOLD, 0.25), 5)
```

- [ ] **Step 6: Verify in the live editor**

`project_run` (mode `"main"`) → `logs_read` (`source="all"`, `count=100`), expect zero `SCRIPT ERROR` referencing `zombie_controller.gd`. Reaching the Zombie Controller view requires playing as the zombie role — if that's not immediately reachable headlessly, rely on the clean-boot log check plus an owner playtest per CLAUDE.md. Then `project_manage(op="stop")`.

---

### Task 8: Reskin the minimap frame overlay

**Files:**
- Modify: `scripts/zombie_controller.gd:103-104` (right after `overlay.add_child(minimap)`)

**Interfaces:**
- Consumes: `Grunge.grain_overlay()`, `Grunge.CrackLines` (Task 5).
- Produces: no new public interface. `minimap.gd` itself is untouched — its live-drawn frame border already inherits the new rust `UIStyle.BORDER` color automatically from Task 2, no code change needed there.

- [ ] **Step 1: Add grain + crack-line decoration on top of the live minimap**

old_text:
```gdscript
		overlay.add_child(minimap)
		minimap.setup(fog_zc, camera)
```

new_text:
```gdscript
		overlay.add_child(minimap)
		minimap.setup(fog_zc, camera)

		# Distress overlay on top of the live minimap — grain + a crack line,
		# matching the mockup's <MinimapSample>. mouse_filter IGNORE keeps
		# minimap click/drag panning working underneath.
		var mm_grain := Grunge.grain_overlay(0.15)
		mm_grain.anchor_left = 0.0
		mm_grain.anchor_right = 0.0
		mm_grain.anchor_top = 1.0
		mm_grain.anchor_bottom = 1.0
		mm_grain.offset_left = Balance.MINIMAP.margin_px
		mm_grain.offset_top = -(Balance.MINIMAP.size_px + Balance.MINIMAP.margin_px)
		mm_grain.offset_right = Balance.MINIMAP.margin_px + Balance.MINIMAP.size_px
		mm_grain.offset_bottom = -Balance.MINIMAP.margin_px
		mm_grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(mm_grain)

		var mm_cracks := Grunge.CrackLines.new(0.08)
		mm_cracks.anchor_left = 0.0
		mm_cracks.anchor_right = 0.0
		mm_cracks.anchor_top = 1.0
		mm_cracks.anchor_bottom = 1.0
		mm_cracks.offset_left = Balance.MINIMAP.margin_px
		mm_cracks.offset_top = -(Balance.MINIMAP.size_px + Balance.MINIMAP.margin_px)
		mm_cracks.offset_right = Balance.MINIMAP.margin_px + Balance.MINIMAP.size_px
		mm_cracks.offset_bottom = -Balance.MINIMAP.margin_px
		mm_cracks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(mm_cracks)
```

- [ ] **Step 2: Verify minimap interaction still works**

This is the one change with an input-handling risk (an overlay sitting visually on top of a clickable minimap). After `project_run`, have the user (or drive via MCP `game_eval` if available) left-click-drag on the minimap to confirm the camera still jumps, and right-click to confirm move/rally orders still fire — `mouse_filter = MOUSE_FILTER_IGNORE` on both new nodes should make them fully click-through, but this is exactly the kind of thing that's cheap to visually confirm and expensive to debug blind. Then `project_manage(op="stop")`.

---

### Task 9: Apply the display font to the brand lockup title

**Files:**
- Modify: `scenes/ui/logo_lockup.gd:35-42` (`_word()`)

**Interfaces:**
- Consumes: `UIStyle.font(UIStyle.FONT_DISPLAY)` (Task 1 + existing `UIStyle.font()` loader, which already handles not-yet-imported TTFs via `load_dynamic_font()` — no change needed there).
- Produces: no new public interface — visual-only.

- [ ] **Step 1: Swap the lockup's word font from mono to display**

old_text:
```gdscript
func _word(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UIStyle.mono_spaced())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
```

new_text:
```gdscript
func _word(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UIStyle.font(UIStyle.FONT_DISPLAY))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
```

- [ ] **Step 2: Verify visually**

`project_run` (mode `"main"`, the main menu is the default scene) → `editor_screenshot` (source `"game"`) or ask the user to glance at the main menu. Expect the "ZOMBIE COMMAND" wordmark now rendering in the Special Elite typewriter face instead of Share Tech Mono. If the new font reads too large/small at the existing `SCALES` point sizes (`scripts/ui/logo_lockup.gd:9-13`), note it as a follow-up tweak rather than guessing new sizes blind — different typefaces have different x-heights at the same pt size. Then `project_manage(op="stop")`.

---

### Task 10: Final verification pass + CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md` (append one line per CLAUDE.md house rules)

**Interfaces:**
- Consumes: nothing new.
- Produces: nothing new — this is the wrap-up task.

- [ ] **Step 1: Full clean-boot check**

`project_run` (mode `"main"`) → `logs_read(source="all", count=150)`. Expect zero `SCRIPT ERROR` / `Parse Error` across every file touched in Tasks 1–9.

- [ ] **Step 2: Owner playtest checklist**

Ask Mads to playtest and confirm, since the MCP game-capture bridge is flaky for this kind of full-screen HUD check (per CLAUDE.md gotcha):
- Shooter role: bottom HUD bar shows the new rust/blood palette, torn top edge, jagged HP fill.
- Zombie Controller role: bottom bar, mode buttons, merge buttons, and portraits show cut corners + new palette; minimap still pans/orders correctly through the new grain/crack overlay.
- Main menu: "ZOMBIE COMMAND" title renders in the new display font.

- [ ] **Step 3: Add the CHANGELOG entry**

Append a line to `CHANGELOG.md` (match the file's existing entry format/style — read the last few entries first to match tone) describing: HUD reskinned to the "v2" distressed blood/rust design system (new `UIStyle` palette, Special Elite display font, cut-corner panels via `CutCornerStyleBox`, jagged progress fills via `RoughFillStyleBox`, and grain/blood/crack/torn-edge decorations via the new `Grunge` helper).

- [ ] **Step 4: Stop, don't commit**

Per CLAUDE.md: do not run `git commit` or `git push`. Instead, suggest a short 1–2 phrase commit message to Mads, e.g. `Reskin HUD to v2 grunge design system`, and stop here.
