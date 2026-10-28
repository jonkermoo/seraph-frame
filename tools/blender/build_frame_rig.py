"""Build the Frame template rig from frame_rig.json: an armature, one plain block per armour slot, joint markers,
and colour-coded slot-map renders in the cel look.

Run headless:
    blender -b --factory-startup --python tools/blender/build_frame_rig.py -- <frame_rig.json> <out_dir>

Writes to <out_dir>: slots_front/side/three_quarter.png, skeleton_front/side.png, slot_map.md and frame_rig.blend.
"""

import json
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cel  # noqa: E402

# bone tails for joints with no child: Neck -> head top (absolute), Wrist -> hand end, Ankle -> toe (x, y offsets; z absolute)
LEAF_TAILS = {"Neck": Vector((0, -1, 133)), "Wrist": Vector((1, -1, 64)), "Ankle": Vector((0, -12, 1))}
PILOT_STUDS = 5  # custom R6 pilot height, for scale


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    return os.path.abspath(argv[0]), os.path.abspath(argv[1])


def mirrored(entries):
    """Expand left-side entries (mirror=true) into left and right."""
    out = []
    for e in entries:
        out.append(e)
        if e.get("mirror"):
            r = dict(e)
            for key in ("name", "parent", "joint"):
                if r.get(key, "").endswith("L"):
                    r[key] = r[key][:-1] + "R"
            if "along" in r:
                r["along"] = [n[:-1] + "R" if n.endswith("L") else n for n in r["along"]]
            for key in ("pos", "centre"):
                if key in r:
                    r[key] = [-r[key][0], r[key][1], r[key][2]]
            out.append(r)
    return out


def hex_colour(h):
    """sRGB hex to the linear colour Blender's shader inputs expect."""
    rgb = [int(h[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return (*lin, 1.0)


def box_mesh(name, size, taper=None):
    """A box; `taper` [x, y] shrinks the bottom face (a V-shaped chest is a box with a narrow bottom)."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    if taper:
        for v in bm.verts:
            if v.co.z < 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def stick_mesh(name, a, b, radius):
    """A thin square bar from a to b, for drawing bones."""
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    length = (b - a).length
    bmesh.ops.scale(bm, vec=Vector((radius, radius, length)), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector((0, 0, length / 2)), verts=bm.verts)
    rot = Vector((0, 0, 1)).rotation_difference(b - a).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(a) @ rot, verts=bm.verts)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def leaf_tail(joint):
    for prefix, tail in LEAF_TAILS.items():
        if joint["name"].startswith(prefix):
            side = -1 if joint["name"].endswith("R") else 1
            pos = Vector(joint["pos"])
            return Vector((pos.x + tail.x * side, pos.y + tail.y, tail.z)) if prefix != "Neck" else tail
    return None


def build_armature(joints):
    arm_data = bpy.data.armatures.new("FrameRig")
    arm = bpy.data.objects.new("FrameRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    by_name = {j["name"]: j for j in joints}
    children = {}
    for j in joints:
        children.setdefault(j["parent"], []).append(j)
    for j in joints:
        bone = arm_data.edit_bones.new(j["name"])
        bone.head = Vector(j["pos"])
        kids = children.get(j["name"], [])
        if len(kids) == 1:
            bone.tail = Vector(kids[0]["pos"])
        elif kids:  # Root / Spine branch: point straight up to the next spine joint
            spine = [k for k in kids if not k["name"][-1] in "LR"]
            bone.tail = Vector(spine[0]["pos"]) if spine else bone.head + Vector((0, 0, 8))
        else:
            bone.tail = leaf_tail(j) or bone.head + Vector((0, 0, 8))
    for j in joints:
        if j["parent"]:
            arm_data.edit_bones[j["name"]].parent = arm_data.edit_bones[by_name[j["parent"]]["name"]]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def slot_matrix(slot, pos):
    """Where a slot's box (and any piece made for it) sits: its centre, long axis along its bone if it has one."""
    turn = Matrix.Identity(4)
    if "along" in slot:
        a, b = (pos[n] for n in slot["along"])
        turn = Vector((0, 0, -1)).rotation_difference(b - a).to_matrix().to_4x4()
    return Matrix.Translation(slot["centre"]) @ turn


def attach(obj, arm, bone_name, world):
    """Parent to a bone, placed at `world`: a bone parent's frame sits at the bone's tail."""
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    pose_bone = arm.pose.bones[bone_name]
    tail = arm.matrix_world @ pose_bone.matrix @ Matrix.Translation((0, pose_bone.bone.length, 0))
    obj.matrix_parent_inverse = tail.inverted()
    obj.matrix_basis = world


def build_slots(slots, joints, arm, ink):
    pos = {j["name"]: Vector(j["pos"]) for j in joints}
    objs = []
    for s in slots:
        obj = bpy.data.objects.new(s["name"], box_mesh(s["name"], s["size"], s.get("taper")))
        bpy.context.scene.collection.objects.link(obj)
        cel.dress(obj, cel.cel_material(s["name"], hex_colour(s["colour"])), ink)
        attach(obj, arm, s["joint"], slot_matrix(s, pos))
        s["offset"] = list(Vector(s["centre"]) - pos[s["joint"]])
        objs.append(obj)
    return objs


def build_skeleton_markers(joints, ink):
    mat = cel.cel_material("joint", (0.12, 0.12, 0.16, 1))
    pos = {j["name"]: Vector(j["pos"]) for j in joints}
    objs = []
    for j in joints:
        ball = bpy.data.objects.new("j_" + j["name"], box_mesh("j", (2.4, 2.4, 2.4)))
        ball.location = pos[j["name"]]
        objs.append(ball)
        end = pos[j["parent"]] if j["parent"] else None
        tail = leaf_tail(j)
        for a, b in ((end, pos[j["name"]]), (pos[j["name"]], tail)):
            if a is not None and b is not None:
                objs.append(bpy.data.objects.new("b_" + j["name"], stick_mesh("b", a, b, 0.9)))
    for o in objs:
        bpy.context.scene.collection.objects.link(o)
        cel.dress(o, mat, ink)
    return objs


def pilot_marker(ink):
    obj = bpy.data.objects.new("PilotR6", box_mesh("pilot", (2, 1, PILOT_STUDS)))
    obj.location = (-22, -10, PILOT_STUDS / 2)
    bpy.context.scene.collection.objects.link(obj)
    cel.dress(obj, cel.cel_material("pilot", (0.9, 0.9, 0.9, 1)), ink)
    return obj


def write_table(path, slots, joints, data):
    pos = {j["name"]: j["pos"] for j in joints}
    total = sum(s["tris"] for s in slots)
    with open(path, "w") as f:
        f.write("# Frame slot map\n\n")
        f.write(f"Height {data['height']} studs. Joints {len(joints)}. Slots {len(slots)}. ")
        f.write(f"Slot tris {total:,} + trim reserve {data['trimTrisReserve']:,} = {total + data['trimTrisReserve']:,} ")
        f.write(f"(x2 with outline hull = {(total + data['trimTrisReserve']) * 2:,}; budget 60,000). ")
        f.write(f"Parts: {len(slots)} slot pieces + up to {data['partBudget'] - len(slots)} trim pieces = {data['partBudget']}.\n\n")
        f.write("Blender axes: Z up, -Y front, +X the Frame's left. Attach point = the joint pivot; the piece's box centre sits at joint + offset.\n\n")
        f.write("| slot | colour | joint | attach point (studs) | box offset | box size (studs) | tri budget |\n")
        f.write("|---|---|---|---|---|---|---|\n")
        for s in slots:
            p = ", ".join(f"{v:g}" for v in pos[s["joint"]])
            o = ", ".join(f"{v:g}" for v in s["offset"])
            sz = " x ".join(f"{v:g}" for v in s["size"])
            f.write(f"| {s['name']} | #{s['colour']} | {s['joint']} | {p} | {o} | {sz} | {s['tris']:,} |\n")
        f.write("\n| joint | parent | position (studs) |\n|---|---|---|\n")
        for j in joints:
            f.write(f"| {j['name']} | {j['parent'] or '-'} | {', '.join(f'{v:g}' for v in j['pos'])} |\n")


def main():
    rig_path, out_dir = parse_args()
    os.makedirs(out_dir, exist_ok=True)
    with open(rig_path) as f:
        data = json.load(f)
    joints = mirrored(data["joints"])
    slots = mirrored(data["slots"])
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    ink = cel.ink_material()
    arm = build_armature(joints)
    blocks = build_slots(slots, joints, arm, ink)
    pilot = pilot_marker(ink)
    cam = cel.setup_render(out_dir)
    frame = blocks + [pilot]
    cel.shoot(cam, "slots_front", 0, frame, out_dir)
    cel.shoot(cam, "slots_side", 90, frame, out_dir)
    cel.shoot(cam, "slots_three_quarter", 35, frame, out_dir, pitch_deg=12)
    for obj in blocks:
        obj.hide_render = True
    markers = build_skeleton_markers(joints, ink)
    cel.shoot(cam, "skeleton_front", 0, markers + [pilot], out_dir)
    cel.shoot(cam, "skeleton_side", 90, markers + [pilot], out_dir)
    for obj in blocks:
        obj.hide_render = False
    for obj in markers:
        obj.hide_render = True
    write_table(os.path.join(out_dir, "slot_map.md"), slots, joints, data)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "frame_rig.blend"))
    print("RIG_DONE", len(joints), "joints", len(slots), "slots", sum(s["tris"] for s in slots), "tris")


if __name__ == "__main__":
    main()
