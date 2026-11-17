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

# --- First person (Phase 10, 3D test player) --------------------------------
# Weapon stats above are reused as-is; these are the extra 3D-only numbers.
# Read by scripts/3d/fp_loadout.gd + scripts/3d/viewmodel.gd.
const FP := {
	px_per_m = 35.0,          # 2D pixels per 3D metre (3d-conversion-design §5)
	max_range_m = 150.0,      # hitscan ray length
	pitch_deg = 85.0,         # how far the view looks up and down
	pistol_reserve = 15,      # spare pistol rounds at start (2D shooter: one spare mag)
	camera_kick_deg = {       # view punch per shot (peak, springs back), degrees
		pistol = 1.6, shotgun = 5.0, rifle = 4.0, uzi = 0.8, bat = 0.0,
	},
	climb_deg = {             # part of each kick that stays — the aim you must pull down
		pistol = 0.3, shotgun = 1.0, rifle = 0.8, uzi = 0.22, bat = 0.0,
	},
	scope_fov = 20.0,         # rifle aim FOV; everything else keeps the rig's aim_fov
	cheat_key = KEY_F9,       # debug builds only: every weapon, T refills (no carry limit)
	hitmarker = {             # crosshair tick when a shot lands on a zombie
		show_s = 0.18, hit = Color.WHITE, limb = Color(1.0, 0.6, 0.2), kill = Color(1.0, 0.15, 0.1), kill_scale = 1.5,
	},
}

# --- 3D zombies (scripts/3d/zombie_3d.gd) — 3D-only numbers -----------------
# HP, damage and attack timing still come from ZOMBIE/FAST/FAT/MASTER above;
# these replace the px-converted speed / sight / hearing, which read too slow
# and too short in first person (2026-11-13 playtest).
# --- 3D loot (scripts/3d/loot_crate.gd + pickup_3d.gd) ---------------------
# Crate contents use LOOT's item counts and weights; this is only the 3D placing.
const LOOT_3D := {
	crate_count = 14,          # spread evenly over the map (loot_scatter.gd)
	min_sep_m = 30.0,          # no two crates closer
	spawn_clear_m = 25.0,      # none this close to the shooter's start
	burst_m = 1.5,             # items land this far around an opened crate
	wall_reach_m = 8.0,        # a crate spot slides to a wall this close (else the spot is skipped)
	seed = 1,                  # map layout; S10 passes the match seed instead
}

# --- 3D impacts (scripts/3d/impact_fx.gd) -----------------------------------
# One look per surface a shot can hit. decal = leaves a bullet hole; count/life/
# speed (min, max m/s)/gravity (m/s2)/size (min, max m) shape the burst; unshaded
# glows (sparks), shaded only shows where light falls (dust).
const IMPACT := {
	decal_cap = 60,             # bullet holes kept, shooter and survivors together
	ground = {decal = true, count = 12, life = 0.6, color = Color(0.62, 0.57, 0.5), unshaded = false,
			speed = Vector2(0.8, 2.2), gravity = 4.0, size = Vector2(0.04, 0.09)},
	wall = {decal = true, count = 10, life = 0.6, color = Color(0.72, 0.68, 0.6), unshaded = false,
			speed = Vector2(0.8, 2.2), gravity = 4.0, size = Vector2(0.04, 0.09)},
	metal = {decal = true, count = 14, life = 0.45, color = Color(1.0, 0.5, 0.12), unshaded = true,
			speed = Vector2(1.0, 3.0), gravity = 5.0, size = Vector2(0.03, 0.07)},
	glass = {decal = false, count = 24, life = 0.9, color = Color(0.8, 0.9, 1.0), unshaded = true,
			speed = Vector2(0.5, 2.0), gravity = 9.8, size = Vector2(0.02, 0.05)},
	wood = {decal = true, count = 10, life = 0.6, color = Color(0.45, 0.3, 0.17), unshaded = false,
			speed = Vector2(1.0, 2.5), gravity = 7.0, size = Vector2(0.03, 0.07)},
	# flesh = a hit on a zombie part or a survivor; gore = a part blown off. splat =
	# blood lands on whatever is up to splat_m behind the hit (no hole in the body).
	flesh = {decal = false, splat = true, count = 16, life = 0.5, color = Color(0.55, 0.03, 0.03), unshaded = false,
			speed = Vector2(1.0, 3.0), gravity = 9.8, size = Vector2(0.03, 0.08)},
	gore = {decal = false, splat = true, count = 40, life = 0.8, color = Color(0.5, 0.03, 0.03), unshaded = false,
			speed = Vector2(1.5, 4.0), gravity = 9.8, size = Vector2(0.04, 0.12)},
	splat_m = 2.5,
	splat_size_m = 0.6,
}

const ZOMBIE_3D := {
	speed_mps = { standard = 2.0, fat = 1.6, master = 1.3 },
	fast_vs_sprint = 1.01,      # fast zombie = the shooter's sprint speed + 1%
	vision_m = { standard = 20.0, fast = 20.0, fat = 16.0, master = 30.0 },  # also the fog reveal
	hearing_m = 70.0,           # a gunshot pulls Aggressive zombies this far
	# Reaction, "like in real life": a beat to register a new target, then a fresh
	# read of where it is only this often (+-30%), and momentum (m/s^2) so a juke
	# or a corner makes them overshoot instead of staying glued on.
	notice_s = 0.6,
	reaction_s = 0.45,
	search_s = 5.0,             # lost sight: keeps heading to the last-seen spot this long
	accel_mps2 = { standard = 5.0, fast = 8.0, fat = 3.0, master = 3.0 },
}

# --- 3D NPC survivors (scripts/3d/npc_3d.gd) — 3D-only numbers --------------
# Everything else (hide times, conversion, follow / formation, NPC aim) is the
# 2D Balance.NPC block, pixels converted at FP.px_per_m.
const NPC_3D := {
	count = 10,                 # 2D: npc_per_player x (shooters + 1)
	speed_mps = 2.7,            # 10% under the shooter's 3 m/s walk, as in 2D
	catchup_m = 4.0,            # a follower further behind than this runs (90% of sprint)
	vision_m = 20.0,            # armed followers shoot zombies they can see this far
	# 2D NPC spread (coeff x distance) missed sideways only; in 3D the same radius
	# misses in two directions and almost never hit. This brings the hit rate back
	# to roughly the 2D "sloppy but useful".
	aim_scale = 0.25,
	recruit_m = 1.3,            # walk into a survivor to make it follow you
	give_m = 3.0,               # interact reach for handing over / taking back a gun
	spawn_min_m = 30.0,         # survivors start at least this far from shooter and horde
	cover_ray_m = 4.0,          # cover_score: 8 rays this long count building walls around a spot
	min_cover = 3,              # hiding spots need at least this (against a wall = 3, alley = 6)
	spot_samples = 16,          # candidate spots tried per hiding-spot search
	wall_reach_m = 8.0,         # a candidate slides to the nearest wall this close
	# spotted by a zombie (hidden or relocating): one roll per sighting
	freeze_chance = 0.2,        # cower where they are; else run for cover
	flee_mps = 4.5,             # beats standard zombies (2.0), not fast ones (6.06)
	flee_min_m = 18.0,          # the cover they run to is at least this far from the zombie
	calm_s = 6.0,               # unseen this long: back to hiding
	spot_check_s = 0.2,         # how often they look for zombies watching them
	corpse_s = 12.0,
}

# --- 3D zombie part HP (spec 3d-conversion-design §6) -----------------------
# Six pools per zombie: head, body, arm x2, leg x2. The body pool is the
# variant's max_hp above. Head or body at 0 kills; limbs never do and never
# bleed into the body. Limb multipliers are first guesses, expected to move.
const ZOMBIE_PARTS := {
	standard = { head = 35, arm = 40, leg = 50 },
	fast = { head = 30, arm = 35, leg = 35 },
	fat = { head = 105, arm = 90, leg = 120 },
	master = { head = 140, arm = 70, leg = 90 },
	hobble_speed = 0.5,         # one leg gone
	crawl_speed = 0.2,          # both legs gone: crawls, hitbox at ground height
	one_arm_interval = 1.6,     # attack_interval x this with one arm gone
	no_arm_interval = 2.4,      # ...and with both (still attacks)
	corpse_s = 12.0,            # how long a body lies there
	flinch_s = 0.25,            # a hit that doesn't take a part off jerks the zombie this long
}

# --- 3D street lights (scripts/3d/street_light.gd + street_lights.gd) -------
# A lamp's state comes from its position + seed, so every peer sees the same
# lamps without syncing. Odds blend from `calm` to `wrecked` by a damage noise
# over the map, so whole stretches are lit and others dark and smashed.
const STREET_LIGHTS := {
	seed = 1337,
	spacing_m = 28.0,         # along each kerb; the far kerb is staggered by half
	kerb_offset_m = 0.6,      # pole centre behind the kerb line
	min_gap_m = 14.0,         # no two lamps closer (bends, junctions, overlaps)
	decay_zone_m = 110.0,     # size of the calm / wrecked patches
	calm = { working = 70.0, blinking = 12.0, dead = 12.0, sparking = 3.0, fallen = 3.0 },
	wrecked = { working = 6.0, blinking = 14.0, dead = 30.0, sparking = 16.0, fallen = 34.0 },
	fallen_sparks = 0.35,     # chance a fallen lamp still has live wires
	smashed_glass = 0.5,      # chance a dead / fallen lamp's lens is gone
	shatter_spark_chance = 0.3,  # a lamp shot out keeps sparking (else just goes dark)
	energy = 12.0,
	range_m = 20.0,
	angle_deg = 62.0,
	color = Color(1.0, 0.68, 0.38),  # sodium
	shadow_fade_m = 35.0,     # lamps further than this drop their shadows
	fade_m = 90.0,            # and further than this switch off
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

# --- Ambient life: lightposts, burning dumpster, critters, grass -----------
const AMBIENT_LIFE := {
	lightpost_count = 3,
	# Temporarily off — code/assets stay in place, just not spawned/active.
	lightposts_enabled = false,
	dumpster_fire_enabled = false,
	static_light = {
		radius_tiles = 4.0,          # ~ a Fat/Master zombie's vision range
		light_tex_size = 256,
		steady_energy = 1.1,         # lightpost
		steady_color = Color(1.0, 0.92, 0.75, 1.0),
		flicker_energy = 1.0,        # dumpster base, jittered around this each frame
		flicker_jitter = 0.25,
		flicker_color = Color(1.0, 0.55, 0.2, 1.0),
	},
	dumpster_noise_mask = {
		radius_px = 220.0,           # gunshots inside this radius of a dumpster are muffled
		alert_radius_mult = 0.8,     # 20% less far
	},
	flashlight_glow = {
		dim_energy = 0.35,           # ambient "there's light over there" glow, zombie side
		full_energy = 1.4,           # promoted brightness when a zombie is caught in the beam
		cone_tex_size = 512,
	},
	critters = {
		rat_count = 20,
		bug_count = 20,
		firefly_count = 30,
		rat_speed = 90.0,
		bug_speed = 55.0,
		firefly_speed = 24.0,
		flee_trigger_px = 160.0,         # distance from flashlight/noise that triggers fleeing
		nudge_trigger_px = 28.0,         # fireflies only: distance to nudge away from a character
		bug_dumpster_radius_px = 160.0,  # spawn radius around a scattered dumpster
		wander_change_seconds = 2.5,     # how often idle wander picks a new direction
	},
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
