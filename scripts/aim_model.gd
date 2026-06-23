extends RefCounted
class_name AimModel

## Pure aiming math — the single source of truth for spread and damage falloff.
## Stateless; called by the server (firing + damage) and the client (cursor).

const TILE := 64.0


## Circle radius as a fraction of the gun->cursor distance.
## debuff_total: additive running + injured + recoil (>= 0). focus_fraction: 0..1.
static func spread_coeff(w: WeaponData, debuff_total: float, focus_fraction: float) -> float:
	var d := clampf(debuff_total, 0.0, 1.0)
	var coeff := w.aim_base + d * (w.aim_max - w.aim_base)
	coeff *= lerpf(1.0, w.focus_min_scale, clampf(focus_fraction, 0.0, 1.0))
	return coeff


## Damage multiplier: 1.0 within optimal_range_px, linear down to 0 at zero_range_px.
static func damage_mult(w: WeaponData, dist_px: float) -> float:
	if dist_px <= w.optimal_range_px:
		return 1.0
	var span := w.zero_range_px - w.optimal_range_px
	if span <= 0.0:
		return 0.0
	return clampf(1.0 - (dist_px - w.optimal_range_px) / span, 0.0, 1.0)


## Uniform random point within a disk of the given radius (px).
static func random_in_disk(radius: float) -> Vector2:
	var r := radius * sqrt(randf())
	var a := randf() * TAU
	return Vector2(cos(a), sin(a)) * r


## True when a shot fired from `origin` along `dir` passes within `radius` of
## `target` — i.e. its straight path threads the target's center crit zone.
## `dir` need not be normalised.
static func is_headshot(origin: Vector2, dir: Vector2, target: Vector2, radius: float) -> bool:
	var d := dir.normalized()
	if d == Vector2.ZERO:
		return false
	# Perpendicular distance from `target` to the ray = |(target - origin) x d|.
	return absf((target - origin).cross(d)) <= radius
