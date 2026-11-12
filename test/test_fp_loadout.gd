extends SceneTree

## Headless check for the first-person loadout rules (scripts/3d/fp_loadout.gd):
## the 8 loadouts, torch vs two-handed, and the 2D ammo/reload/falloff rules. Run:
##   "/Applications/Godot 2.app/Contents/MacOS/Godot" --headless --path . --script test/test_fp_loadout.gd

var _failures := 0
var L = load("res://scripts/3d/fp_loadout.gd")
var W = load("res://scripts/weapons.gd")


func _init() -> void:
	# --- loadouts: torch only where a hand is free ---
	_check("8 loadouts", L.COUNT == 8 and L.NAMES.size() == 8 and L.WEAPON.size() == 8)
	for n in L.COUNT:
		_check("loadout %d: never torch + two-handed" % n, not (L.has_torch(n) and L.two_handed(n)))
	_check("torch alone has torch", L.has_torch(L.TORCH))
	_check("pistol+torch has torch in left", L.TORCH_HAND[L.PISTOL_TORCH] == "L")
	_check("pistol alone has no torch", not L.has_torch(L.PISTOL))
	for n in [L.SHOTGUN, L.RIFLE, L.UZI, L.BAT]:
		_check("%s is two-handed" % L.NAMES[n], L.two_handed(n))
	_check("uzi is the 2D machine gun", L.WEAPON[L.UZI] == W.MACHINEGUN)
	_check("bat is melee", L.data(L.BAT).is_melee)
	_check("cycle wraps down", L.cycle(0, -1) == 7)
	_check("cycle wraps up", L.cycle(7, 1) == 0)

	# --- ammo: 2D starting loads ---
	var p: Dictionary = L.new_ammo(W.PISTOL)
	_check("pistol starts 15 + 15 spare", p.mag == 15 and p.reserve == 15)
	var s: Dictionary = L.new_ammo(W.SHOTGUN)
	_check("shotgun starts 2 loaded of 8", s.mag == 2 and s.reserve == 6)
	var r: Dictionary = L.new_ammo(W.RIFLE)
	_check("rifle starts 1 loaded of 10", r.mag == 1 and r.reserve == 9)

	# --- reload tops up from reserve, never past the mag ---
	var pd = W.get_data(W.PISTOL)
	var a := {mag = 3, reserve = 20}
	_check("can reload a part mag", L.can_reload(a, pd))
	L.finish_reload(a, pd)
	_check("reload fills to 15 (got %d/%d)" % [a.mag, a.reserve], a.mag == 15 and a.reserve == 8)
	var b := {mag = 0, reserve = 4}
	L.finish_reload(b, pd)
	_check("short reserve loads what is left", b.mag == 4 and b.reserve == 0)
	_check("no reload when reserve empty", not L.can_reload(b, pd))
	_check("no reload when mag full", not L.can_reload({mag = 15, reserve = 9}, pd))

	# --- falloff in metres: pistol full to 640px = 18.3 m, zero at 800px = 22.9 m ---
	_check("pistol full damage at 15 m", is_equal_approx(L.falloff(pd, 15.0), 1.0))
	_check("pistol zero damage at 23 m", L.falloff(pd, 23.0) == 0.0)
	var mid: float = L.falloff(pd, 20.57)  # 720 px, halfway down the ramp
	_check("pistol half damage mid-ramp (got %.2f)" % mid, absf(mid - 0.5) < 0.02)

	# --- spread: rifle tighter, shotgun wider than the pistol ---
	_check("pistol spread x1", is_equal_approx(L.spread_mult(pd), 1.0))
	_check("rifle tighter", L.spread_mult(W.get_data(W.RIFLE)) < 0.5)
	_check("shotgun wider", L.spread_mult(W.get_data(W.SHOTGUN)) > 1.5)

	print("FAILURES: %d" % _failures if _failures else "ALL PASS")
	quit(1 if _failures else 0)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + label)
