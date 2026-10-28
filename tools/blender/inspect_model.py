"""Take a model apart: per-piece triangle counts, sizes in studs, an exploded view and cel previews.

Run headless:
    blender -b --factory-startup --python tools/blender/inspect_model.py -- <model> <out_dir> [--height 140]

<model> may be .blend, .fbx, .glb/.gltf or .obj. Every mesh is baked to world space (modifiers and
armature poses applied) so pieces can be measured and pulled apart. A model made of only a few meshes is
also split into loose parts. The model is scaled so its height is --height studs (1 Blender unit = 1 stud).

Writes to <out_dir>: report.json, report.md, front/side/back/three_quarter/exploded .png and inspected.blend.
"""

import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cel  # noqa: E402

TRI_LIMIT = 20000  # Roblox per-mesh limit
TRI_TARGET = 6000  # per-mesh target
FRAME_TRIS = 60000  # own Frame rig budget
FRAME_PARTS = 30


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if len(argv) < 2:
        raise SystemExit("usage: -- <model> <out_dir> [--height 140]")
    height = 140.0
    if "--height" in argv:
        height = float(argv[argv.index("--height") + 1])
    return os.path.abspath(argv[0]), os.path.abspath(argv[1]), height


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def import_model(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.objects = list(src.objects)
        for obj in dst.objects:
            if obj is not None:
                bpy.context.scene.collection.objects.link(obj)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise SystemExit("unsupported file type " + ext)


def base_colour(mat):
    if mat is None:
        return (0.6, 0.6, 0.62, 1.0)
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                return tuple(node.inputs["Base Color"].default_value)
    return tuple(mat.diffuse_color)


def bake_meshes():
    """Replace every mesh object with a world-space copy of its evaluated mesh (no parent, no modifiers)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    baked = []
    originals = list(bpy.data.objects)
    for obj in [o for o in originals if o.type == "MESH" and o.visible_get()]:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        mesh.transform(obj.matrix_world)
        new = bpy.data.objects.new(obj.name, mesh)
        new["source_parent"] = obj.parent.name if obj.parent else ""
        new["source_bone"] = obj.parent_bone or ""
        baked.append(new)
    bones = []
    for arm in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
        bones += [{"armature": arm.name, "bone": b.name, "parent": b.parent.name if b.parent else ""} for b in arm.data.bones]
    for obj in originals:
        bpy.data.objects.remove(obj, do_unlink=True)
    for obj in baked:
        bpy.context.scene.collection.objects.link(obj)
    return baked, bones


def split_loose(objs):
    out = []
    for obj in objs:
        bpy.context.view_layer.objects.active = obj
        for o in bpy.context.view_layer.objects:
            o.select_set(o == obj)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="LOOSE")
        bpy.ops.object.mode_set(mode="OBJECT")
        out += [o for o in bpy.context.selected_objects]
    return out


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def bounds(objs):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for obj in objs:
        for v in obj.data.vertices:
            lo = Vector(map(min, lo, v.co))
            hi = Vector(map(max, hi, v.co))
    return lo, hi


def normalise(objs, height):
    lo, hi = bounds(objs)
    k = height / max(hi.z - lo.z, 1e-6)
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    m = Matrix.Scale(k, 4) @ Matrix.Translation(-centre)
    for obj in objs:
        obj.data.transform(m)
    return k, hi - lo


def origin_to_centre(obj):
    lo, hi = bounds([obj])
    c = (lo + hi) / 2
    obj.data.transform(Matrix.Translation(-c))
    obj.location = c


def apply_cel(objs, source_colours):
    ink = cel.ink_material()
    cache = {}
    for obj in objs:
        colour = source_colours.get(obj.name, (0.6, 0.6, 0.62, 1.0))
        key = tuple(round(c, 3) for c in colour)
        if key not in cache:
            cache[key] = cel.cel_material(str(len(cache)), colour)
        cel.dress(obj, cache[key], ink)


def main():
    model, out_dir, height = parse_args()
    os.makedirs(out_dir, exist_ok=True)
    clear_scene()
    import_model(model)
    source_meshes = len([o for o in bpy.data.objects if o.type == "MESH"])
    objs, bones = bake_meshes()
    colours_by_name = {}
    for obj in objs:
        mats = [m for m in obj.data.materials if m is not None]
        colours_by_name[obj.name] = base_colour(mats[0] if mats else None)
    material_names = {o.name: [m.name for m in o.data.materials if m] for o in objs}
    split = False
    if len(objs) < 5:
        objs = split_loose(objs)
        split = True
        for obj in objs:
            stem = obj.name.split(".")[0]
            colours_by_name.setdefault(obj.name, colours_by_name.get(stem, (0.6, 0.6, 0.62, 1.0)))
            material_names.setdefault(obj.name, material_names.get(stem, []))
    k, src_size = normalise(objs, height)
    for obj in objs:
        origin_to_centre(obj)

    pieces = []
    for obj in objs:
        lo, hi = bounds([obj])
        size = hi - lo
        pieces.append(
            {
                "name": obj.name,
                "tris": tris(obj),
                "size_studs": [round(size.x, 2), round(size.y, 2), round(size.z, 2)],
                "centre_studs": [round(c, 2) for c in obj.location],
                "materials": material_names.get(obj.name, []),
                "source_parent": obj.get("source_parent", ""),
                "source_bone": obj.get("source_bone", ""),
                "over_limit": tris(obj) > TRI_LIMIT,
            }
        )
    pieces.sort(key=lambda p: -p["tris"])
    total = sum(p["tris"] for p in pieces)
    report = {
        "model": model,
        "source_meshes": source_meshes,
        "split_into_loose_parts": split,
        "pieces": len(pieces),
        "total_tris": total,
        "total_tris_with_outline_hull": total * 2,
        "source_size_units": [round(c, 4) for c in src_size],
        "scale_to_studs": round(k, 4),
        "height_studs": height,
        "bones": bones,
        "budget": {
            "frame_tris": FRAME_TRIS,
            "frame_parts": FRAME_PARTS,
            "mesh_limit": TRI_LIMIT,
            "mesh_target": TRI_TARGET,
            "fits_tris": total <= FRAME_TRIS,
            "fits_parts": len(pieces) <= FRAME_PARTS,
            "meshes_over_limit": sum(p["over_limit"] for p in pieces),
            "decimate_ratio_for_25k_body": round(min(1.0, 25000 / max(total, 1)), 3),
        },
        "piece_list": pieces,
    }
    with open(os.path.join(out_dir, "report.json"), "w") as f:
        json.dump(report, f, indent=2)
    with open(os.path.join(out_dir, "report.md"), "w") as f:
        f.write(f"# {os.path.basename(model)}\n\n")
        f.write(f"- source meshes {source_meshes}, pieces {len(pieces)} (split loose: {split})\n")
        f.write(f"- total tris {total:,} (x2 with outline hull = {total * 2:,})\n")
        f.write(f"- scaled x{k:.3f} to {height} studs; bones {len(bones)}\n\n")
        f.write("| piece | tris | size (studs) | materials |\n|---|---|---|---|\n")
        for p in pieces:
            flag = " **>20k**" if p["over_limit"] else ""
            f.write(f"| {p['name']} | {p['tris']:,}{flag} | {p['size_studs']} | {', '.join(p['materials'])} |\n")

    apply_cel(objs, colours_by_name)
    cam = cel.setup_render(out_dir)
    cel.shoot(cam, "front", 0, objs, out_dir)
    cel.shoot(cam, "side", 90, objs, out_dir)
    cel.shoot(cam, "back", 180, objs, out_dir)
    cel.shoot(cam, "three_quarter", 35, objs, out_dir, pitch_deg=12)
    centre = (lambda lo, hi: (lo + hi) / 2)(*cel.bounds_world(objs))
    for obj in objs:
        obj.location = centre + (obj.location - centre) * 1.8
    cel.shoot(cam, "exploded", 35, objs, out_dir, pitch_deg=12)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "inspected.blend"))
    print("INSPECT_DONE", json.dumps({k2: report[k2] for k2 in ("pieces", "total_tris", "scale_to_studs")}))


main()
