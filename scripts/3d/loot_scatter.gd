extends RefCounted
## Random but even placement (loot crates): a jittered grid. The map is cut into
## about `count` near-square cells; each cell, in a seeded random order, gets one
## point at a random spot inside it, if accept() allows one there and it is at
## least min_sep from every point already placed. A cell with no valid spot (all
## building) stays empty. Same seed, same points. Checked headless by
## test/test_loot_scatter.gd.


## accept(p: Vector2) -> Vector2: the valid point to use for candidate p (it may
## move it, e.g. onto the navmesh), or Vector2.INF to reject it.
static func scatter(rect: Rect2, count: int, seed: int, min_sep: float, accept: Callable) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cols := maxi(1, roundi(sqrt(count * rect.size.x / rect.size.y)))
	var rows := ceili(float(count) / cols)
	var cell := rect.size / Vector2(cols, rows)
	var cells := []
	for r in rows:
		for c in cols:
			cells.append(Vector2(c, r))
	for i in range(cells.size() - 1, 0, -1):  # seeded shuffle (Array.shuffle uses the global rng)
		var j := rng.randi_range(0, i)
		var t: Vector2 = cells[i]
		cells[i] = cells[j]
		cells[j] = t
	var out := PackedVector2Array()
	for c: Vector2 in cells.slice(0, count):
		for attempt in 30:
			var p: Vector2 = accept.call(rect.position + (c + Vector2(rng.randf(), rng.randf())) * cell)
			if p != Vector2.INF and Array(out).all(func(q: Vector2) -> bool: return q.distance_to(p) >= min_sep):
				out.append(p)
				break
	return out
