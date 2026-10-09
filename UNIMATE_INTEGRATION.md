# UniMate Integration for Ashfall Rifleman

## Complete Workflow

### 1. Preprocess & Generate Animations (Linux via GitHub Actions)

```bash
# Trigger workflow manually or push to main
gh workflow run unimate-preprocess.yml \
  -f asset=assets/characters/raw/rifleman/rifleman_rigged.glb \
  -f output_name=rifleman
```

**Outputs (artifacts):**
- `unimate-rifleman-preprocessed/` → `cond.npy`, `rifleman.glb`, `annotation.json`
- `unimate-rifleman-animations/` → Generated `.glb`/`.fbx` per prompt
- `unimate-rifleman-godot-import/` → Ready-to-import package with manifest

### 2. Import into Godot

```bash
# After downloading artifacts, run:
godot --headless -s tools/import_unimate_anims.gd -- \
  --input-dir unimate-rifleman-animations \
  --output-dir assets/characters/animations/rifleman
```

**Result:** `assets/characters/animations/rifleman/` contains:
```
shoot_00.gltf
shoot_01.gltf
shoot_02.gltf
reload_00.gltf
reload_01.gltf
reload_02.gltf
dodge_00.gltf    # left
dodge_01.gltf    # right
melee_00.gltf
melee_01.gltf
melee_02.gltf
aim_00.gltf
idle_01.gltf     # armed idle
ANIMATION_MANIFEST.json
```

### 3. Add to AnimationPlayer

In Godot Editor:
1. Open `scenes/characters/rifleman.tscn`
2. Select `AnimationPlayer`
3. Click "Animation" → "Load" → select each `.gltf`
4. Rename to match manifest (shoot_00, reload_00, etc.)
5. Set **Loop** = false for actions, true for idle/aim

### 4. Integrate Code

**Option A: Merge patch** (apply `tools/rifleman_unimate_patch.md` to `rifleman.gd`)

**Option B: Attach as child node**
1. Add `UniMateAnimations` as child of `Rifleman` in scene
2. Call integration methods from existing functions

### 5. Animation Mapping

| Gameplay Action | UniMate Prompt | Animation Clip | Duration | Integration |
|----------------|----------------|----------------|----------|-------------|
| Fire | "An object shoots a rifle." | `shoot_00` | ~0.5s | `fire()` → `on_fire()` |
| Reload | "An object reloads a rifle." | `reload_00` | ~1.2s | `reload()` → `on_reload()` |
| Dodge | "An object dodges left/right." | `dodge_00`/`dodge_01` | ~0.4s | `begin_dodge()` → `play_dodge()` |
| Melee | "An object performs a melee attack." | `melee_00` | ~0.6s | `melee()` → `on_melee()` |
| Aim | "An object aims down sights." | `aim_00` | ~0.2s | `aim_layer` blend |
| Armed Idle | "An object idles with weapon ready." | `idle_01` | loop | `weapon_layer` blend |

### 6. Optional: Retarget to rifleman_v2.glb

If you prefer the v2 mesh appearance:

```bash
# In Blender (run once):
blender -b -P tools/rig_rifleman_v2.py -- \
  --input assets/characters/raw/rifleman/rifleman_v2.glb \
  --reference assets/characters/raw/rifleman/rifleman_rigged.glb \
  --output assets/characters/raw/rifleman/rifleman_v2_rigged.glb
```

Then in Godot:
1. Replace `MODEL` preload in `rifleman.gd` with `rifleman_v2_rigged.glb`
2. Re-import animations (they'll retarget automatically if bone names match)
3. Adjust bone filters in `WEAPON_UPPER_BONES` if Rigify names differ

---

## Prompt Engineering Tips

For better results, iterate on prompts:

```bash
# Shooting variations
"An object fires a rifle from the shoulder."
"An object shoots a rifle while standing."
"An object fires a weapon with recoil."

# Reload variations
"An object reloads a rifle with a magazine."
"An object ejects a magazine and inserts a fresh one."

# Dodge variations
"An object dodges to the left."
"An object performs a combat roll to the right."
"An object sidesteps quickly."

# Melee variations
"An object strikes with a rifle butt."
"An object performs a melee attack with a gun."
```

Use `--cfg_scale 5-7` for stronger prompt adherence, `--num_repetitions 5` for variety.

---

## Files Created

| File | Purpose |
|------|---------|
| `.github/workflows/unimate-preprocess.yml` | CI pipeline for preprocessing + generation |
| `tools/rig_rifleman_v2.py` | Auto-rig v2 mesh with Rigify |
| `tools/import_unimate_anims.gd` | Import generated animations to Godot |
| `scripts/player/unimate_animations.gd` | Animation integration layer |
| `tools/rifleman_unimate_patch.md` | Patch for rifleman.gd |

---

## Next Steps

1. **Push to GitHub** and run the workflow
2. **Download artifacts** and run import script
3. **Apply patch** or attach `UniMateAnimations` node
4. **Test in-game** and adjust durations/blend times
5. **Iterate prompts** for better animation quality