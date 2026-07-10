extends RefCounted
class_name NetSmooth

## Client-side smoothing of server-synced transforms.
##
## The MultiplayerSynchronizers replicate sync_pos/sync_rot (plain script vars)
## instead of raw position/rotation; each frame the client eases the visible
## node toward that pose. This hides internet jitter — raw writes snap entities
## to whatever cadence packets arrive at (bursty over TCP/TLS), which showed as
## "everything jumping around" in online matches. Tunables in Balance.NET.
## Pure static helper (headless-testable; see test/ conventions in CLAUDE.md).


## Ease node.position toward sync_pos. Distances past snap_dist_px teleport
## instantly (merge completion, spawns) instead of visibly sliding across the map.
## rate: Balance.NET.smooth_rate for watched entities; pass
## Balance.NET.own_smooth_rate for the player's own shooter (stiffer = crisper
## stops, and jitter matters less on the entity you control than lag does).
static func follow(node: Node2D, sync_pos: Vector2, delta: float, rate: float = Balance.NET.smooth_rate) -> void:
	if node.position.distance_to(sync_pos) > Balance.NET.snap_dist_px:
		node.position = sync_pos
		return
	node.position = node.position.lerp(sync_pos, alpha(delta, rate))


## Ease node.rotation toward sync_rot along the shortest arc.
static func follow_rot(node: Node2D, sync_rot: float, delta: float, rate: float = Balance.NET.smooth_rate) -> void:
	node.rotation = lerp_angle(node.rotation, sync_rot, alpha(delta, rate))


## Frame-rate-independent exponential blend factor.
static func alpha(delta: float, rate: float = Balance.NET.smooth_rate) -> float:
	return 1.0 - exp(-rate * delta)
