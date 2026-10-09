#!/usr/bin/env godot --headless -s
"""
Import UniMate-generated animations into Godot project.
Run: godot --headless -s tools/import_unimate_anims.gd -- --input-dir outputs/samples/rifleman --output-dir assets/characters/animations/rifleman
"""

import sys
import os
import json
import shutil
import argparse
from pathlib import Path

# Parse args
argv = sys.argv[1:]
if "--" in argv:
    argv = argv[argv.index("--") + 1:]

parser = argparse.ArgumentParser()
parser.add_argument("--input-dir", required=True)
parser.add_argument("--output-dir", required=True)
parser.add_argument("--manifest", help="ANIMATION_MANIFEST.json from workflow")
args = parser.parse_args(argv)

input_dir = Path(args.input_dir)
output_dir = Path(args.output_dir)
output_dir.mkdir(parents=True, exist_ok=True)

# Expected animation mappings from UniMate prompts
ANIM_MAP = {
    "shoot": ["shoot", "fire", "rifle"],
    "reload": ["reload"],
    "dodge": ["dodge", "evade"],
    "melee": ["melee", "attack", "strike"],
    "aim": ["aim", "ads", "sights"],
    "idle": ["idle", "ready"],
}

def match_animation(filename: str) -> str:
    """Match filename to animation type."""
    name = filename.lower().replace('_', ' ').replace('-', ' ')
    for anim_type, keywords in ANIM_MAP.items():
        if any(k in name for k in keywords):
            return anim_type
    return "unknown"

# Find all generated GLB/FBX files
anim_files = list(input_dir.rglob("*.glb")) + list(input_dir.rglob("*.fbx"))
print(f"Found {len(anim_files)} animation files")

imported = []
for f in anim_files:
    anim_type = match_animation(f.name)
    if anim_type == "unknown":
        print(f"  Skipping {f.name} (no match)")
        continue
    
    # Create unique name with repetition index
    base_name = f"{anim_type}"
    existing = [i for i in imported if i.startswith(base_name)]
    idx = len(existing)
    target_name = f"{base_name}_{idx:02d}{f.suffix}"
    target_path = output_dir / target_name
    
    shutil.copy2(f, target_path)
    imported.append(target_name)
    print(f"  {f.name} -> {target_name} ({anim_type})")

# Generate manifest
manifest = {
    "source": "UniMate",
    "asset": "rifleman",
    "animations": []
}
for name in imported:
    anim_type = name.split('_')[0]
    manifest["animations"].append({
        "file": name,
        "type": anim_type,
        "loop": anim_type in ["idle", "aim"],
        "speed": 1.0,
    })

manifest_path = output_dir / "ANIMATION_MANIFEST.json"
with open(manifest_path, 'w') as f:
    json.dump(manifest, f, indent=2)

print(f"\nImported {len(imported)} animations to {output_dir}")
print(f"Manifest written to {manifest_path}")