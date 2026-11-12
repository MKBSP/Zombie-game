"""Build the test-size city: crop the West Village map and tag it for the
procedural city shaders (shader/city_building.gdshader, city_ground.gdshader).

Run headless (the .blend is read, never saved):
  /Applications/Blender.app/Contents/MacOS/Blender -b \
    assets/blender/maps/manhattan_westvillage.blend \
    --python assets/blender/maps/build_small_city.py
Writes assets/city/westvillage_small.glb.

What it bakes into the mesh, because OSM has no doors/windows/shopfronts:
  * every wall face gets material "<base>__<side>", side = what the wall faces,
    found by stepping out from the wall and looking down for road surfaces:
      main   -> secondary road (shop street)   street -> residential road
      alley  -> service road                   back   -> yard / courtyard
      party  -> a neighbour within PARTY_GAP (blank wall)
  * wall UV  = (metres along the wall, metres above ground)
    wall UV2 = (wall length, building height)  -> the shader lays out floors/bays
  * vertex colour R/G = per-building random seeds (style, lit windows...)
  * road/sidewalk UV = (metres along, metres across from centreline)
  * footway faces lying on a road become "paths_crossing" (zebra stripes)
glTF flips V on export (v -> 1 - v), so every V written here is pre-flipped.
"""
import bpy, bmesh, os, random, json, collections
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

# ~250 x 170 m (10% of the 788 x 540 m map) around the v5 spawn, shifted west
# so the secondary road (the only shop street nearby) is inside.
# Godot (x, y, z) = Blender (x, z, -y); spawn Godot (8, 12) -> Blender (8, -12).
X0, X1, Y0, Y1 = -160.0, 90.0, -97.0, 73.0
GROUND_PAD = 20.0
BORDER_T, BORDER_H = 2.0, 20.0
OUT = os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", "city", "westvillage_small.glb")
MASK_OUT = OUT.replace(".glb", "_mask.png")
MASK_RES = 1.0      # metres per pixel
MASK_RANGE = 16.0   # metres of distance-to-street encoded in 0..1
# blosm floats the flat layers 0.3 m above the walkable Ground-col; drop them to
# just above it (layer order kept) so feet meet the asphalt.
LAYER_Z = {"Roads": 0.02, "Cycleways": 0.025, "Footways": 0.03, "PedestrianAreas": 0.02}
CROSSING_LIFT = 0.01
PARTY_GAP = 1.5     # a neighbour closer than this = shared/party wall (blank)
# consecutive wall faces join into one facade (curves, bow fronts) if they turn
# less than ~20 deg, or ~50 deg when one of them is a short curve piece
SMOOTH_DOT, CURVE_DOT, CURVE_PIECE = 0.94, 0.64, 3.0
REPORT = os.environ.get("CITY_REPORT")  # optional json dump of stats + sample viewpoints

SIDE_OF_ROAD = {"roads_secondary": "main", "roads_residential": "street",
                "roads_unclassified": "street", "roads_service": "alley"}
SIDE_RANK = ["main", "street", "alley"]  # first found wins within one sample
FLAT = ["Roads", "Footways", "Cycleways", "PedestrianAreas", "Ground-col", "Tree_01-col", "Tree_02-col"]
STRIPS = ["Roads", "Footways", "Cycleways"]  # blosm sweeps: u along, v 0..1 across
DOWN = Vector((0, 0, -1))

objs = bpy.data.objects


def inside(p, pad=0.0):
    return X0 - pad <= p.x <= X1 + pad and Y0 - pad <= p.y <= Y1 + pad


def bake_transform(o):
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)


def crop(o, pad=0.0):
    bake_transform(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for co, no in (((X1 + pad, 0, 0), (1, 0, 0)), ((X0 - pad, 0, 0), (-1, 0, 0)),
                   ((0, Y1 + pad, 0), (0, 1, 0)), ((0, Y0 - pad, 0), (0, -1, 0))):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                               plane_co=co, plane_no=no, clear_outer=True)
    bm.to_mesh(o.data)
    bm.free()


def box(o, xa, xb, ya, yb):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    c, s = Vector(((xa + xb) / 2, (ya + yb) / 2, BORDER_H / 2)), Vector((xb - xa, yb - ya, BORDER_H))
    for v in bm.verts:
        v.co = c + Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z))
    bm.to_mesh(o.data)
    bm.free()
    o.matrix_world = Matrix.Identity(4)


def bvh_of(polys_world):
    verts, faces = [], []
    for pts in polys_world:
        faces.append(list(range(len(verts), len(verts) + len(pts))))
        verts.extend(pts)
    return BVHTree.FromPolygons(verts, faces) if faces else None


def world_polys(o, pred=lambda p: True):
    mw, me = o.matrix_world, o.data
    return [[mw @ me.vertices[i].co for i in p.vertices] for p in me.polygons if pred(p)]


def over(bvh, p):
    return bvh is not None and bvh.ray_cast(Vector((p.x, p.y, 60.0)), DOWN, 200.0)[0] is not None


def material(me, name, src):
    """Index of material `name` on mesh `me`, copying `src` if it doesn't exist."""
    m = bpy.data.materials.get(name)
    if m is None:
        m = src.copy()
        m.name = name
    if m.name not in me.materials:
        me.materials.append(m)
    return list(me.materials).index(m)


# --- 1. crop ---------------------------------------------------------------
removed = 0
for o in list(objs):
    if o.type in ("CAMERA", "LIGHT"):
        objs.remove(o)
    elif o.name.startswith("Building"):
        if not all(inside(o.matrix_world @ Vector(v)) for v in o.bound_box):
            objs.remove(o)
            removed += 1
for n in FLAT:
    o = objs.get(n)
    if o:
        crop(o, GROUND_PAD if n == "Ground-col" else 0.0)
        if n in LAYER_Z:
            zmin = min(v.co.z for v in o.data.vertices) if o.data.vertices else 0.0
            for v in o.data.vertices:
                v.co.z += LAYER_Z[n] - zmin
        if not o.data.polygons:
            objs.remove(o)
T = BORDER_T
box(objs["Border_E-col"], X1, X1 + T, Y0 - T, Y1 + T)
box(objs["Border_W-col"], X0 - T, X0, Y0 - T, Y1 + T)
box(objs["Border_N-col"], X0 - T, X1 + T, Y1, Y1 + T)
box(objs["Border_S-col"], X0 - T, X1 + T, Y0 - T, Y0)

buildings = [o for o in objs if o.name.startswith("Building") and o.type == "MESH"]

# --- 2. lookup structures ----------------------------------------------------
roads = objs.get("Roads")
road_bvh = {}
if roads:
    for side in SIDE_RANK:
        idx = {i for i, m in enumerate(roads.data.materials) if m and SIDE_OF_ROAD.get(m.name) == side}
        road_bvh[side] = bvh_of(world_polys(roads, lambda p, idx=idx: p.material_index in idx))
any_road = bvh_of(world_polys(roads)) if roads else None
walk_bvh = bvh_of(sum((world_polys(objs[n]) for n in ("Footways", "PedestrianAreas") if n in objs), []))
bld_bvh = bvh_of(sum((world_polys(o) for o in buildings), []))
roofs_bvh = bvh_of(sum((world_polys(o, lambda p: abs(p.normal.z) >= 0.5) for o in buildings), []))


def wall_side(c, n):
    """What a wall at world point c with outward normal n looks onto."""
    if over(roofs_bvh, c + n * PARTY_GAP):  # just outside us is inside a neighbour
        return "party"
    hit = bld_bvh.ray_cast(c + n * 0.05, n, 40.0)
    limit = min(hit[3] if hit[0] is not None else 40.0, 30.0)
    saw_walk, d = False, 1.0
    while d <= limit:
        p = c + n * d
        for side in SIDE_RANK:
            if over(road_bvh.get(side), p):
                return side
        saw_walk = saw_walk or over(walk_bvh, p)
        d += 1.0
    return "street" if saw_walk else "back"


# --- 3. tag buildings ----------------------------------------------------------
stats = collections.Counter()
samples = {}
for o in buildings:
    me, mw = o.data, o.matrix_world
    rng = random.Random(str(o.get("id", o.name)))
    seed, seed2 = rng.random(), rng.random()
    zs = [v.co.z for v in me.vertices]
    zmin = min(zs)
    walls = [p for p in me.polygons if p.material_index == 0 and abs(p.normal.z) < 0.5]
    wall_idx = {p.index for p in walls}
    roof_bvh = bvh_of(world_polys(o, lambda p: p.index not in wall_idx))
    height = max((me.vertices[i].co.z for p in walls for i in p.vertices), default=max(zs)) - zmin
    uv = me.uv_layers.new(name="UVMap").data
    uv2 = me.uv_layers.new(name="UV2").data
    col = me.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    me.color_attributes.active_color = col
    srcs = list(me.materials)
    for p in me.polygons:
        for li in p.loop_indices:
            col.data[li].color = (seed, seed2, 0.5, 1.0)  # B = 0.5 marker, checked on the Godot side
    # pass 1: what each wall faces + its bottom edge a->b (loop order = ring order)
    info = {}
    for p in walls:
        n = (mw.to_3x3() @ p.normal).normalized()
        n.z = 0.0
        n.normalize()
        c = mw @ p.center
        if over(roof_bvh, c + n * 0.5):  # stepping "out" lands under our own roof
            n = -n
            stats["flipped_normal"] += 1
        c.z = zmin + 1.5
        side = wall_side(c, n)
        if side not in samples or rng.random() < 0.15:
            samples[side] = [c + n * 12.0, c]
        vs = list(p.vertices)
        fz = min(me.vertices[i].co.z for i in vs)
        pos = [k for k, i in enumerate(vs) if me.vertices[i].co.z < fz + 0.05]
        f = {"side": side, "a": None}
        if len(pos) == 2:
            ka, kb = (pos[1], pos[0]) if pos == [0, len(vs) - 1] else (pos[0], pos[1])
            e = me.vertices[vs[kb]].co - me.vertices[vs[ka]].co
            e.z = 0.0
            if e.length > 1e-3:
                f.update(a=vs[ka], b=vs[kb], len=e.length, dir=e.normalized())
        info[p.index] = f
    # pass 2: chain faces that continue each other within SMOOTH_DOT into one
    # facade, so bow fronts / curved corners get one continuous bay layout
    key = lambda vi: (round(me.vertices[vi].co.x, 2), round(me.vertices[vi].co.y, 2))
    starts = {key(f["a"]): i for i, f in info.items() if f["a"] is not None}
    nxt = {}
    for i, f in info.items():
        j = starts.get(key(f["b"])) if f["a"] is not None else None
        lim = CURVE_DOT if j is not None and min(f["len"], info[j]["len"]) < CURVE_PIECE else SMOOTH_DOT
        if j is not None and j != i and f["dir"].dot(info[j]["dir"]) > lim:
            nxt[i] = j
    heads = [i for i in info if i not in set(nxt.values())] + list(info)  # rings have no head
    seen, segments = set(), []
    for i in heads:
        if i in seen:
            continue
        seg = [i]
        seen.add(i)
        while seg[-1] in nxt and nxt[seg[-1]] not in seen:
            seg.append(nxt[seg[-1]])
            seen.add(seg[-1])
        segments.append(seg)
    # pass 3: one side (majority by length) and one u run per facade
    for seg in segments:
        side_len = collections.Counter()
        for i in seg:
            side_len[info[i]["side"]] += info[i].get("len", 1.0)
        side = side_len.most_common(1)[0][0]
        total = sum(info[i].get("len", 0.0) for i in seg)
        off = 0.0
        for i in seg:
            p, f = me.polygons[i], info[i]
            if f["a"] is None:  # odd face: lay out on its own
                t = Vector((-p.normal.y, p.normal.x, 0.0)).normalized()
                raw = [me.vertices[v].co.dot(t) for v in p.vertices]
                us, length = [u - min(raw) for u in raw], max(raw) - min(raw)
            else:
                a = me.vertices[f["a"]].co
                us = [off + (me.vertices[v].co - a).dot(f["dir"]) for v in p.vertices]
                length = total
                off += f["len"]
            for li, vi, u in zip(p.loop_indices, p.vertices, us):
                uv[li].uv = (u, 1.0 - (me.vertices[vi].co.z - zmin))
                uv2[li].uv = (length, 1.0 - height)
            p.material_index = material(me, f"{srcs[0].name}__{side}", srcs[0])
            stats[side] += 1
        stats["facades"] += 1

# --- 4. road / sidewalk UVs in metres, crossings --------------------------------
crossing_src = None
for n in STRIPS:
    o = objs.get(n)
    if not o or not o.data.uv_layers:
        continue
    me = o.data
    uv = me.uv_layers.active.data
    for p in me.polygons:
        loops, vs = list(p.loop_indices), [me.vertices[i].co for i in p.vertices]
        uvs = [uv[li].uv.copy() for li in loops]
        along = None
        for i in range(len(loops)):
            j = (i + 1) % len(loops)
            e = vs[j] - vs[i]
            if abs(uvs[i].y - uvs[j].y) < 1e-4 and abs(uvs[i].x - uvs[j].x) > 1e-6 and e.length > 1e-3:
                along = e if uvs[j].x > uvs[i].x else -e
                break
        if along is None:
            along = max((vs[(i + 1) % len(vs)] - vs[i] for i in range(len(vs))), key=lambda e: e.length)
        along = Vector((along.x, along.y, 0)).normalized()
        perp = Vector((-along.y, along.x, 0))
        for li, co in zip(loops, vs):
            uv[li].uv = (co.dot(along), 1.0 - (co - p.center).dot(perp))
        if n == "Footways" and over(any_road, p.center):
            crossing_src = crossing_src or me.materials[p.material_index]
            p.material_index = material(me, "paths_crossing", crossing_src)
            for i in p.vertices:
                me.vertices[i].co.z += CROSSING_LIFT
            stats["crossing_faces"] += 1

# --- 5. distance-to-street mask for the bare ground ----------------------------
# Ground-col is one quad; the shader paves it near streets and turns it into
# backlot/alley further in. R = distance to the nearest road/footway / MASK_RANGE.
flat = []
for n in ("Roads", "Footways", "PedestrianAreas", "Cycleways"):
    if n in objs:
        flat += [[Vector((v.x, v.y, 0.0)) for v in poly] for poly in world_polys(objs[n])]
flat_bvh = bvh_of(flat)
mx0, my0 = X0 - GROUND_PAD, Y0 - GROUND_PAD
mw_, mh_ = int((X1 - X0 + 2 * GROUND_PAD) / MASK_RES), int((Y1 - Y0 + 2 * GROUND_PAD) / MASK_RES)
img = bpy.data.images.new("street_mask", mw_, mh_, alpha=False)
px = [0.0] * (mw_ * mh_ * 4)
for j in range(mh_):          # Blender rows run bottom-up
    for i in range(mw_):
        hit = flat_bvh.find_nearest(Vector((mx0 + (i + 0.5) * MASK_RES, my0 + (j + 0.5) * MASK_RES, 0.0)))
        d = min((hit[3] if hit[0] is not None else MASK_RANGE) / MASK_RANGE, 1.0)
        k = (j * mw_ + i) * 4
        px[k:k + 4] = (d, d, d, 1.0)
img.pixels = px
img.filepath_raw = os.path.normpath(MASK_OUT)
img.file_format = "PNG"
img.save()
# Rect travels with the mesh as glTF extras -> Godot node metadata.
objs["Ground-col"]["street_mask_rect"] = [mx0, my0, mw_ * MASK_RES, mh_ * MASK_RES]
objs["Ground-col"]["street_mask_range"] = MASK_RANGE

# --- 6. export -----------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(o.type == "MESH")
bpy.ops.export_scene.gltf(filepath=os.path.normpath(OUT), export_format="GLB", use_selection=True,
                          export_extras=True, export_vertex_color="ACTIVE", export_yup=True)

stats["buildings"] = len(buildings)
stats["buildings_removed"] = removed
print("CITY_STATS", dict(stats))
if REPORT:
    to_godot = lambda v: [round(v.x, 2), round(v.z, 2), round(-v.y, 2)]
    with open(REPORT, "w") as f:
        json.dump({"stats": dict(stats),
                   "views": {k: [to_godot(a), to_godot(b)] for k, (a, b) in samples.items()}}, f, indent=1)
