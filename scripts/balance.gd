extends Node

## ============================================================================
##  BALANCE — single source of truth for every gameplay tuning value.
##  Edit a number here, then run. Read elsewhere as e.g. Balance.ZOMBIE.speed.
##  The visual aim ring and the real bullet spread both pull the same weapon
##  numbers below, so they always stay coupled.
##  (Structural things — fog state enums, group names, HUD bar pixel sizes —
##   intentionally stay in their own files.)
## ============================================================================

# --- Player ----------------------------------------------------------------
const SHOOTER := {
	speed = 210.0,
	max_hp = 100,
	contact_dps = 12.0,            # legacy field on the shooter
	focus_time = 5.0,             # seconds of held still-aim for full focus
	aim_shrink_tau = 0.3,         # ring shrink easing time constant
	pistol_dmg_ref = 35.0,        # damage unit used to scale recoil recovery
	injured_hp_frac = 0.5,        # below this fraction of max hp -> "badly hurt"
	recoil_initial = 0.5,         # spread debuff added on each shot
	recoil_recover_factor = 2.0,  # seconds-per-damage-unit to recover recoil
	debuff_running = 0.20,        # aim spread while moving
	debuff_hurt = 0.40,           # aim spread below injured_hp_frac hp
	debuff_injured = 0.20,        # aim spread when below max hp but not badly hurt
}

# --- Zombies (variant chosen by group in zombie.gd) ------------------------
const ZOMBIE := { speed = 85.0,  max_hp = 150, contact_dps = 12.0, vision = 2, contact_px = 38.0, scale = 1.0 }
const FAST   := { speed = 220.0, max_hp = 150, contact_dps = 18.0, vision = 2, contact_px = 38.0, scale = 1.0 }
const FAT    := { speed = 76.5,  max_hp = 750, contact_dps = 60.0, vision = 2, contact_px = 38.0, scale = 1.5 }
const MASTER := { speed = 60.0,  max_hp = 450, contact_dps = 12.0, vision = 3, contact_px = 48.0, scale = 1.8 }

# --- NPC -------------------------------------------------------------------
const NPC := {
	speed = 189.0,            # 10% slower than the shooter
	max_hp = 50,
	hide_min = 10.0,
	hide_max = 20.0,
	hide_radius = 12,         # tiles searched for the next hiding spot
	convert_duration = 5.0,
	follow_distance = 64.0,   # 1 tile behind the shooter
	follow_deadzone = 12.0,
	vision_px = 384.0,        # 6 tiles
	muzzle_offset = 40.0,     # spawn bullets past the NPC's own body
	# --- Armed-NPC accuracy (Phase 3), separate from the player ---
	panic = 0.35,                  # base inaccuracy floor (always applied)
	debuff_running = 0.20,         # added while moving
	debuff_injured = 0.20,         # added when hp < max_hp
	debuff_hurt = 0.40,            # added when hp < max_hp * injured_hp_frac (replaces injured)
	injured_hp_frac = 0.5,
	recoil_initial = 0.50,         # per-shot kick
	recoil_recover_factor = 2.0,   # seconds-per-damage-unit to recover
	dmg_ref = 35.0,                # damage unit for recoil scaling (pistol = 1)
	min_shot_interval = 0.667,     # 1.5 shots/sec cap
}

# --- Bullet (per-weapon values below override damage/speed on spawn) --------
const BULLET := { speed = 600.0, damage = 35.0, lifetime = 1.8 }

# --- Weapons ---------------------------------------------------------------
# aim_base / aim_max = ring radius as a fraction of gun->cursor distance
# (no debuff / full debuff). optimal_range_px..zero_range_px = damage falloff.
const PISTOL := {
	display_name = "Pistol", damage = 35.0, cooldown = 0.28, mag_size = 15,
	reload_time = 3.0, pellets = 1, bullet_speed = 600.0, is_special = false, total_ammo = 0,
	aim_base = 0.1, aim_max = 0.30, focus_min_scale = 0.7,
	optimal_range_px = 640.0, zero_range_px = 800.0,
}
const RIFLE := {
	display_name = "Rifle", damage = 87.5, cooldown = 0.0, mag_size = 1,
	reload_time = 3.0, pellets = 1, bullet_speed = 750.0, is_special = true, total_ammo = 10,
	aim_base = 0.02, aim_max = 0.15, focus_min_scale = 0.50,
	optimal_range_px = 1024.0, zero_range_px = 1184.0,
}
const SHOTGUN := {
	display_name = "Shotgun", damage = 28.0, cooldown = 0.0, mag_size = 2,
	reload_time = 3.0, pellets = 5, bullet_speed = 600.0, is_special = true, total_ammo = 8,
	aim_base = 0.2, aim_max = 0.3, focus_min_scale = 0.9,
	optimal_range_px = 320.0, zero_range_px = 480.0,
}

# --- Headshots (Phase 2) ---------------------------------------------------
const HEADSHOT := {
	radius_px = 5.0,   # center crit zone radius, same on every zombie
	mult = 4.0,        # crit damage multiplier (x the range-adjusted damage)
}

# --- Merging ---------------------------------------------------------------
const MERGE := {
	touch_distance = 30.0,         # px apart before zombies lock in
	lock_seconds_per_zombie = 2.0, # lock duration scales with merge size
}

# --- World -----------------------------------------------------------------
const WORLD := { npc_count = 5, fog_enabled = false }

# --- Aim cursor / shared aim math ------------------------------------------
const AIM := {
	min_opacity = 0.22,   # faintest the ring ever gets (never fully vanishes)
	tile = 64.0,
}

# --- Fog: shooter flashlight cone ------------------------------------------
const FOG_SHOOTER := {
	grid_w = 47, grid_h = 47,
	cone_depth = 5,           # tiles forward
	cone_half_width = 1.5,    # tiles at the far end
	dim_radius = 1,           # tiles dimly lit around the shooter
	vis_fog = 0.0, vis_dim = 0.5, vis_full = 1.0,
}

# --- Fog: zombie-controller explored map -----------------------------------
const FOG_ZC := {
	grid_w = 47, grid_h = 47,
	vis_unexplored = 0.0, vis_explored = 0.35, vis_visible = 1.0,
}
