extends RefCounted
class_name StanceLogic

static func flip_leg(current_leg: int) -> int:
	return 1 - current_leg

static func arrived(distance: float, arrive_px: float) -> bool:
	return distance <= arrive_px
