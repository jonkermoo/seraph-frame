"""The unarmoured base body every Frame shares: lanky muscle and sinew forms, one rigid part per rig bone.

Armour pieces go on top of it, so wherever a piece covers the body the base must stay inside that piece. The check
here builds the placeholder pieces too and looks at every base vertex: one that sits outside all armour, with armour
just beneath it (along its inward normal) and between it and its bone, has come out through that armour.

Two tones (flesh and sinew) in one part come from a small palette texture: every face's UVs point at one pixel.
The chest and the back each get an empty socket (a sinew ring plus an attachment point) for designs made later.

Run headless:
    blender -b --factory-startup --python tools/blender/build_frame_base.py -- <frame_rig.json> <out_dir>

Writes to <out_dir>: base_front/back/three_quarter.png, armoured_front/three_quarter.png,
compare_front.png and compare_three_quarter.png (bare | armoured), palette.png, base.md and frame_base.blend.
"""

import json
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, geometry
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_frame_pieces as pieces  # noqa: E402
import build_frame_rig as rig  # noqa: E402
import cel  # noqa: E402

FLESH = "7E6A66"  # muted brown-grey
SINEW = "CDBFB0"  # pale tendon and bone
TONES = (FLESH, SINEW)
PART_BUDGET = 15
TRI_BUDGET = 20000
POKE_REACH = 3.0  # studs under a base vertex to look for armour it has come out through


# --- shapes (world space, left side; sym=True also adds the mirror image, for parts on the centre line) ------------


class Part:
    def __init__(self, bone):
        self.bone = bone
        self.bms = {t: bmesh.new() for t in TONES}

    def _add(self, tone, tmp, sym):
        if sym:
            twin = tmp.copy()
            bmesh.ops.scale(twin, vec=Vector((-1, 1, 1)), verts=twin.verts)
            bmesh.ops.reverse_faces(twin, faces=twin.faces)
            pieces.merge(self.bms[tone], twin)
        pieces.merge(self.bms[tone], tmp)

    def blob(self, centre, radii, tone=FLESH, along=None, segs=8, rings=6, sym=False):
        """A faceted ellipsoid; with `along` its third radius lies along that direction (a muscle belly)."""
        tmp = bmesh.new()
        bmesh.ops.create_uvsphere(tmp, u_segments=segs, v_segments=rings, radius=1.0)
        bmesh.ops.scale(tmp, vec=Vector(radii), verts=tmp.verts)
        turn = Vector((0, 0, 1)).rotation_difference(Vector(along)).to_matrix().to_4x4() if along else Matrix()
        bmesh.ops.transform(tmp, matrix=Matrix.Translation(centre) @ turn, verts=tmp.verts)
        self._add(tone, tmp, sym)

    def rope(self, a, b, ra, rb, tone=FLESH, sides=6, sym=False):
        """A tapered prism from a (radius ra) to b (radius rb): limb cores, tendons, the neck."""
        a, b = Vector(a), Vector(b)
        tmp = bmesh.new()
        bmesh.ops.create_cone(tmp, cap_ends=True, segments=sides, radius1=rb, radius2=ra, depth=(b - a).length)
        turn = Vector((0, 0, 1)).rotation_difference(a - b).to_matrix().to_4x4()
        bmesh.ops.transform(tmp, matrix=Matrix.Translation((a + b) / 2) @ turn, verts=tmp.verts)
        self._add(tone, tmp, sym)

    def box(self, size, at, tone=FLESH, taper=None, bevel=0.0, sym=False):
        tmp = bmesh.new()
        pieces.add_box(tmp, size, at=at, taper=taper, bevel=bevel)
        self._add(tone, tmp, sym)

    def socket(self, at, facing):
        """An empty socket: a sinew ring round a flesh plug, for an attachment made later."""
        ring, plug = bmesh.new(), bmesh.new()
        f = Vector(facing)
        pieces.add_disc(ring, 2.6, 0.8, at=Vector(at), facing=facing)
        pieces.add_disc(plug, 1.8, 0.8, at=Vector(at) + f * 0.15, facing=facing)
        self._add(SINEW, ring, False)
        self._add(FLESH, plug, False)


def head():
    p = Part("Neck")
    p.rope((0, -0.4, 116.5), (0, -1.0, 123.5), 2.4, 2.0, sides=8)
    p.rope((1.6, -2.2, 117.5), (1.9, -1.2, 123.0), 0.6, 0.5, tone=SINEW, sides=5, sym=True)
    p.blob((0, -1.4, 126.4), (3.0, 3.6, 4.0), segs=10, rings=7)
    p.blob((0, -4.3, 126.2), (2.1, 0.9, 2.7), tone=SINEW)  # plain face plate, no features yet
    return p


def torso():
    p = Part("Spine")
    p.blob((0, 0.6, 110.5), (8.6, 5.4, 8.6), segs=10, rings=8)  # rib cage
    p.rope((0, 0.3, 92.5), (0, 0.5, 103), 2.9, 4.8, sides=8)  # belly up to the ribs
    p.blob((5.0, -3.9, 113.0), (5.0, 2.0, 3.2), sym=True)  # pecs
    p.blob((7.0, -0.6, 116.4), (1.9, 1.9, 5.0), along=(1, 0, -0.35), sym=True)  # collar out to the shoulder
    for z in (103.4, 100.4, 97.4, 94.6):  # abs
        p.box((2.6, 1.4, 2.6), (1.55, -3.9, z), bevel=0.4, sym=True)
    for z in (108.5, 106.0):  # serratus bands
        p.rope((7.0, -1.5, z), (5.0, -3.0, z - 4.0), 0.6, 0.5, tone=SINEW, sym=True)
    p.blob((4.8, 1.2, 117.3), (4.6, 2.8, 2.4), sym=True)  # trapezius
    p.blob((5.2, 2.8, 107.5), (2.8, 2.6, 7.0), sym=True)  # lats
    p.rope((0, 4.2, 96.5), (0, 5.6, 117), 0.7, 0.7, tone=SINEW)  # spine ridge
    p.socket((0, -5.2, 109.5), (0, -1, 0))  # core socket
    p.socket((0, 5.5, 108.5), (0, 1, 0))  # spine socket
    return p


def pelvis():
    p = Part("Root")
    p.rope((0, 0.3, 93.5), (0, 0.2, 76), 2.9, 3.4, sides=8)
    for z in (86.6, 83.6):  # lower abs
        p.box((2.4, 1.3, 2.5), (1.4, -2.9, z), bevel=0.4, sym=True)
    p.rope((0, 0.3, 77.5), (0, 0.3, 69.5), 3.3, 4.6, sides=8)
    p.blob((0, -0.8, 68.8), (2.0, 2.0, 2.4))
    return p


def thigh():
    p = Part("HipL")
    p.blob((4.4, 1.6, 71.6), (2.2, 2.0, 2.4))  # glute
    p.blob((4.6, 0, 71.5), (2.5, 2.5, 2.5))  # hip ball
    p.rope((4.8, -0.1, 70.5), (9.6, -0.9, 53.5), 2.7, 2.1)
    p.blob((7.1, -1.4, 63), (2.0, 1.7, 6.5), along=(4.3, -0.7, -15))  # quads
    p.blob((7.3, 1.1, 62), (1.8, 1.5, 7.0), along=(4.3, -0.7, -15))  # hamstring
    p.rope((4.8, -1.0, 67), (8.4, -1.8, 54.5), 0.55, 0.45, tone=SINEW)
    return p


def shin():
    p = Part("KneeL")
    p.rope((9.95, -0.8, 53.2), (10.4, -0.6, 48), 2.0, 2.0)
    p.blob((10, -2.6, 51.2), (1.7, 1.0, 2.0), tone=SINEW)  # kneecap
    p.rope((10.4, -0.7, 49), (13.3, 0.8, 20), 1.9, 1.3)
    p.blob((11.0, 0.3, 41), (1.8, 1.4, 7.0), along=(3.5, 2, -33))  # calf
    p.rope((10.6, -2.0, 47), (13.0, -1.0, 22), 0.9, 0.7, tone=SINEW)  # shin bone
    p.rope((12.4, 1.6, 32), (13.4, 2.1, 19), 0.5, 0.5, tone=SINEW)  # heel tendon
    return p


def foot():
    p = Part("AnkleL")
    p.rope((13.4, 0.9, 19.5), (13.5, 0.0, 5), 1.6, 1.6)
    p.blob((13.5, 1.4, 3.8), (1.6, 1.6, 1.8), tone=SINEW)  # heel
    p.box((4.2, 12, 3.4), (13.5, -4.5, 2.6), taper=(0.8, 0.9), bevel=0.5)
    p.blob((13.5, -9.0, 2.2), (1.8, 1.1, 1.1), tone=SINEW)  # toe cap
    p.rope((13.5, -1.5, 7), (13.5, -7.5, 4.2), 0.5, 0.5, tone=SINEW)
    return p


def upper_arm():
    p = Part("ShoulderL")
    p.blob((16.9, -0.8, 113.4), (3.2, 3.3, 3.3))  # deltoid
    p.rope((15.4, -0.9, 111), (16.9, -0.1, 97), 1.8, 1.5)
    p.blob((16.2, -1.4, 103), (1.5, 1.3, 5.0), along=(2, 1, -14))  # biceps
    p.blob((16.0, 0.2, 104), (1.5, 1.3, 5.5), along=(2, 1, -14))  # triceps
    p.blob((17.0, 0.2, 96), (1.7, 1.7, 1.8), tone=SINEW)  # elbow
    return p


def forearm():
    p = Part("ElbowL")
    p.rope((17.2, -0.1, 94.5), (18.9, -1.0, 80.5), 2.0, 1.4)
    p.blob((17.8, -0.9, 90), (1.6, 1.4, 5.0), along=(2, -1, -17))
    p.rope((17.9, 0.9, 93), (19.0, 0.0, 81), 0.6, 0.6, tone=SINEW)
    p.rope((18.85, -0.95, 80.2), (19.05, -1.0, 78.4), 1.6, 1.6, tone=SINEW, sides=8)  # wrist band
    return p


def hand():
    p = Part("WristL")
    p.box((2.4, 6.4, 5.0), (19.5, -1.5, 75.6), bevel=0.3)
    for y in (-3.9, -1.5, 0.9):
        p.rope((19.5, y, 73.2), (19.5, y, 67.4 if y != -1.5 else 66.7), 0.85, 0.75)
        p.blob((19.5, y, 73.0), (0.9, 0.85, 0.7), tone=SINEW)  # knuckles
    p.rope((19.3, -3.4, 75.2), (19.0, -4.2, 71.8), 0.6, 0.55)  # thumb
    return p


PARTS = (head, torso, pelvis, thigh, shin, foot, upper_arm, forearm, hand)


# --- building -----------------------------------------------------------------------------------------------------


def palette_image(out_dir):
    image = bpy.data.images.new("palette", len(TONES), 1)
    px = []
    for t in TONES:
        px += [int(t[i : i + 2], 16) / 255 for i in (0, 2, 4)] + [1.0]
    image.pixels = px
    image.filepath_raw = os.path.join(out_dir, "palette.png")
    image.file_format = "PNG"
    image.save()
    return image


def to_mesh(name, part, mirror):
    """Join a part's tones into one mesh, each face's UVs on its tone's palette pixel."""
    out = bmesh.new()
    for i, tone in enumerate(TONES):
        bm = part.bms[tone]
        if mirror:
            bm = bm.copy()
            bmesh.ops.scale(bm, vec=Vector((-1, 1, 1)), verts=bm.verts)
            bmesh.ops.reverse_faces(bm, faces=bm.faces)
        uv = bm.loops.layers.uv.verify()
        for face in bm.faces:
            for loop in face.loops:
                loop[uv].uv = ((i + 0.5) / len(TONES), 0.5)
        pieces.merge(out, bm.copy())
    mesh = bpy.data.meshes.new(name)
    out.to_mesh(mesh)
    out.free()
    return mesh


def build_base(arm, mat, ink):
    objs = []
    for make in PARTS:
        part = make()
        sides = [(part.bone, False)]
        if part.bone.endswith("L"):
            sides.append((part.bone[:-1] + "R", True))
        for bone, mirror in sides:
            obj = bpy.data.objects.new("Base_" + bone, to_mesh("Base_" + bone, part, mirror))
            bpy.context.scene.collection.objects.link(obj)
            cel.dress(obj, mat, ink)
            rig.attach(obj, arm, bone, Matrix())
            objs.append(obj)
    return objs


def add_sockets(arm):
    """Attachment points for the chest core and the spine piece (Roblox Attachments later)."""
    out = []
    for name, at in (("Socket_Core", (0, -5.6, 109.5)), ("Socket_Spine", (0, 5.9, 108.5))):
        empty = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(empty)
        rig.attach(empty, arm, "Spine", Matrix.Translation(at))
        out.append(name)
    return out


# --- the poke-through check ----------------------------------------------------------------------------------------


def islands(obj):
    """An armour part's closed pieces (its primitives), each as (bvh, lo, hi) in world space."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    verts = [v.co.copy() for v in bm.verts]
    seen, out = set(), []
    for start in bm.faces:
        if start.index in seen:
            continue
        group, stack = [], [start]
        seen.add(start.index)
        while stack:
            f = stack.pop()
            group.append([v.index for v in f.verts])
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        ids = {i for poly in group for i in poly}
        lo = Vector((min(verts[i][k] for i in ids) for k in range(3)))
        hi = Vector((max(verts[i][k] for i in ids) for k in range(3)))
        out.append((BVHTree.FromPolygons(verts, group), lo, hi))
    bm.free()
    return out


def inside(bvh, p):
    """Odd number of surface crossings along a ray means inside; majority of three rays against grazing hits."""
    votes = 0
    for d in (Vector((0.31, 0.12, 0.94)), Vector((0.88, -0.41, 0.23)), Vector((-0.2, 0.95, -0.24))):
        d.normalize()
        hits, origin = 0, p
        while True:
            loc, _, _, _ = bvh.ray_cast(origin, d)
            if loc is None:
                break
            hits += 1
            origin = loc + d * 1e-4
        votes += hits % 2
    return votes >= 2


def poke_check(base, armour, arm):
    all_islands = [i for obj in armour for i in islands(obj)]
    verts, polys = [], []
    for obj in armour:
        m = obj.matrix_world
        offset = len(verts)
        verts += [m @ v.co for v in obj.data.vertices]
        polys += [[offset + i for i in p.vertices] for p in obj.data.polygons]
    shell = BVHTree.FromPolygons(verts, polys)
    report = {}
    for obj in base:
        bone = arm.data.bones[obj.parent_bone]
        count, worst, where = 0, 0.0, None
        for v in obj.data.vertices:
            p = obj.matrix_world @ v.co
            if any(lo.x <= p.x <= hi.x and lo.y <= p.y <= hi.y and lo.z <= p.z <= hi.z and inside(b, p) for b, lo, hi in all_islands):
                continue
            # armour must lie both straight beneath the vertex and between it and its bone; either alone also
            # catches flesh that only sits next to a piece's edge or under its end (a seam or a joint)
            inward = -(obj.matrix_world.to_3x3() @ v.normal).normalized()
            under, _, _, _ = shell.ray_cast(p + inward * 1e-3, inward, POKE_REACH)
            q, t = geometry.intersect_point_line(p, bone.head_local, bone.tail_local)
            q = bone.head_local if t < 0 else bone.tail_local if t > 1 else q
            to_bone = q - p
            between = to_bone.length > 1e-6 and shell.ray_cast(p, to_bone.normalized(), to_bone.length)[0] is not None
            if under is not None and between:
                count += 1
                if (under - p).length > worst:
                    worst, where = (under - p).length, [round(c, 1) for c in p]
        report[obj.name] = (count, round(worst, 2), where)
    return report


# --- main ---------------------------------------------------------------------------------------------------------


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main():
    rig_path, out_dir = rig.parse_args()
    os.makedirs(out_dir, exist_ok=True)
    with open(rig_path) as f:
        data = json.load(f)
    joints = rig.mirrored(data["joints"])
    slots = rig.mirrored(data["slots"])
    pos = {j["name"]: Vector(j["pos"]) for j in joints}
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    ink = cel.ink_material()
    arm = rig.build_armature(joints)
    mat = cel.palette_material("base", palette_image(out_dir))
    base = build_base(arm, mat, ink)
    sockets = add_sockets(arm)
    armour, _, armour_rows, _ = pieces.build_pieces(slots, pos, arm, ink)
    pilot = rig.pilot_marker(ink)
    bpy.context.view_layer.update()
    pokes = poke_check(base, armour, arm)

    cam = cel.setup_render(out_dir)
    everything = base + armour + [pilot]  # one framing for bare and armoured, so the pairs line up
    for obj in armour:
        obj.hide_render = True
    cel.shoot(cam, "base_front", 0, everything, out_dir)
    cel.shoot(cam, "base_back", 180, everything, out_dir)
    cel.shoot(cam, "base_three_quarter", 35, everything, out_dir, pitch_deg=12)
    for obj in armour:
        obj.hide_render = False
    cel.shoot(cam, "armoured_front", 0, everything, out_dir)
    cel.shoot(cam, "armoured_three_quarter", 35, everything, out_dir, pitch_deg=12)
    cel.side_by_side(["base_front", "armoured_front"], "compare_front", out_dir)
    cel.side_by_side(["base_three_quarter", "armoured_three_quarter"], "compare_three_quarter", out_dir)

    base_tris = sum(tris(o) for o in base)
    armour_tris = sum(r[2] for r in armour_rows)
    with open(os.path.join(out_dir, "base.md"), "w") as f:
        f.write("# Frame base body\n\n")
        f.write(f"Base: {len(base)} parts (budget {PART_BUDGET}), {base_tris:,} tris (budget {TRI_BUDGET:,}), ")
        f.write(f"{base_tris * 2:,} with the outline hull. Two tones from a {len(TONES)}x1 palette texture.\n\n")
        f.write(f"With round-2 armour: {len(base) + len(armour)} parts (cap {data['partBudget']}), ")
        f.write(f"{base_tris + armour_tris:,} tris, {(base_tris + armour_tris) * 2:,} with hull (cap 60,000).\n\n")
        f.write(f"Sockets (attachments on Spine): {', '.join(sockets)}.\n\n")
        f.write("| part | bone | tris | poking vertices | worst poke (studs) | at |\n|---|---|---|---|---|---|\n")
        for obj in base:
            count, worst, where = pokes[obj.name]
            f.write(f"| {obj.name} | {obj.parent_bone} | {tris(obj):,} | {count} | {worst:g} | {where or '-'} |\n")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "frame_base.blend"))
    total_pokes = sum(r[0] for r in pokes.values())
    print("BASE_DONE", len(base), "parts", base_tris, "tris", "pokes", total_pokes, json.dumps(pokes))


if __name__ == "__main__":
    main()
