class_name UIStyle
extends RefCounted
## ZOMBIE COMMAND visual identity tokens — single source of truth for all UI
## colors, fonts and shared style rules (the UI counterpart of balance.gd).
## Extracted from the Figma Make design system; see docs/design_system.md.
## Rules: 0px corners everywhere, mono font for data/labels, hairline borders.

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

# ── Fonts ───────────────────────────────────────────────────────────────────
const FONT_MONO := "res://resources/fonts/ShareTechMono-Regular.ttf"
const FONT_BODY := "res://resources/fonts/Rajdhani-Medium.ttf"
const FONT_BODY_BOLD := "res://resources/fonts/Rajdhani-Bold.ttf"
const FONT_DISPLAY := "res://resources/fonts/SpecialElite-Regular.ttf"


static var _fonts: Dictionary = {}
static var _mono_spaced: FontVariation


## Load a TTF (cached), whether or not the editor has imported it yet.
static func font(path: String) -> FontFile:
	if _fonts.has(path):
		return _fonts[path]
	var f: FontFile = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is FontFile:
			f = res
	if f == null:
		f = FontFile.new()
		f.load_dynamic_font(path)
	if path == FONT_MONO:
		# OS fallback so glyphs Share Tech Mono lacks (e.g. the ☣ biohazard
		# mark) still render instead of showing tofu boxes.
		var sys := SystemFont.new()
		sys.font_names = PackedStringArray(
			["Apple Symbols", "Segoe UI Symbol", "Noto Sans Symbols 2", "sans-serif"])
		f.fallbacks = [sys]
	_fonts[path] = f
	return f


## Share Tech Mono with wide tracking — headings, HUD labels, buttons.
static func mono_spaced() -> FontVariation:
	if _mono_spaced == null:
		_mono_spaced = FontVariation.new()
		_mono_spaced.base_font = font(FONT_MONO)
		_mono_spaced.spacing_glyph = 3
	return _mono_spaced


## HP bar color rule: >60% green, 30–60% warn yellow, <30% crit red.
static func hp_color(pct: float) -> Color:
	if pct > 0.6:
		return INFECTION
	if pct > 0.3:
		return WARN_YELLOW
	return HEMORRHAGE


## A color with its alpha replaced (for the `color·8%` active-fill idiom).
static func fade(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


## Sharp-cornered stylebox: `bg` fill, 1px `border`, optional glow shadow.
static func box(bg: Color, border: Color, glow := Color.TRANSPARENT, glow_size := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(1)
	sb.border_color = border
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
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
		sb.glow_color = glow
		sb.glow_size = glow_size
	return sb


## Jagged-leading-edge fill for HP/ammo progress bars (mockup's RoughBar).
static func rough_fill(color: Color) -> RoughFillStyleBox:
	var sb := RoughFillStyleBox.new()
	sb.bg_color = color
	return sb
