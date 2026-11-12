"""Bake first-person arms + torch from arms.blend for the viewmodel.

Run headless (the .blend is read, never saved):
  /Applications/Blender.app/Contents/MacOS/Blender -b assets/blender/other/arms.blend \
    --python assets/blender/other/build_fp_arms.py
Writes assets/weapons/fp_arms.glb with:
  Arms_grip, Arms_open  skinned arms, one armature each, with the fingers curled
                        (grip) or relaxed (open) baked in as the rest pose. Meshes
                        ArmL_* / ArmR_* are split by side so each can be hidden.
                        scripts/3d/viewmodel.gd poses the upper arm, forearm and
                        hand bones every frame (so the wrist and elbow bend).
  Torch                 static: origin = where the hand grips it, beam toward -Z,
                        ~0.2 m long.
"""
import bpy, bmesh, os, math
from mathutils import Vector, Matrix, Quaternion

TORCH_M = 0.20
TORCH_GRIP = 0.40   # grip point, fraction of the length back from the lens
# Finger curl in degrees per bone. "Beginning" bones are the knuckle roots.
POSES = {
    "grip": {"root": 15.0, "mid": 80.0, "tip": 65.0, "thumb": 55.0, "thumb_tip": 30.0},
    "open": {"root": 5.0, "mid": 12.0, "tip": 10.0, "thumb": 10.0, "thumb_tip": 5.0},
}
OUT = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", "weapons", "fp_arms.glb"))

arm = bpy.data.objects["Armature"]
model = bpy.data.objects["ArmModel"]
torch = bpy.data.objects["Torch"]
W = arm.matrix_world


def side(name):
    return "R" if (".R" in name or name.endswith(".001")) else "L"


def role(name):
    n = name.split(".")[0]
    if n.startswith("Thumb"):
        return "thumb_tip" if n == "ThumbTip" else ("thumb" if n == "Thumb" else None)
    if n.endswith("Beginning"):
        return "root"
    if n.endswith("Tip"):
        return "tip"
    if n in ("DoubleFingers", "Index"):
        return "mid"
    return None


def set_pose(a, p):
    for pb in a.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        r = role(pb.name)
        if r is None:
            continue
        s = side(pb.name)
        if r.startswith("thumb"):
            # thumbs sit on the inner side; tuck them under, toward the palm
            axis_w, ang = Vector((1, 0, 0)), p[r] * (1.0 if s == "L" else -1.0)
        else:
            axis_w, ang = Vector((0, 1, 0)), p[r]  # +Y curl swings +X fingers down
        axis_a = (W.to_3x3().inverted() @ axis_w).normalized()
        axis_b = (a.data.bones[pb.name].matrix_local.to_3x3().inverted() @ axis_a).normalized()
        pb.rotation_quaternion = Quaternion(axis_b, math.radians(ang))
    bpy.context.view_layer.update()


coll = bpy.data.collections.new("fp_export")
bpy.context.scene.collection.children.link(coll)
dominant = []
for v in model.data.vertices:
    g = max(v.groups, key=lambda g: g.weight) if v.groups else None
    dominant.append(side(model.vertex_groups[g.group].name) if g else "L")

made = []
for pose_name, p in POSES.items():
    a = arm.copy()
    a.data = arm.data.copy()
    a.name = "Arms_" + pose_name
    a.animation_data_clear()
    coll.objects.link(a)
    set_pose(a, p)
    made.append(a)
    for s in ("L", "R"):
        o = model.copy()
        o.data = model.data.copy()
        o.name = f"Arm{s}_{pose_name}"
        o.parent = a
        for md in o.modifiers:
            if md.type == "ARMATURE":
                md.object = a
        coll.objects.link(o)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if dominant[v.index] != s], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
        made.append(o)

# torch: long axis -> beam forward, origin at the grip
torch.name = "TorchSrc"
tme = torch.data.copy()
tme.transform(torch.matrix_world)
ext = [max(v.co[i] for v in tme.vertices) - min(v.co[i] for v in tme.vertices) for i in range(3)]
long_axis = ext.index(max(ext))
if long_axis != 1:  # rotate the long axis onto Y
    tme.transform(Matrix.Rotation(math.pi / 2, 4, "X" if long_axis == 2 else "Z"))
lens_idx = [i for i, m in enumerate(tme.materials) if m and m.name == "LightBlue"]
lens = [tme.vertices[v].co for f in tme.polygons if f.material_index in lens_idx for v in f.vertices]
ys = [v.co.y for v in tme.vertices]
length = max(ys) - min(ys)
lens_y = sum(v.y for v in lens) / len(lens) if lens else max(ys)
flip = lens_y < (max(ys) + min(ys)) / 2          # lens must end up at +Y (Godot -Z)
cx = sum(v.co.x for v in tme.vertices) / len(tme.vertices)
cz = sum(v.co.z for v in tme.vertices) / len(tme.vertices)
front = min(ys) if flip else max(ys)
grip_y = front + (length * TORCH_GRIP if flip else -length * TORCH_GRIP)
m = Matrix.Translation(Vector((-cx, -grip_y, -cz)))
if flip:
    m = Matrix.Rotation(math.pi, 4, "Z") @ m
tme.transform(Matrix.Scale(TORCH_M / length, 4) @ m)
to = bpy.data.objects.new("Torch", tme)
coll.objects.link(to)
made.append(to)

bpy.ops.object.select_all(action="DESELECT")
for o in made:
    o.select_set(True)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
# current pose as the joints' rest: Godot imports the arms already curled/relaxed
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_rest_position_armature=False, export_animations=False)
print("FP_ARMS", OUT, [o.name for o in made])
