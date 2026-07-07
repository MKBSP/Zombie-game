extends RefCounted
class_name LobbyModel

## Pure lobby role logic — no GameState / networking, so it is headless-testable.
## State is a dict: { "zombie": int, "shooters": Array }  (0 = free slot).
## role ints match GameState.Role: 0 = HUMAN (shooter), 1 = ZOMBIE.

const ROLE_HUMAN := 0
const ROLE_ZOMBIE := 1

static func _copy(state: Dictionary) -> Dictionary:
	return { "zombie": state.get("zombie", 0), "shooters": (state.get("shooters", []) as Array).duplicate() }

## Free whatever slot `peer` currently holds.
static func remove(state: Dictionary, peer: int) -> Dictionary:
	var s := _copy(state)
	if s["zombie"] == peer:
		s["zombie"] = 0
	s["shooters"].erase(peer)
	return s

## Grant the requested role if available, releasing whatever slot `peer` already
## held. A refused claim (role taken / shooters full) is a no-op: the player
## keeps its current slot rather than being dropped.
static func claim(state: Dictionary, peer: int, role: int, max_shooters: int) -> Dictionary:
	if role == ROLE_ZOMBIE:
		if state.get("zombie", 0) == peer:
			return _copy(state)  # already zombie — idempotent
		if int(state.get("zombie", 0)) != 0:
			return _copy(state)  # taken by someone else — refuse, keep current slot
		var s := remove(state, peer)  # release old shooter slot, take zombie
		s["zombie"] = peer
		return s
	else:  # ROLE_HUMAN / shooter
		if peer in (state.get("shooters", []) as Array):
			return _copy(state)  # already a shooter — idempotent
		if (state.get("shooters", []) as Array).size() >= max_shooters:
			return _copy(state)  # full — refuse, keep current slot
		var s := remove(state, peer)  # release old zombie slot, take shooter
		s["shooters"].append(peer)
		return s

## The host may start only with a zombie and at least one shooter.
static func can_start(state: Dictionary) -> bool:
	return int(state.get("zombie", 0)) != 0 and not (state.get("shooters", []) as Array).is_empty()
