"""Grey placeholder armour pieces for every Frame slot, snapped to the template rig, plus a slot swap test.

Each piece is modelled in its slot's own space (origin at the slot centre, +Z towards the parent joint, -Y the
Frame's front) and only for the left side; right-side pieces are mirrored. Snapping a piece is placing it with the
slot's matrix, so swapping one is replacing the mesh of the slot's part and nothing else.

Run headless:
    blender -b --factory-startup --python tools/blender/build_frame_pieces.py -- <frame_rig.json> <out_dir>

Writes to <out_dir>: pieces_front/side/three_quarter.png, swap_a.png and swap_b.png (shoulder variants),
pieces.md (triangles, parts, fit) and frame_pieces.blend.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_frame_rig as rig  # noqa: E402
import cel  # noqa: E402

PLATE = "B8BCC4"
TRIM = "3A3D46"
GLOW = "FF8A2B"  # eye glow is a player colour, not a slot
FIT_TOLERANCE = 0.25  # studs a piece may poke out of its slot box


# --- shape helpers (all in slot space) ---------------------------------------------------------------------------


def add_box(bm, size, at=(0, 0, 0), taper=None, bevel=0.0, rot=None):
    """Box with an optional narrower bottom face and bevelled edges."""
    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0)
    if taper:
        for v in tmp.verts:
            if v.co.z < 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
    bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
    if bevel:
        bmesh.ops.bevel(tmp, geom=tmp.edges[:], offset=bevel, segments=1, affect="EDGES", profile=0.5)
    place = Matrix.Translation(at) @ (rot or Matrix.Identity(4))
    bmesh.ops.transform(tmp, matrix=place, verts=tmp.verts)
    merge(bm, tmp)


def add_prism(bm, size, at=(0, 0, 0), top=1.0, bottom=1.0, sides=8, rot=None):
    """Tapered prism along Z (limb segments, boot shafts); size is its bounding box."""
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=sides, radius1=bottom * 0.5, radius2=top * 0.5, depth=1.0)
    bmesh.ops.scale(tmp, vec=Vector(size), verts=tmp.verts)
    place = Matrix.Translation(at) @ (rot or Matrix.Identity(4))
    bmesh.ops.transform(tmp, matrix=place, verts=tmp.verts)
    merge(bm, tmp)


def add_disc(bm, radius, depth, at, facing):
    """Short cylinder whose flat face points along `facing` (chest seal, Lifeline socket)."""
    tmp = bmesh.new()
    bmesh.ops.create_cone(tmp, cap_ends=True, segments=12, radius1=radius, radius2=radius, depth=depth)
    turn = Vector((0, 0, 1)).rotation_difference(Vector(facing)).to_matrix().to_4x4()
    bmesh.ops.transform(tmp, matrix=Matrix.Translation(at) @ turn, verts=tmp.verts)
    merge(bm, tmp)


def merge(bm, tmp):
    mesh = bpy.data.meshes.new("tmp")
    tmp.to_mesh(mesh)
    tmp.free()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


# --- the pieces: each returns {colour: bmesh} for one slot size ----------------------------------------------------


def head_visor(s):
    plate, glow = bmesh.new(), bmesh.new()
    add_box(plate, (s[0] * 0.9, s[1] * 0.85, s[2] * 0.75), at=(0, 0.5, -s[2] * 0.1), taper=(0.75, 0.85), bevel=0.8)
    for side in (-1, 1):  # two short rear-swept fins
        add_box(plate, (0.8, s[1] * 0.4, 2.4), at=(side * s[0] * 0.28, s[1] * 0.2, s[2] * 0.28), rot=rot_x(-35))
    add_box(glow, (s[0] * 0.7, 0.8, 1.2), at=(0, -s[1] * 0.38, s[2] * 0.05))
    return {PLATE: plate, GLOW: glow}


def chest_seal(s):
    plate, trim = bmesh.new(), bmesh.new()
    add_box(plate, (s[0] * 0.95, s[1] * 0.9, s[2] * 0.95), taper=(0.22, 0.7), bevel=0.7)
    add_disc(trim, 3.6, 1.2, at=(0, -s[1] * 0.41, s[2] * 0.2), facing=(0, -1, 0))
    return {PLATE: plate, TRIM: trim}


def back_socket(s):
    plate, trim = bmesh.new(), bmesh.new()
    add_box(plate, (s[0] * 0.9, s[1] * 0.75, s[2] * 0.9), at=(0, -s[1] * 0.1, 0), taper=(0.7, 1), bevel=0.6)
    add_disc(trim, 3.0, 1.5, at=(0, s[1] * 0.3, s[2] * 0.2), facing=(0, 1, 0))
    return {PLATE: plate, TRIM: trim}


def waist_band(s):
    plate = bmesh.new()
    add_box(plate, (s[0] * 0.95, s[1] * 0.95, s[2] * 0.95), taper=(0.75, 0.9), bevel=0.5)
    return {PLATE: plate}


def side_plate(s):
    plate = bmesh.new()
    add_box(plate, (s[0] * 0.7, s[1] * 0.9, s[2] * 0.9), at=(s[0] * 0.1, 0, 0), taper=(0.6, 0.8), bevel=0.4)
    return {PLATE: plate}


def shoulder_block(s):
    """Swap variant A: a square pauldron block."""
    plate = bmesh.new()
    add_box(plate, (s[0] * 0.95, s[1] * 0.95, s[2] * 0.8), at=(0, 0, s[2] * 0.08), taper=(0.85, 0.85), bevel=1.2)
    return {PLATE: plate}


def shoulder_swept(s):
    """Swap variant B: three thin plates stepping down and out, swept back."""
    plate = bmesh.new()
    for i in range(3):
        add_box(
            plate,
            (s[0] * 0.55, s[1] * (0.88 - i * 0.12), 1.4),
            at=(-s[0] * 0.15 + i * 1.3, s[1] * 0.02 * i, s[2] * 0.22 - i * 2.8),
            rot=rot_y(-22) @ rot_x(8),
            bevel=0.3,
        )
    return {PLATE: plate}


def limb(top, bottom, sides=8):
    def build(s):
        plate = bmesh.new()
        add_prism(plate, (s[0] * 0.95, s[1] * 0.95, s[2] * 0.97), top=top, bottom=bottom, sides=sides)
        return {PLATE: plate}

    return build


def knee_cap(s):
    plate = bmesh.new()
    add_box(plate, (s[0] * 0.95, s[1] * 0.9, s[2] * 0.95), taper=(0.55, 0.5), bevel=0.4)
    return {PLATE: plate}


def hand_three_finger(s):
    """Large hand: palm block, three finger groups and a thumb."""
    plate = bmesh.new()
    add_box(plate, (s[0] * 0.9, s[1] * 0.9, s[2] * 0.42), at=(0, 0, s[2] * 0.27), bevel=0.3)
    for i, y in enumerate((-0.3, 0.0, 0.3)):
        length = s[2] * (0.5 if i == 1 else 0.44)
        add_box(plate, (s[0] * 0.75, s[1] * 0.26, length), at=(0, y * s[1], s[2] * 0.06 - length / 2), bevel=0.2)
    add_box(plate, (s[0] * 0.6, s[1] * 0.2, s[2] * 0.3), at=(-s[0] * 0.1, -s[1] * 0.28, s[2] * 0.12), rot=rot_x(25))
    return {PLATE: plate}


def boot_tall(s):
    plate = bmesh.new()
    add_prism(plate, (s[0] * 0.9, s[1] * 0.55, s[2] * 0.7), at=(0, s[1] * 0.15, s[2] * 0.15), top=1.0, bottom=0.85)
    add_box(plate, (s[0] * 0.95, s[1] * 0.97, s[2] * 0.3), at=(0, 0, -s[2] * 0.34), taper=(1, 1), bevel=0.6)
    add_box(plate, (s[0] * 0.8, s[1] * 0.35, s[2] * 0.22), at=(0, -s[1] * 0.22, -s[2] * 0.12), taper=(1, 1.3), bevel=0.4)
    return {PLATE: plate}


PIECES = {
    "Head": head_visor,
    "Chest": chest_seal,
    "BackUnit": back_socket,
    "Waist": waist_band,
    "Side": side_plate,
    "Shoulder": shoulder_block,
    "UpperArm": limb(1.0, 0.85),
    "Forearm": limb(0.85, 1.0),
    "Hand": hand_three_finger,
    "Thigh": limb(1.0, 0.8),
    "Knee": knee_cap,
    "Shin": limb(0.9, 0.75),
    "Foot": boot_tall,
}
SWAP = {"slot": "Shoulder", "a": shoulder_block, "b": shoulder_swept}


# --- building -----------------------------------------------------------------------------------------------------


def slot_kind(name):
    return name[:-1] if name[-1] in "LR" and name[:-1] in PIECES else name


def to_mesh(name, bm, mirror):
    if mirror:
        bmesh.ops.scale(bm, vec=Vector((-1, 1, 1)), verts=bm.verts)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return mesh


def make_parts(slot, builder):
    """One mesh per colour for a slot: {colour: mesh}."""
    mirror = slot["name"].endswith("R") and slot_kind(slot["name"]) != slot["name"]
    return {c: to_mesh(f"{slot['name']}_{c}", bm, mirror) for c, bm in builder(slot["size"]).items()}


def tris(mesh):
    return sum(len(p.vertices) - 2 for p in mesh.polygons)


def fit(mesh, size):
    """How far (studs) the piece pokes outside its slot box; 0 when it fits."""
    worst = 0.0
    for v in mesh.vertices:
        for axis in range(3):
            worst = max(worst, abs(v.co[axis]) - size[axis] / 2)
    return round(worst, 2)


def build_pieces(slots, pos, arm, ink):
    """Every slot's piece as parts on the rig: (parts, [(slot, part)] for the swap slot, report rows, materials)."""
    mats = {c: cel.cel_material(c, rig.hex_colour(c)) for c in (PLATE, TRIM, GLOW)}
    rows, swap_objs, parts = [], [], []
    for slot in slots:
        kind = slot_kind(slot["name"])
        for colour, mesh in make_parts(slot, PIECES[kind]).items():
            obj = bpy.data.objects.new(f"{slot['name']}_{colour}", mesh)
            bpy.context.scene.collection.objects.link(obj)
            cel.dress(obj, mats[colour], ink)
            rig.attach(obj, arm, slot["joint"], rig.slot_matrix(slot, pos))
            parts.append(obj)
            if kind == SWAP["slot"]:
                swap_objs.append((slot, obj))
            rows.append((slot["name"], colour, tris(mesh), slot["tris"], fit(mesh, slot["size"])))
    return parts, swap_objs, rows, mats


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
    parts, swap_objs, rows, mats = build_pieces(slots, pos, arm, ink)
    pilot = rig.pilot_marker(ink)

    cam = cel.setup_render(out_dir)
    frame = parts + [pilot]
    cel.shoot(cam, "pieces_front", 0, frame, out_dir)
    cel.shoot(cam, "pieces_side", 90, frame, out_dir)
    cel.shoot(cam, "pieces_three_quarter", 35, frame, out_dir, pitch_deg=12)
    cel.shoot(cam, "swap_a", 35, frame, out_dir, pitch_deg=12)

    # the swap: same parts, same bone, same matrix; only the mesh changes
    swapped = []
    for slot, obj in swap_objs:
        new = make_parts(slot, SWAP["b"])[PLATE]
        obj.data = new
        cel.dress(obj, mats[PLATE], ink)
        obj.modifiers.remove(obj.modifiers[0])  # dress() added a second outline; keep one
        swapped.append((slot["name"], tris(new), slot["tris"], fit(new, slot["size"])))
    cel.shoot(cam, "swap_b", 35, frame, out_dir, pitch_deg=12)

    total = sum(r[2] for r in rows)
    with open(os.path.join(out_dir, "pieces.md"), "w") as f:
        f.write("# Frame placeholder pieces\n\n")
        f.write(f"Parts {len(parts)} (budget {data['partBudget']}). Triangles {total:,}, ")
        f.write(f"with outline hull {total * 2:,} (budget 60,000). Planned body {data['bodyTris']:,}.\n\n")
        f.write("| part | colour | tris | slot budget | pokes out of slot box (studs) |\n|---|---|---|---|---|\n")
        for name, colour, t, budget, out in rows:
            f.write(f"| {name} | #{colour} | {t:,} | {budget:,} | {out:g} |\n")
        f.write("\n## Swap test (shoulder variant B replaces A)\n\n| part | tris | slot budget | pokes out |\n|---|---|---|---|\n")
        for name, t, budget, out in swapped:
            f.write(f"| {name} | {t:,} | {budget:,} | {out:g} |\n")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "frame_pieces.blend"))
    worst = max(r[4] for r in rows)
    print("PIECES_DONE", len(parts), "parts", total, "tris", "worst fit", worst, "tolerance", FIT_TOLERANCE)


if __name__ == "__main__":
    main()
