extends Node
# UniMate Animation Integration for Rifleman
# Attach as child of Rifleman node, or merge into rifleman.gd

class_name UniMateAnimations

# Animation names (from ANIMATION_MANIFEST.json)
const UNIMATE_ANIMS := {
	"shoot": "shoot_00",
	"reload": "reload_00",
	"dodge_left": "dodge_00",
	"dodge_right": "dodge_01",
	"melee": "melee_00",
	"aim": "aim_00",
	"idle_armed": "idle_01",
}

# State durations (adjust based on actual clip lengths)
const DURATIONS := {
	"shoot": 0.5,
	"reload": 1.2,
	"dodge": 0.4,
	"melee": 0.6,
	"aim": 0.2,
	"idle_armed": 0.0,
}

# Upper body bones for filtering (must match rifleman.gd WEAPON_UPPER_BONES)
const WEAPON_UPPER_BONES := {
	"spine": true, "chest": true, "neck": true, "head": true, "weapon": true,
	"hand_ik.L": true, "hand_ik.R": true, "elbow_pole.L": true, "elbow_pole.R": true,
	"cloak.L": true, "cloak.R": true, "shoulder.L": true, "shoulder.R": true,
	"upper_arm.L": true, "upper_arm.R": true, "forearm.L": true, "forearm.R": true,
	"hand.L": true, "hand.R": true,
}

var rifleman: Node
var anim_player: AnimationPlayer
var anim_tree: AnimationTree

func _ready() -> void:
	rifleman = get_parent()
	anim_player = rifleman.get_node_or_null("AnimationPlayer")
	anim_tree = rifleman.get_node_or_null("AnimationTree")
	
	if not anim_player:
		push_error("UniMateAnimations: No AnimationPlayer found on parent")
	if not anim_tree:
		push_warning("UniMateAnimations: No AnimationTree found on parent")

func has_animation(name: String) -> bool:
	return anim_player and anim_player.has_animation(name)

# --- Public API ---

func play_shoot(counter: bool = false) -> float:
	"""Play shoot animation. Returns duration."""
	if not _ensure_anim("shoot"):
		return 0.13
	var clip = UNIMATE_ANIMS["shoot"]
	if counter and has_animation("shoot_counter"):
		clip = "shoot_counter"
	anim_player.play(clip)
	anim_player.seek(0, true)
	return DURATIONS["shoot"]

func play_reload() -> float:
	"""Play reload animation. Returns duration."""
	if not _ensure_anim("reload"):
		return 0.83
	anim_player.play(UNIMATE_ANIMS["reload"])
	anim_player.seek(0, true)
	return DURATIONS["reload"]

func play_dodge(direction: Vector3 = Vector3.FORWARD) -> float:
	"""Play dodge animation based on direction."""
	if not _ensure_anim("dodge"):
		return 0.36
	
	# Pick left/right dodge based on movement direction relative to facing
	var clip = UNIMATE_ANIMS["dodge_left"]
	if direction.dot(rifleman.global_basis.x) > 0:
		clip = UNIMATE_ANIMS["dodge_right"]
	
	anim_player.play(clip)
	anim_player.seek(0, true)
	return DURATIONS["dodge"]

func play_melee() -> float:
	"""Play melee attack animation."""
	if not _ensure_anim("melee"):
		return 0.57
	anim_player.play(UNIMATE_ANIMS["melee"])
	anim_player.seek(0, true)
	return DURATIONS["melee"]

func set_aim_layer(enabled: bool) -> void:
	"""Enable/disable aim upper-body layer."""
	if anim_tree and anim_tree.has_node("parameters/aim_layer/blend_amount"):
		anim_tree.set("parameters/aim_layer/blend_amount", 1.0 if enabled else 0.0)

func set_armed_idle(enabled: bool) -> void:
	"""Switch to armed idle (weapon ready) vs unarmed idle."""
	if anim_tree and anim_tree.has_node("parameters/weapon_layer/blend_amount"):
		anim_tree.set("parameters/weapon_layer/blend_amount", 1.0 if enabled else 0.0)

# --- AnimationTree Integration ---

func setup_animation_tree() -> void:
	"""Add UniMate animation nodes to existing AnimationTree.
	   Call this from rifleman.gd _ready() after setup_directional_blend()."""
	if not anim_tree or not anim_tree.tree_root:
		return
	
	var graph = anim_tree.tree_root
	
	# --- Shoot layer (one-shot, high priority) ---
	if has_animation(UNIMATE_ANIMS["shoot"]):
		var shoot_clip = AnimationNodeAnimation.new()
		shoot_clip.animation = UNIMATE_ANIMS["shoot"]
		graph.add_node("unimate_shoot", shoot_clip)
		
		var shoot_seek = AnimationNodeTimeSeek.new()
		graph.add_node("unimate_shoot_seek", shoot_seek)
		graph.connect_node("unimate_shoot_seek", 0, "unimate_shoot")
		
		var shoot_layer = AnimationNodeBlend2.new()
		shoot_layer.filter_enabled = true
		# Filter to upper body bones (same as fire_layer)
		_filter_upper_body(shoot_layer)
		graph.add_node("unimate_shoot_layer", shoot_layer)
		graph.connect_node("unimate_shoot_layer", 0, "fire_layer")  # After fire
		graph.connect_node("unimate_shoot_layer", 1, "unimate_shoot_seek")
		
		# Parameter for blending
		anim_tree.set("parameters/unimate_shoot_layer/blend_amount", 0.0)
	
	# --- Reload layer ---
	if has_animation(UNIMATE_ANIMS["reload"]):
		var reload_clip = AnimationNodeAnimation.new()
		reload_clip.animation = UNIMATE_ANIMS["reload"]
		graph.add_node("unimate_reload", reload_clip)
		
		var reload_seek = AnimationNodeTimeSeek.new()
		graph.add_node("unimate_reload_seek", reload_seek)
		graph.connect_node("unimate_reload_seek", 0, "unimate_reload")
		
		var reload_layer = AnimationNodeBlend2.new()
		reload_layer.filter_enabled = true
		_filter_upper_body(reload_layer)
		graph.add_node("unimate_reload_layer", reload_layer)
		graph.connect_node("unimate_reload_layer", 0, "reload_layer")
		graph.connect_node("unimate_reload_layer", 1, "unimate_reload_seek")
		
		anim_tree.set("parameters/unimate_reload_layer/blend_amount", 0.0)
	
	# --- Melee layer ---
	if has_animation(UNIMATE_ANIMS["melee"]):
		var melee_clip = AnimationNodeAnimation.new()
		melee_clip.animation = UNIMATE_ANIMS["melee"]
		graph.add_node("unimate_melee", melee_clip)
		
		var melee_seek = AnimationNodeTimeSeek.new()
		graph.add_node("unimate_melee_seek", melee_seek)
		graph.connect_node("unimate_melee_seek", 0, "unimate_melee")
		
		var melee_layer = AnimationNodeBlend2.new()
		melee_layer.filter_enabled = true
		_filter_upper_body(melee_layer)
		graph.add_node("unimate_melee_layer", melee_layer)
		graph.connect_node("unimate_melee_layer", 0, "melee_layer")
		graph.connect_node("unimate_melee_layer", 1, "unimate_melee_seek")
		
		anim_tree.set("parameters/unimate_melee_layer/blend_amount", 0.0)
	
	# --- Aim layer (additive upper body) ---
	if has_animation(UNIMATE_ANIMS["aim"]):
		var aim_clip = AnimationNodeAnimation.new()
		aim_clip.animation = UNIMATE_ANIMS["aim"]
		graph.add_node("unimate_aim", aim_clip)
		
		var aim_layer = AnimationNodeBlend2.new()
		aim_layer.filter_enabled = true
		_filter_upper_body(aim_layer)
		graph.add_node("unimate_aim_layer", aim_layer)
		graph.connect_node("unimate_aim_layer", 0, "aim_layer")
		graph.connect_node("unimate_aim_layer", 1, "unimate_aim")
		
		anim_tree.set("parameters/unimate_aim_layer/blend_amount", 0.0)
	
	# --- Armed idle (replaces sheathed_idle when weapon drawn) ---
	if has_animation(UNIMATE_ANIMS["idle_armed"]):
		var armed_idle_clip = AnimationNodeAnimation.new()
		armed_idle_clip.animation = UNIMATE_ANIMS["idle_armed"]
		armed_idle_clip.loop_mode = Animation.LOOP_LINEAR
		graph.add_node("unimate_armed_idle", armed_idle_clip)
		
		var armed_idle_layer = AnimationNodeBlend2.new()
		armed_idle_layer.filter_enabled = true
		_filter_upper_body(armed_idle_layer)
		graph.add_node("unimate_armed_idle_layer", armed_idle_layer)
		graph.connect_node("unimate_armed_idle_layer", 0, "weapon_pose")
		graph.connect_node("unimate_armed_idle_layer", 1, "unimate_armed_idle")
		
		anim_tree.set("parameters/unimate_armed_idle_layer/blend_amount", 0.0)

func _filter_upper_body(layer: AnimationNodeBlend2) -> void:
	"""Filter animation to weapon upper body bones."""
	if not anim_player:
		return
	var anim = anim_player.get_animation(layer.get_connected_node(1).get_animation())
	for track in range(anim.get_track_count()):
		var path = anim.track_get_path(track)
		if path.get_subname_count() > 0 and WEAPON_UPPER_BONES.has(String(path.get_subname(0))):
			layer.set_filter_path(path, true)

func _ensure_anim(key: String) -> bool:
	if not has_animation(UNIMATE_ANIMS[key]):
		push_warning("UniMate animation '%s' not found" % UNIMATE_ANIMS[key])
		return false
	return true

# --- Integration hooks for rifleman.gd ---

func on_fire(counter: bool = false) -> float:
	"""Call from rifleman.fire(). Returns animation duration."""
	# Trigger shoot layer blend
	if anim_tree and anim_tree.has_node("parameters/unimate_shoot_layer/blend_amount"):
		anim_tree.set("parameters/unimate_shoot_layer/blend_amount", 1.0)
		call_deferred("_reset_shoot_layer")
	return play_shoot(counter)

func _reset_shoot_layer() -> void:
	if anim_tree and anim_tree.has_node("parameters/unimate_shoot_layer/blend_amount"):
		await get_tree().create_timer(0.1).timeout
		anim_tree.set("parameters/unimate_shoot_layer/blend_amount", 0.0)

func on_reload() -> float:
	"""Call from rifleman.reload()."""
	if anim_tree and anim_tree.has_node("parameters/unimate_reload_layer/blend_amount"):
		anim_tree.set("parameters/unimate_reload_layer/blend_amount", 1.0)
		call_deferred("_reset_reload_layer")
	return play_reload()

func _reset_reload_layer() -> void:
	if anim_tree and anim_tree.has_node("parameters/unimate_reload_layer/blend_amount"):
		await get_tree().create_timer(1.2).timeout
		anim_tree.set("parameters/unimate_reload_layer/blend_amount", 0.0)

func on_melee() -> float:
	"""Call from rifleman.melee()."""
	if anim_tree and anim_tree.has_node("parameters/unimate_melee_layer/blend_amount"):
		anim_tree.set("parameters/unimate_melee_layer/blend_amount", 1.0)
		call_deferred("_reset_melee_layer")
	return play_melee()

func _reset_melee_layer() -> void:
	if anim_tree and anim_tree.has_node("parameters/unimate_melee_layer/blend_amount"):
		await get_tree().create_timer(0.6).timeout
		anim_tree.set("parameters/unimate_melee_layer/blend_amount", 0.0)

func on_weapon_state_changed(state: String) -> void:
	"""Call from rifleman.set_weapon_state()."""
	if state == "ready":
		set_armed_idle(true)
		set_aim_layer(true)
	elif state == "sheathed":
		set_armed_idle(false)
		set_aim_layer(false)