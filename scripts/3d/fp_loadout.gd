extends RefCounted
## First-person loadouts for the 3D test player, plus the 2D ammo/reload rules
## ported unchanged (stats come from Balance via Weapons.get_data). Pure data and
## static helpers; visuals, input and raycasts live in scripts/3d/viewmodel.gd.
## Checked headless by test/test_fp_loadout.gd.

const W := preload("res://scripts/weapons.gd")
const Aim := preload("res://scripts/aim_model.gd")

enum { EMPTY, TORCH, PISTOL, PISTOL_TORCH, SHOTGUN, RIFLE, UZI, BAT }
const COUNT := 8
const NAMES := ["Hands", "Torch", "Pistol", "Pistol + torch", "Shotgun", "Rifle", "Uzi", "Bat"]
## Weapons.* id per loadout (-1 = nothing). The 2D machine gun is the uzi.
const WEAPON := [-1, -1, W.PISTOL, W.PISTOL, W.SHOTGUN, W.RIFLE, W.MACHINEGUN, W.MELEE]
## Which hand holds the torch ("" = no torch). Two-handed loadouts have none.
const TORCH_HAND := ["", "R", "", "L", "", "", "", ""]
## Balance.FP.camera_kick_deg key per weapon id.
const KEY := {W.PISTOL: "pistol", W.SHOTGUN: "shotgun", W.RIFLE: "rifle", W.MACHINEGUN: "uzi", W.MELEE: "bat"}
## What the shooter spawns holding. Pistol and torch are always carried; on top
## of them, one heavy (shotgun / rifle / uzi) and one melee (bat), as in 2D.
const START := PISTOL_TORCH


## Loadouts the shooter can select: hands, torch and pistol always, plus the
## heavy and the bat if carried. `all` = the debug cheat.
static func available(heavy: int, melee: int, all: bool) -> Array:
	if all:
		return range(COUNT)
	var out := [EMPTY, TORCH, PISTOL, PISTOL_TORCH]
	for n in [SHOTGUN, RIFLE, UZI]:
		if WEAPON[n] == heavy:
			out.append(n)
	if melee != -1:
		out.append(BAT)
	return out


## Picking up weapon `id`: the new slots, the weapon dropped to make room (-1 =
## none), and whether it was one already carried (refill its ammo instead).
static func take(heavy: int, melee: int, id: int) -> Dictionary:
	var out := {heavy = heavy, melee = melee, dropped = -1, refill = false}
	var slot := "melee" if id == W.MELEE else "heavy"
	if out[slot] == id:
		out.refill = true
	else:
		out.dropped = out[slot]
		out[slot] = id
	return out


## Stay on `loadout` if still selectable, else back to START.
static func fallback(loadout: int, avail: Array) -> int:
	return loadout if loadout in avail else START


static func two_handed(loadout: int) -> bool:
	return loadout >= SHOTGUN


static func has_torch(loadout: int) -> bool:
	return TORCH_HAND[loadout] != ""


static func data(loadout: int) -> Resource:
	return null if WEAPON[loadout] < 0 else W.get_data(WEAPON[loadout])


static func cycle(loadout: int, step: int) -> int:
	return posmod(loadout + step, COUNT)


## Starting ammo, as in 2D: the pistol has a full mag + Balance.FP.pistol_reserve
## spare; specials come with total_ammo, a mag of it loaded.
static func new_ammo(id: int) -> Dictionary:
	var d := W.get_data(id)
	if d.is_melee:
		return {mag = 0, reserve = 0}
	if id == W.PISTOL:
		return {mag = d.mag_size, reserve = Balance.FP.pistol_reserve}
	var mag := mini(d.mag_size, d.total_ammo)
	return {mag = mag, reserve = d.total_ammo - mag}


static func can_reload(a: Dictionary, d: Resource) -> bool:
	return a.mag < d.mag_size and a.reserve > 0


static func finish_reload(a: Dictionary, d: Resource) -> void:
	var n: int = mini(d.mag_size - a.mag, a.reserve)
	a.mag += n
	a.reserve -= n


## 2D damage falloff, ranges converted at Balance.FP.px_per_m.
static func falloff(d: Resource, dist_m: float) -> float:
	return Aim.damage_mult(d, dist_m * Balance.FP.px_per_m)


## Reticle-volume multiplier: the 2D aim_base relative to the pistol's, so the
## rifle aims ~5x tighter and the shotgun spreads twice as wide.
static func spread_mult(d: Resource) -> float:
	return d.aim_base / W.get_data(W.PISTOL).aim_base
