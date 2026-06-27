extends RefCounted
class_name LootTable

## Pure, headless-testable loot rolls. No engine/scene state.


## Items in a box: chance_three -> 3, else chance_two -> 2, else 1.
## `r` is expected in [0, 1).
static func roll_item_count(r: float, chance_two: float, chance_three: float) -> int:
	if r < chance_three:
		return 3
	if r < chance_two:
		return 2
	return 1


## Pick a kind from `weights` ({kind_int: weight_int}) by a cumulative walk over
## sorted keys. `r` in [0, 1) maps onto the normalized cumulative ranges.
static func roll_kind(r: float, weights: Dictionary) -> int:
	var keys := weights.keys()
	keys.sort()
	var total := 0
	for k in keys:
		total += int(weights[k])
	if total <= 0:
		return keys[0]
	var threshold := r * float(total)
	var acc := 0.0
	for k in keys:
		acc += float(weights[k])
		if threshold < acc:
			return k
	return keys[keys.size() - 1]
