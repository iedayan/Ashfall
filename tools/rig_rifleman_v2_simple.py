#!/usr/bin/env blender -b -P
"""
Auto-rig rifleman_v2.glb with a SIMPLE rig matching rifleman_rigged.glb bone structure (27 bones).
Run: blender -b -P tools/rig_rifleman_v2_simple.py -- --output assets/characters/raw/rifleman/rifleman_v2_rigged.glb
"""

import sys
import argparse

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    argv = []

parser = argparse.ArgumentParser()
parser.add_argument("--input", default="assets/characters/raw/rifleman/rifleman_v2.glb")
parser.add_argument("--reference", default="assets/characters/raw/rifleman/rifleman_rigged.glb")
parser.add_argument("--output", default="assets/characters/raw/rifleman/rifleman_v2_rigged.glb")
args = parser.parse_args(argv)

import bpy
from mathutils import Vector

# --- Setup ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete()

# Import reference to get bone structure
print(f"Importing reference: {args.reference}")
if args.reference.endswith('.fbx'):
    bpy.ops.import_scene.fbx(filepath=args.reference)
else:
    bpy.ops.import_scene.gltf(filepath=args.reference)

ref_armature = None
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        ref_armature = obj
        ref_armature.name = "ReferenceRig"
        break

if not ref_armature:
    print("ERROR: No armature found in reference")
    sys.exit(1)

# Get reference bone hierarchy
bpy.context.view_layer.objects.active = ref_armature
bpy.ops.object.mode_set(mode='EDIT')
ref_bones = {}
for b in ref_armature.data.edit_bones:
    ref_bones[b.name] = {
        'head': b.head.copy(),
        'tail': b.tail.copy(),
        'roll': b.roll,
        'parent': b.parent.name if b.parent else None,
        'children': [c.name for c in b.children],
    }
print(f"Reference bones ({len(ref_bones)}): {list(ref_bones.keys())}")
bpy.ops.object.mode_set(mode='OBJECT')

# Import target mesh
print(f"Importing target: {args.input}")
bpy.ops.object.select_all(action='DESELECT')
if args.input.endswith('.fbx'):
    bpy.ops.import_scene.fbx(filepath=args.input)
else:
    bpy.ops.import_scene.gltf(filepath=args.input)

target_mesh = None
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        target_mesh = obj
        target_mesh.name = "RiflemanV2_Mesh"
        break

if not target_mesh:
    print("ERROR: No mesh found in target")
    sys.exit(1)

# Get mesh bounds for positioning
mesh_bounds = [target_mesh.matrix_world @ Vector(c) for c in target_mesh.bound_box]
min_z = min(v.z for v in mesh_bounds)
max_z = max(v.z for v in mesh_bounds)
height = max_z - min_z

# --- Create Simple Armature matching reference exactly ---
print("Creating simple armature...")
bpy.ops.object.armature_add(enter_editmode=False)
armature = bpy.context.active_object
armature.name = "RiflemanV2_Rig"
armature.location = (0, 0, min_z)
bpy.ops.object.transform_apply(location=True)

bpy.ops.object.mode_set(mode='EDIT')

# Create bones matching reference structure
for bone_name, data in ref_bones.items():
    if bone_name not in armature.data.edit_bones:
        b = armature.data.edit_bones.new(bone_name)
    else:
        b = armature.data.edit_bones[bone_name]
    b.head = data['head']
    b.tail = data['tail']
    b.roll = data['roll']

# Set parent relationships
for bone_name, data in ref_bones.items():
    b = armature.data.edit_bones[bone_name]
    if data['parent'] and data['parent'] in armature.data.edit_bones:
        b.parent = armature.data.edit_bones[data['parent']]
    b.use_connect = False

bpy.ops.object.mode_set(mode='OBJECT')

# --- Scale armature to match mesh height ---
# The reference is ~1.7m tall, scale to match mesh
ref_height = max_z - min_z  # approximate
scale_factor = height / 1.7  # assume reference is 1.7 units tall
armature.scale = (scale_factor, scale_factor, scale_factor)
bpy.ops.object.transform_apply(scale=True)

# Reposition to sit on ground
bpy.ops.object.mode_set(mode='EDIT')
for b in armature.data.edit_bones:
    b.head.z -= min_z
    b.tail.z -= min_z
bpy.ops.object.mode_set(mode='OBJECT')

# --- Parent mesh to rig with automatic weights ---
print("Parenting mesh to rig...")
bpy.ops.object.select_all(action='DESELECT')
target_mesh.select_set(True)
armature.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.parent_set(type='ARMATURE_AUTO')

# --- Clean up reference ---
bpy.data.objects.remove(ref_armature, do_unlink=True)

# --- Export ---
print(f"Exporting to: {args.output}")
bpy.ops.object.select_all(action='DESELECT')
armature.select_set(True)
target_mesh.select_set(True)
bpy.context.view_layer.objects.active = armature

if args.output.endswith('.fbx'):
    bpy.ops.export_scene.fbx(
        filepath=args.output,
        use_selection=True,
        add_leaf_bones=False,
        bake_anim=False,
        armature_nodetype='ROOT'
    )
else:
    bpy.ops.export_scene.gltf(
        filepath=args.output,
        export_format='GLB',
        use_selection=True,
        export_skins=True,
        export_morph=False,
        export_animations=False,
    )

print("Done!")