"""Shared cel look for preview renders: two-tone toon colour, a baked inverted-hull ink outline, orthographic shots."""

import math
import os

import bpy
from mathutils import Vector

OUTLINE_STUDS = 0.35  # inverted-hull thickness for a 140-stud Frame (art doc 1.2)
INK = (0.04, 0.035, 0.05, 1.0)


def cel_material(name, colour):
    """Two-tone toon: lit colour or a hard shadow shade, emitted so lighting can't add gradients."""
    mat = bpy.data.materials.new("cel_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    diffuse = nt.nodes.new("ShaderNodeBsdfDiffuse")
    to_rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = (colour[0] * 0.55, colour[1] * 0.55, colour[2] * 0.62, 1.0)
    ramp.color_ramp.elements[1].position = 0.5
    ramp.color_ramp.elements[1].color = colour
    emit = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(diffuse.outputs[0], to_rgb.inputs[0])
    nt.links.new(to_rgb.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], emit.inputs[0])
    nt.links.new(emit.outputs[0], out.inputs[0])
    return mat


def ink_material():
    mat = bpy.data.materials.new("ink")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs[0].default_value = INK
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs[0], out.inputs[0])
    mat.use_backface_culling = True
    mat.use_backface_culling_shadow = True  # the hull wraps the body; it must not shade it
    return mat


def dress(obj, mat, ink):
    """Give a mesh its cel colour plus the outline hull (a flipped Solidify shell in ink)."""
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    obj.data.materials.append(ink)
    hull = obj.modifiers.new("outline", "SOLIDIFY")
    hull.thickness = OUTLINE_STUDS
    hull.offset = 1.0
    hull.use_flip_normals = True
    hull.use_rim = False
    hull.material_offset = 1
    for p in obj.data.polygons:
        p.use_smooth = False


def setup_render(out_dir):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = 900
    scene.render.resolution_y = 1200
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    # paper-coloured backdrop for the camera, but only dim fill light so the sun decides the toon step
    nt = world.node_tree
    paper = nt.nodes["Background"]
    paper.inputs[0].default_value = (0.93, 0.91, 0.86, 1)
    fill = nt.nodes.new("ShaderNodeBackground")
    fill.inputs[0].default_value = (0.1, 0.1, 0.12, 1)
    mix = nt.nodes.new("ShaderNodeMixShader")
    path = nt.nodes.new("ShaderNodeLightPath")
    nt.links.new(path.outputs["Is Camera Ray"], mix.inputs[0])
    nt.links.new(fill.outputs[0], mix.inputs[1])
    nt.links.new(paper.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], nt.nodes["World Output"].inputs[0])
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 7
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def shoot(cam, name, yaw_deg, objs, out_dir, pitch_deg=8):
    bpy.context.view_layer.update()
    lo, hi = bounds_world(objs)
    centre = (lo + hi) / 2
    size = hi - lo
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    # yaw 0 looks at the front, which faces -Y (Roblox -Z)
    direction = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    dist = max(size) * 3
    cam.location = centre + direction * dist
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    cam.data.ortho_scale = max(size.z, size.x * 1.33, size.y * 1.33) * 1.1
    cam.data.clip_end = dist * 3
    bpy.context.scene.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)


def bounds_world(objs):
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for obj in objs:
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi
