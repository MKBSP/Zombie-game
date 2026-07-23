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
## Online smoothing: clients ease entities toward the server's synced pose
## (sync_pos/sync_rot) instead of snapping, so internet jitter doesn't show.
const NET := {
	smooth_rate = 14.0,      # 1/s ease for entities you watch (zombies, NPCs, others)
	snap_dist_px = 160.0,    # beyond this, teleport (merge completion, respawn)
	# Your own shooter moves client-authoritatively (zero perceived lag). The
	# server speed-clamps the reported position; if its adopted position ends up
	# further than this from yours, the server wins and you snap back.
	reclaim_dist_px = 240.0,
}

const SHOOTER := {
	speed = 105.0,
	scale = 0.5,
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
	# Multiplayer spawn placement: keep shooters away from the zombie spawn and
	# from each other (pixels; 64px = 1 tile).
	min_dist_from_zombie_px = 768.0,
	min_dist_from_shooter_px = 256.0,
}

# --- Zombies (variant chosen by group in zombie.gd) ------------------------
const ZOMBIE := { speed = 42.5,  max_hp = 150, contact_dps = 12.0, vision = 2, contact_px = 38.0, scale = 0.5,  damage_per_hit = 15, attack_interval = 1.0 }
const FAST   := { speed = 110.0, max_hp = 150, contact_dps = 18.0, vision = 2, contact_px = 38.0, scale = 0.5,  damage_per_hit = 12, attack_interval = 0.7 }
const FAT    := { speed = 38.25, max_hp = 750, contact_dps = 60.0, vision = 2, contact_px = 38.0, scale = 0.75, damage_per_hit = 45, attack_interval = 1.3 }
const MASTER := { speed = 30.0,  max_hp = 450, contact_dps = 12.0, vision = 3, contact_px = 48.0, scale = 0.9,  damage_per_hit = 20, attack_interval = 1.2 }

# --- Unit separation (RVO avoidance) ---------------------------------------
const SEPARATION := {
	agent_radius = 16.0,       # px, ~body radius; agents keep this much apart
	neighbor_distance = 80.0,  # px, how far an agent looks for neighbors
	max_neighbors = 10,
	time_horizon = 1.0,        # s, how far ahead RVO predicts collisions
}

# --- Stances ----------------------------------------------------------------
const STANCE := {
	arrive_px = 8.0,             # how close counts as "reached the point"
	hold_attack_px = 64.0,       # Hold: bite enemies within ~1 tile, no chase
	leash_px = 120.0,            # Aggressive: engage radius around a parked flee point
	damage_flee_window = 0.4,    # seconds the "recently damaged" flag stays up
}

# --- Minimap ----------------------------------------------------------------
const MINIMAP := {
	size_px = 200.0,            # on-screen square size
	world_px = 3008.0,          # world extent the minimap covers
	margin_px = 12.0,           # inset from the screen corner
	zombie_blip = 2.5,
	enemy_blip = 3.0,
	ghost_fade = 4.0,           # s, last-known blip fade
	under_attack_seconds = 1.5, # s, red pulse duration
	gunshot_jitter_px = 90.0,   # "general area" fuzz for the shot ripple
	ripple_seconds = 1.2,
}

# --- Sound aggro + world feedback ------------------------------------------
const AGGRO := {
	world_ripple_px = 700.0,   # show a world ripple only if camera within this of the shot
	ripple_seconds = 0.7,
	ripple_radius = 120.0,
	alert_radius_px = 600.0,   # Aggressive zombies within this get pulled toward the shot
	alert_seconds = 3.0,
}

# --- NPC -------------------------------------------------------------------
const NPC := {
	speed = 80.0,             # 10% slower than the shooter, both halved
	scale = 0.5,
	max_hp = 50,
	hide_min = 10.0,
	hide_max = 20.0,
	hide_radius = 12,         # tiles searched for the next hiding spot
	convert_duration = 5.0,
	follow_distance = 64.0,   # 1 tile behind the shooter
	follow_deadzone = 20.0,   # must exceed RVO agent_radius wobble (16px)
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
	# --- Follow: breadcrumb trail + combat formation ---
	breadcrumb_px = 24.0,        # min distance between recorded trail points
	trail_max = 64,              # trail ring-buffer cap (~1500 px of path)
	slot_spacing_px = 64.0,      # trail arc-length per follower slot (1 tile)
	threat_radius_px = 384.0,    # zombie within this of the shooter -> formation
	threat_exit_px = 500.0,      # formation mode ends only past this (hysteresis)
	threat_hold_s = 1.0,         # min seconds before switching to another threat
	form_dir_tau = 0.25,         # s, easing of the shooter->threat formation axis
	arrive_slow_px = 64.0,       # ease-off radius approaching the follow point
	retarget_px = 12.0,          # re-path only when the goal moved this far
	formation_back_px = 56.0,    # armed slot depth behind the shooter
	formation_side_px = 48.0,    # armed slot lateral offset
}

# --- Bullet (per-weapon values below override damage/speed on spawn) --------
const BULLET := { speed = 1200.0, damage = 35.0, lifetime = 1.8 }

# --- Weapons ---------------------------------------------------------------
# aim_base / aim_max = ring radius as a fraction of gun->cursor distance
# (no debuff / full debuff). optimal_range_px..zero_range_px = damage falloff.
const PISTOL := {
	display_name = "Pistol", damage = 35.0, cooldown = 0.28, mag_size = 15,
	reload_time = 3.0, pellets = 1, bullet_speed = 1200.0, is_special = false, total_ammo = 0,
	aim_base = 0.1, aim_max = 0.30, focus_min_scale = 0.7,
	optimal_range_px = 640.0, zero_range_px = 800.0,
}
const RIFLE := {
	display_name = "Rifle", damage = 87.5, cooldown = 0.0, mag_size = 1,
	reload_time = 3.0, pellets = 1, bullet_speed = 1500.0, is_special = true, total_ammo = 10,
	aim_base = 0.02, aim_max = 0.15, focus_min_scale = 0.50,
	optimal_range_px = 1024.0, zero_range_px = 1184.0,
}
const SHOTGUN := {
	display_name = "Shotgun", damage = 28.0, cooldown = 0.0, mag_size = 2,
	reload_time = 3.0, pellets = 5, bullet_speed = 1200.0, is_special = true, total_ammo = 8,
	aim_base = 0.2, aim_max = 0.3, focus_min_scale = 0.9,
	optimal_range_px = 320.0, zero_range_px = 480.0,
}
const MACHINEGUN := {
	display_name = "Machine Gun", damage = 22.0, cooldown = 0.08, mag_size = 40,
	reload_time = 4.0, pellets = 1, bullet_speed = 1300.0, is_special = true, total_ammo = 120,
	aim_base = 0.14, aim_max = 0.40, focus_min_scale = 0.8,
	optimal_range_px = 512.0, zero_range_px = 700.0,
}

# --- Melee (Phase 4) -------------------------------------------------------
const MELEE := {
	display_name = "Melee",
	damage = 10.0,
	cooldown = 0.6,            # seconds between swings
	range_px = 50.0,           # reach just past the body
	half_width_px = 19.0,      # ~80% of the 48px player hitbox
	fatigue_hits = 3,          # landed hits inside fatigue_window that trigger fatigue
	fatigue_window = 3.0,
	fatigue_mult = 0.5,        # damage multiplier while fatigued
	fatigue_recover = 10.0,    # seconds with no landed hit to clear fatigue
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
# Enemy / NPC counts scale with the number of shooter players (computed in
# world.gd from the spawned shooter count):
#   normal zombies = base_zombie_count + zombies_per_extra_shooter * (shooters - 1)
#   NPCs           = npc_per_player * (shooters + 1)   # +1 counts the zombie player
const WORLD := {
	base_zombie_count = 15,
	zombies_per_extra_shooter = 5,
	npc_per_player = 5,
	fog_enabled = true,
}

# --- Loot boxes ------------------------------------------------------------
# box_count crates scatter on walkable tiles. Each box rolls an item count
# (chance_three -> 3, else chance_two -> 2, else 1), then each item rolls a
# kind by relative weight. Heal amounts and interaction radii live here too.
const LOOT := {
	box_count = 8,
	chance_two = 0.20,
	chance_three = 0.01,
	# Relative spawn weights per item kind (tune freely; need not sum to 100).
	weight_ammo_mag = 20,
	weight_bandage = 25,
	weight_medipack = 15,
	weight_melee = 15,
	weight_shotgun = 12,
	weight_machinegun = 12,
	weight_rifle = 12,
	# Heal amounts.
	heal_bandage = 10,
	heal_medipack = 50,
	# Burst: items land within burst_radius_px of the box, kept burst_min_sep_px
	# apart, animating over burst_tween_time seconds.
	burst_radius_px = 64.0,
	burst_min_sep_px = 28.0,
	burst_tween_time = 0.3,
	# Contextual-interact reach per target type (px).
	interact_pickup_px = 56.0,
	interact_box_px = 64.0,
	# Must cover NPC.follow_distance (64) + deadzone (12) — followers hover a
	# tile behind, and solid bodies stop you overlapping them (22px was
	# physically unreachable after that landed).
	interact_give_px = 90.0,
	interact_take_px = 56.0,   # take-back is non-destructive -> normal reach
}

# --- Aim cursor / shared aim math ------------------------------------------
const AIM := {
	min_opacity = 0.22,   # faintest the ring ever gets (never fully vanishes)
	tile = 64.0,
}

# --- Fog: shooter flashlight lighting (2D lights) --------------------------
# ambient_darkness is the CanvasModulate tint over the whole world — the
# "opacity dial": lower = near-black, higher = faint grey where the street
# layout stays readable. Everything else tunes the two lights / occluders.
const FOG_SHOOTER := {
	ambient_darkness = Color(0.16, 0.16, 0.19, 1.0),
	flashlight_range = 540.0,          # px, cone reach from the shooter
	flashlight_energy = 1.5,
	flashlight_half_angle_deg = 22.0,  # half the cone's opening angle
	flashlight_color = Color(1.0, 0.97, 0.85, 1.0),
	halo_radius = 140.0,               # px, ~2 tiles around the shooter
	halo_energy = 0.9,
	halo_color = Color(0.82, 0.86, 1.0, 1.0),
	shadows_enabled = true,
	dynamic_occluder_radius = 14.0,    # px, body-sized occluder for entities; NOTE: also hand-set in entity .tscn Occluder polygons (±this); keep in sync
	cone_tex_size = 512,               # generated cone texture resolution
	halo_tex_size = 256,               # generated halo texture resolution
}

# --- Prop fog occluders (see scenes/props/prop_occluder.gd) ----------------
const PROP_OCCLUDER := {
	inset_frac = 0.25,        # shrink the occluder vs the visual so props stay lit
	fence_segment_px = 6.0,   # solid picket width
	fence_gap_px = 7.0,       # gap letting light bleed through
	fence_thickness_px = 6.0, # occluder depth across the fence line
}

# --- Fog: zombie-controller explored map + shooter-style lighting ----------
const FOG_ZC := {
	grid_w = 47, grid_h = 47,
	# Shader mask: only unexplored tiles stay opaque black; explored/visible
	# are transparent — dimming comes from ambient_darkness + vision lights.
	vis_unexplored = 0.0, vis_explored = 1.0, vis_visible = 1.0,
	ambient_darkness = Color(0.16, 0.16, 0.19, 1.0),
	light_energy = 1.2,       # per-zombie vision light
	light_tex_size = 256,     # generated radial texture resolution
	shadows_enabled = true,   # LOS shadows on vision lights
}

# --- Combat juice / effects (all cosmetic; no gameplay impact) --------------
const FX := {
	# One-shot hit bursts (CPUParticles2D). Colors are Color(r,g,b).
	presets = {
		"red_blood":   { color = Color(0.65, 0.02, 0.02), amount = 14, lifetime = 0.42, spread_deg = 55.0, vel_min = 60.0, vel_max = 180.0, scale_min = 2.0, scale_max = 4.0, gravity = 220.0 },
		"green_blood": { color = Color(0.20, 0.75, 0.10), amount = 14, lifetime = 0.42, spread_deg = 55.0, vel_min = 60.0, vel_max = 180.0, scale_min = 2.0, scale_max = 4.0, gravity = 220.0 },
		"sparks":      { color = Color(1.0, 0.85, 0.35),  amount = 10, lifetime = 0.20, spread_deg = 40.0, vel_min = 140.0, vel_max = 320.0, scale_min = 1.0, scale_max = 2.0, gravity = 40.0 },
	},
	# Muzzle flash: brief additive sprite + PointLight2D pulse at the gun tip.
	muzzle_flash_time = 0.06,        # seconds the flash + light stay up
	muzzle_light_energy = 1.6,       # player light pulse energy
	muzzle_light_range_px = 130.0,   # player light radius
	muzzle_npc_light_energy = 0.8,   # NPCs get a smaller pulse
	muzzle_flash_scale = 0.6,
	# Player bleed trail (baked, permanent).
	bleed_seconds = 6.0,             # bleeding window, refreshed on each hit
	bleed_drip_px = 26.0,            # emit one drop per this much travel
	bleed_drop_radius_px = 3.0,      # stamp radius on the canvas, world px
	bleed_color = Color(0.45, 0.02, 0.02, 0.85),
	canvas_downscale = 1,            # 1 = world-res canvas (crisp); raise to save memory
}
