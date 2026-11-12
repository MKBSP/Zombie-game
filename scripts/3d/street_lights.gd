extends Node3D
## Lines both kerbs of a road mesh with StreetLights (scripts/3d/street_light.gd)
## every Balance.STREET_LIGHTS.spacing_m, the far kerb staggered by half.
##
## Reads the road strips' UVs as baked by assets/blender/maps/build_small_city.py:
## u = metres along, v = metres across from the centreline, so a triangle edge
## with both ends at the same |v| = half width is a kerb. Spots that land on
## another road (junctions), under a building / tree, or too close to a lamp
## already placed are dropped. Runs once at the first physics frame (rays need
## the physics space); spots and states are deterministic, so every peer builds
## the same street. Checked headless by test/test_street_lights.gd.

const Lamp := preload("res://scripts/3d/street_light.gd")
const B := preload("res://scripts/balance.gd")

@export var roads: NodePath = ^"../City/Roads"


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	var mi := get_node_or_null(roads) as MeshInstance3D
	if mi == null:
		push_warning("street_lights: no road mesh at %s" % roads)
		return
	var tris := PackedVector3Array()
	var uvs := PackedVector2Array()
	for s in mi.mesh.get_surface_count():
		var a := mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		for i: int in a[Mesh.ARRAY_INDEX]:
			tris.append(mi.global_transform * v[i])
			uvs.append(uv[i])
	var S: Dictionary = B.STREET_LIGHTS
	var space := get_world_3d().direct_space_state
	var placed: Array[Vector3] = []
	for spot in kerb_spots(tris, uvs, S.spacing_m, S.kerb_offset_m):
		var p: Vector3 = spot.pos
		if on_road(p, tris) or placed.any(func(q: Vector3) -> bool: return q.distance_to(p) < S.min_gap_m):
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 60.0, p + Vector3.DOWN * 5.0))
		if hit.is_empty() or hit.position.y > p.y + 0.5:
			continue  # off the map, or under a building / tree
		p.y = hit.position.y
		var lamp := Lamp.new()
		lamp.transform = global_transform.affine_inverse() * Transform3D(Basis.looking_at(-spot.out), p)
		add_child(lamp)
		placed.append(p)


## Kerb spots for road triangles (3 world vertices + UVs each): positions
## `offset` behind the kerb line, and `out` = the kerb's outward normal (away
## from the road). Spots sit at u = k * spacing on the +v kerb and half a
## spacing later on the -v kerb.
static func kerb_spots(tris: PackedVector3Array, uvs: PackedVector2Array, spacing: float, offset: float) -> Array[Dictionary]:
	var spots: Array[Dictionary] = []
	for t in range(0, tris.size() - 2, 3):
		var hw := maxf(absf(uvs[t].y), maxf(absf(uvs[t + 1].y), absf(uvs[t + 2].y)))
		for e in 3:
			var i := t + e
			var j := t + (e + 1) % 3
			var k := t + (e + 2) % 3
			if uvs[i].y * uvs[j].y <= 0.0 or minf(absf(uvs[i].y), absf(uvs[j].y)) < hw - 0.05:
				continue  # not an edge along a kerb
			var a := tris[i]
			var b := tris[j]
			var ua := uvs[i].x
			var ub := uvs[j].x
			if ua > ub:
				var tmp := a
				a = b
				b = tmp
				ua = uvs[j].x
				ub = uvs[i].x
			if ub - ua < 0.01:
				continue
			var o := Vector3(b.z - a.z, 0.0, a.x - b.x).normalized()
			if o.dot(a - tris[k]) < 0.0:
				o = -o
			var phase := 0.0 if uvs[i].y > 0.0 else spacing * 0.5
			var u := ceilf((ua - phase) / spacing) * spacing + phase
			while u < ub:
				spots.append({pos = a.lerp(b, (u - ua) / (ub - ua)) + o * offset, out = o})
				u += spacing
	return spots


## True if p (XZ) lies on any of the road triangles.
static func on_road(p: Vector3, tris: PackedVector3Array) -> bool:
	var q := Vector2(p.x, p.z)
	for t in range(0, tris.size() - 2, 3):
		if Geometry2D.point_is_inside_triangle(q, Vector2(tris[t].x, tris[t].z),
				Vector2(tris[t + 1].x, tris[t + 1].z), Vector2(tris[t + 2].x, tris[t + 2].z)):
			return true
	return false
