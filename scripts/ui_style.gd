class_name UIStyle
extends RefCounted
## ZOMBIE COMMAND visual identity tokens — single source of truth for all UI
## colors, fonts and shared style rules (the UI counterpart of balance.gd).
## Extracted from the Figma Make design system; see docs/design_system.md.
## Rules: 0px corners everywhere, mono font for data/labels, hairline borders.

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

# ── Fonts ───────────────────────────────────────────────────────────────────
const FONT_MONO := "res://resources/fonts/ShareTechMono-Regular.ttf"
const FONT_BODY := "res://resources/fonts/Rajdhani-Medium.ttf"
const FONT_BODY_BOLD := "res://resources/fonts/Rajdhani-Bold.ttf"


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
