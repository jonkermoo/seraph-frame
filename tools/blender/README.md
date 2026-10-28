# Blender tools

Headless Blender scripts for Frame models. Run each with
`blender -b --factory-startup --python tools/blender/<script>.py -- <args>`, always with absolute paths.
Outputs (renders, .blend files) go to a scratch folder outside the repo, never into git.

| Script | Does |
|---|---|
| `cel.py` | Shared preview look: two-tone toon colour, a 0.35-stud inverted-hull ink outline, orthographic shots. |
| `inspect_model.py <model> <out>` | Takes a model apart: triangles and size in studs per piece, budgets check, cel and exploded renders. |
| `build_frame_rig.py frame_rig.json <out>` | Builds the Frame template rig (armature + one block per slot) and renders the slot map and tables. |
| `build_frame_pieces.py frame_rig.json <out>` | Grey placeholder pieces snapped to every slot, a shoulder swap test, triangle/part/fit report. |
| `build_frame_base.py frame_rig.json <out>` | The unarmoured base body under the armour (one part per bone, flesh and sinew from a palette texture), a poke-through check with the placeholder pieces on, bare vs armoured renders. |

`frame_rig.json` is the Frame template: 15 joints and 22 armour slots at 140 studs. Each slot has the joint it
hangs from, its box (centre and size in studs), and a triangle budget. A piece is modelled in its slot's space
(origin at the box centre, +Z towards the joint, -Y the front), left side only; the right side is mirrored.
Budgets: about 25k body triangles (doubled by the outline, 60k cap) and at most 30 parts. Each part has one colour.

The base body is one rigid part per bone (15). Its two tones come from a 2x1 palette texture: each face's UVs sit on
one pixel, so a part needs only one MeshPart. Wherever an armour piece covers it, the base must stay inside the piece.
