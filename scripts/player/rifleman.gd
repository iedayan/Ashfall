extends CharacterBody3D
# Gameplay operator: the rigged rifleman GLB (built by tools/rig_rifleman.py) with
# directional locomotion, concept-aligned aim/action poses, reactions and a bone-attached rifle.
# Collision stays a simple capsule and animation never adds gameplay root motion.
const MODEL = preload("res://assets/characters/raw/rifleman/rifleman_rigged.glb")
const Kit = preload("res://scripts/vfx/visual_kit.gd")
const UniMateAnims = preload("res://scripts/player/unimate_animations.gd")
const SHEATH_DELAY := 8.0
const INSPECT_DELAY := 4.0
const HIT_DURATION := 0.30
const DEFAULT_DODGE_DURATION := 0.36
const RELOAD_DURATION := 0.83
const MELEE_DURATION := 0.57
const ABILITY_DURATION := 0.77
const LOCOMOTION_SMOOTHING := 14.0
const DIRECTION_SMOOTHING := 16.0
const FACING_SMOOTHING := 12.0
const FORWARD_REFERENCE_SPEED := 3.5
const BACKWARD_REFERENCE_SPEED := 2.5
const STRAFE_REFERENCE_SPEED := 2.8
const ANIMATION_SPEED_MIN := 0.8
const ANIMATION_SPEED_MAX := 1.2
const WEAPON_UPPER_BONES := {
	"spine": true, "chest": true, "neck": true, "head": true, "weapon": true,
	"hand_ik.L": true, "hand_ik.R": true, "elbow_pole.L": true, "elbow_pole.R": true,
	"cloak.L": true, "cloak.R": true, "shoulder.L": true, "shoulder.R": true,
	"upper_arm.L": true, "upper_arm.R": true, "forearm.L": true, "forearm.R": true,
	"hand.L": true, "hand.R": true,
}
var visual: Node3D
var model: Node3D
var anim: AnimationPlayer
var weapon: Node3D
var muzzle: OmniLight3D
var muzzle_fx: Node3D
var sound: AudioStreamPlayer3D
var unimate_anims: UniMateAnims
var clock = 0.0
var recoil = 0.0
var recoil_velocity := 0.0
var state = ""
var footwork
var muzzle_socket: Node3D
var flash_time := 0.0
var animation_tree: AnimationTree
var dodge_blend := 0.0
var hit_time := 0.0
var hit_elapsed := 0.0
var hit_direction := Vector3.BACK
var death_direction := Vector3.BACK
var dead := false
var locomotion_weights := Vector2.ZERO
var recoil_lateral := 0.0
var recoil_lateral_velocity := 0.0
var lunge := 0.0
var lunge_velocity := 0.0
var weapon_sway := 0.0
var banking_roll := 0.0
var banking_pitch := 0.0
var spin_time := 0.0
var inspect_time := 0.0
var idle_clock := 0.0
var inspect_triggered := false
var visual_yaw := 0.0
var facing_direction := Vector3.FORWARD
var movement_direction := Vector3.FORWARD
var smoothed_movement_direction := Vector3.FORWARD
var current_animation_speed := 1.0
var weapon_state := "ready"
var weapon_state_time := 0.0
var weapon_filter_paths: Array[NodePath] = []
var fire_filter_paths: Array[NodePath] = []
var aim_filter_paths: Array[NodePath] = []
var reload_filter_paths: Array[NodePath] = []
var melee_filter_paths: Array[NodePath] = []
var ability_filter_paths: Array[NodePath] = []
var target_aim := Vector3.FORWARD
var dodge_duration := DEFAULT_DODGE_DURATION
var dodge_elapsed := 0.0
var dodge_direction := Vector3.FORWARD
var dodge_started := false
var shot_time := 0.0
var fire_counter := false
var reload_time := 0.0
var melee_time := 0.0
var ability_time := 0.0
# The body moves on the physics tick (60 Hz) but the display refreshes faster. With
# smooth_motion, the visual is offset to the interpolated tick position every rendered frame
# and animation/foot IK run per frame, so stride, feet and muzzle stay in render space.
var smooth_motion := false
var tick_origins: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var frame_motion: Array[bool] = [false, false]
var animate_requested := false
var animate_live := false
var locomotion_start_weight := 0.0
var locomotion_stop_weight := 0.0
var locomotion_pivot_weight := 0.0
var locomotion_pivot_sign := 0.0
var was_traveling := false
var prior_travel_direction := Vector3.FORWARD

func _ready() -> void:
	var collision = CollisionShape3D.new()
	var bounds = CapsuleShape3D.new()
	bounds.radius = 0.35
	bounds.height = 1.6
	collision.shape = bounds
	collision.position.y = 0.8
	add_child(collision)
	visual = Node3D.new()
	add_child(visual)
	model = MODEL.instantiate()
	# The GLB faces +Z; gameplay forward is -Z.
	model.rotation.y = PI
	visual.add_child(model)
	# Put player on render layer 2 so the character rim light (cull mask 2) catches their edges.
	Kit.assign_layers(model, 2)
	anim = model.find_child("AnimationPlayer", true, false)
	for clip in ["idle", "aim", "run", "run_backward", "strafe_left", "strafe_right", "inspect", "sheathed_idle"]:
		if anim.has_animation(clip):
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim.play("idle")
	setup_directional_blend()
	# Initialize UniMate animations
	unimate_anims = UniMateAnims.new()
	unimate_anims.rifleman = self
	unimate_anims.anim_player = anim
	unimate_anims.anim_tree = animation_tree
	unimate_anims.setup_animation_tree()
	add_child(unimate_anims)
	var skeleton: Skeleton3D = model.find_child("Skeleton3D",true,false)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	footwork = preload("res://scripts/player/operator_footwork.gd").new()
	skeleton.add_child(footwork)
	footwork.configure(self)
	weapon = model.find_child("weapon", true, false)
	var tip: Node3D = model.find_child("Muzzle", true, false)
	muzzle_socket = tip
	# Flash cards, light pop, sparks, smoke and brass live in their own top-level node.
	muzzle_fx = preload("res://scripts/vfx/muzzle_flash.gd").new()
	add_child(muzzle_fx)
	muzzle_fx.configure(tip, self)
	muzzle = muzzle_fx.light
	sound = AudioStreamPlayer3D.new()
	sound.bus = "SFX"
	add_child(sound)
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data = PackedByteArray()
	data.resize(6615*2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 83
	for i in range(6615):
		var t = float(i)/22050.0
		var sample = (rng.randf_range(-1,1)*exp(-t*38)+sin(t*TAU*95)*exp(-t*22))*0.45
		data.encode_s16(i*2,int(clampf(sample,-1,1)*32767))
	wav.data = data
	sound.stream = wav
	sound.volume_db = -12

func render_origin() -> Vector3:
	if not smooth_motion:
		return global_position
	return tick_origins[0].lerp(tick_origins[1], Engine.get_physics_interpolation_fraction())

func _physics_process(_delta: float) -> void:
	if not smooth_motion:
		return
	# Runs after the expedition moved the body this tick; large jumps are teleports.
	tick_origins[0] = tick_origins[1] if tick_origins[1].distance_to(global_position) < 1.5 else global_position
	tick_origins[1] = global_position
	animate_live = animate_requested
	animate_requested = false

func _process(delta: float) -> void:
	if not smooth_motion:
		return
	visual.position = global_basis.inverse()*(render_origin()-global_position)
	if animate_live:
		animate(delta, frame_motion[0], frame_motion[1])

# Called from the gameplay tick. With smooth_motion, animation runs in _process at frame rate.
func request_animate(delta: float, moving: bool, dodging: bool) -> void:
	if not smooth_motion:
		animate(delta, moving, dodging)
		return
	frame_motion = [moving, dodging]
	animate_requested = true

func animate(delta: float, moving: bool, dodging: bool) -> void:
	clock += delta
	# A spring gives the rifle a sharp impulse, a shouldered catch and a short settle instead
	# of the old constant-rate slide. It remains visual: discharge and hitscan still happen in fire().
	recoil_velocity += (-recoil * 210.0 - recoil_velocity * 23.0) * delta
	recoil += recoil_velocity * delta
	lunge_velocity += (-lunge * 220.0 - lunge_velocity * 23.0) * delta
	lunge += lunge_velocity * delta
	recoil_lateral_velocity += (-recoil_lateral * 250.0 - recoil_lateral_velocity * 27.0) * delta
	recoil_lateral += recoil_lateral_velocity * delta
	if absf(recoil) < 0.001 and absf(recoil_velocity) < 0.01:
		recoil = 0.0
		recoil_velocity = 0.0
	if absf(lunge) < 0.001 and absf(lunge_velocity) < 0.01:
		lunge = 0.0
		lunge_velocity = 0.0
	if absf(recoil_lateral) < 0.001 and absf(recoil_lateral_velocity) < 0.01:
		recoil_lateral = 0.0
		recoil_lateral_velocity = 0.0
	flash_time = maxf(0,flash_time-delta)
	shot_time = maxf(0.0, shot_time-delta)
	reload_time = maxf(0.0, reload_time-delta)
	melee_time = maxf(0.0, melee_time-delta)
	ability_time = maxf(0.0, ability_time-delta)
	spin_time = maxf(0, spin_time - delta)
	inspect_time = maxf(0, inspect_time - delta)
	if hit_time > 0.0:
		hit_elapsed += delta
	hit_time = maxf(0,hit_time-delta)
	if dodging:
		dodge_elapsed = minf(dodge_elapsed + delta, dodge_duration)
	elif dodge_started:
		dodge_started = false

	var weapon_active := moving or dodging or dead or hit_time > 0 or absf(recoil) > 0.001 or spin_time > 0 \
		or reload_time > 0 or melee_time > 0 or ability_time > 0
	if weapon_active:
		idle_clock = 0.0
		inspect_triggered = false
	else:
		idle_clock += delta
		if idle_clock > INSPECT_DELAY and not inspect_triggered and weapon_state == "ready":
			inspect_triggered = true
			inspect_time = 1.2
			if animation_tree.has_node("parameters/inspect_seek/seek_request"):
				animation_tree.set("parameters/inspect_seek/seek_request", 0.0)
	update_weapon_state(delta, weapon_active)

	footwork.update_motion(delta,dodging or dead)
	var traveling: bool = footwork.speed > 0.08 and not dodging
	# Procedural transition phrases bridge the authored loops. They give starts a committed
	# forward catch, stops a compression/recovery and sharp direction changes a planted pivot
	# instead of cross-fading endlessly between four treadmill cycles.
	if traveling and not was_traveling:
		locomotion_start_weight = 1.0
	if not traveling and was_traveling:
		locomotion_stop_weight = 1.0
	if traveling and was_traveling and footwork.travel_direction.length_squared() > 0.01:
		var next_travel: Vector3 = footwork.travel_direction.normalized()
		var turn_dot := prior_travel_direction.dot(next_travel)
		if turn_dot < 0.72:
			locomotion_pivot_weight = maxf(locomotion_pivot_weight, clampf((0.72-turn_dot)/1.72, 0.0, 1.0))
			locomotion_pivot_sign = signf(prior_travel_direction.cross(next_travel).y)
		prior_travel_direction = next_travel
	locomotion_start_weight = move_toward(locomotion_start_weight, 0.0, delta / 0.16)
	locomotion_stop_weight = move_toward(locomotion_stop_weight, 0.0, delta / 0.20)
	locomotion_pivot_weight = move_toward(locomotion_pivot_weight, 0.0, delta / 0.18)
	was_traveling = traveling
	var next = "death" if dead else ("dodge" if dodging else ("run" if traveling else "idle"))
	if next != state:
		state = next
		if next == "dodge":
			if not dodge_started:
				begin_dodge(DEFAULT_DODGE_DURATION, global_basis * Vector3.FORWARD)
	# Facing direction is independent of movement direction. The upper body tracks the aim
	# target while the lower body follows the smoothed movement vector.
	if target_aim.length_squared() > 0.01:
		facing_direction = facing_direction.slerp(target_aim.normalized(), 1.0 - exp(-delta * FACING_SMOOTHING)).normalized()
	# Smooth the raw travel direction before converting to local space so rapid input
	# changes don't instantly reorient the hips/legs.
	if footwork.travel_direction.length_squared() > 0.001:
		movement_direction = movement_direction.slerp(footwork.travel_direction.normalized(), 1.0 - exp(-delta * DIRECTION_SMOOTHING)).normalized()
	else:
		movement_direction = Vector3.FORWARD
	smoothed_movement_direction = smoothed_movement_direction.slerp(movement_direction, 1.0 - exp(-delta * LOCOMOTION_SMOOTHING)).normalized()
	# Convert smoothed world-space movement into character-local locomotion parameters.
	# This is what drives the directional animation blend without rotating the skeleton.
	var local_motion = global_basis.inverse() * smoothed_movement_direction
	var target = Vector2.ZERO
	if traveling:
		target.x = clampf(local_motion.x, -1.0, 1.0)
		target.y = clampf(-local_motion.z, -1.0, 1.0)
		var blend_sum = absf(target.x) + absf(target.y)
		if blend_sum > 1.0:
			target /= blend_sum
	# Smooth locomotion blending for natural transitions between directions.
	locomotion_weights = locomotion_weights.lerp(target, 1.0 - exp(-delta * DIRECTION_SMOOTHING))
	animation_tree.set("parameters/locomotion/blend_position", locomotion_weights)
	# Sync animation speed with actual horizontal gameplay velocity.
	var reference_speed = FORWARD_REFERENCE_SPEED
	if absf(local_motion.z) < 0.5 and absf(local_motion.x) > 0.5:
		reference_speed = STRAFE_REFERENCE_SPEED
	elif local_motion.z > 0.1:
		reference_speed = BACKWARD_REFERENCE_SPEED
	var actual_speed = footwork.speed
	var speed_ratio = actual_speed / maxf(reference_speed, 0.01)
	current_animation_speed = clampf(speed_ratio, ANIMATION_SPEED_MIN, ANIMATION_SPEED_MAX)
	animation_tree.set("parameters/cadence/scale", current_animation_speed if traveling else 1.0)
	# Blend into the defensive pose fast enough to read on commitment (matches the
	# 0.035 s hit-attack convention), then ease back smoothly.
	dodge_blend = move_toward(dodge_blend,1.0 if dodging else 0.0,delta/(0.035 if dodging else 0.12))
	animation_tree.set("parameters/defense/blend_amount",dodge_blend)
	animation_tree.set("parameters/aim_layer/blend_amount", 1.0 if weapon_state == "ready" and not dodging and not dead else 0.0)
	var hit_attack := clampf(hit_elapsed / 0.035, 0.0, 1.0)
	var hit_release := clampf(hit_time / 0.20, 0.0, 1.0)
	animation_tree.set("parameters/reaction/blend_amount", hit_attack * hit_release * 0.82 if hit_time > 0 else 0.0)

	# Spin & Inspect flourish blend
	var spin_weight = clampf(spin_time / 0.5, 0.0, 1.0)
	var inspect_weight = sin(clampf(inspect_time / 1.2, 0.0, 1.0) * PI) * 0.85
	animation_tree.set("parameters/spin_blend/blend_amount", spin_weight)
	animation_tree.set("parameters/inspect_blend/blend_amount", inspect_weight if spin_weight <= 0 else 0.0)
	animation_tree.set("parameters/reload_layer/blend_amount", action_weight(reload_time, RELOAD_DURATION))
	animation_tree.set("parameters/melee_layer/blend_amount", action_weight(melee_time, MELEE_DURATION))
	animation_tree.set("parameters/ability_layer/blend_amount", action_weight(ability_time, ABILITY_DURATION))
	if shot_time > 0:
		var fire_duration = 0.16 if fire_counter else 0.13
		var fire_elapsed = fire_duration - shot_time
		if fire_elapsed < 0.05:
			animation_tree.set("parameters/fire_layer/blend_amount", clampf(fire_elapsed / 0.05, 0.0, 1.0))
		else:
			animation_tree.set("parameters/fire_layer/blend_amount", minf(shot_time / 0.04, 1.0))
	else:
		animation_tree.set("parameters/fire_layer/blend_amount", 0.0)

	animation_tree.set("parameters/defeat/blend_amount",1.0 if dead else 0.0)
	animation_tree.advance(delta)

	# Procedural torso banking & lean into velocity
	var target_banking_roll = -locomotion_weights.x * 0.05
	var target_banking_pitch = locomotion_weights.y * 0.025
	banking_roll = lerpf(banking_roll, target_banking_roll, 1.0 - exp(-delta * 12.0))
	banking_pitch = lerpf(banking_pitch, target_banking_pitch, 1.0 - exp(-delta * 12.0))

	# Smooth visual model yaw toward gameplay rotation for grounded body momentum.
	# The visual counter-rotates relative to the capsule so the model catches up
	# instead of snapping instantly, without affecting gameplay targeting.
	var capsule_yaw = global_basis.get_rotation_quaternion().get_euler().y
	var target_visual_yaw = lerp_angle(0.0, capsule_yaw, 0.35)
	visual_yaw = lerp_angle(visual_yaw, target_visual_yaw, 1.0 - exp(-delta * 12.0))
	visual.rotation.y = visual_yaw

	# Recoil kicks back and slightly right; lateral torque adds weight.
	model.position.z = recoil * 0.042 + lunge * 0.035
	model.position.x = recoil_lateral * 0.010
	var transition_pitch := -locomotion_start_weight * 0.085 + locomotion_stop_weight * 0.065
	var pivot_roll := locomotion_pivot_sign * locomotion_pivot_weight * 0.075
	model.rotation.x = -recoil * 0.042 + banking_pitch + transition_pitch
	model.rotation.z = recoil_lateral * 0.018 + banking_roll + pivot_roll

	# Subtle weapon sway during locomotion adds life without fighting the aim. Swayed Y
	# is a smoothed offset of the live amplitude, so stopping eases it back to rest
	# instead of freezing at its last value.
	var sway_factor = clampf(footwork.speed / 6.0, 0, 1) if not dodging and not dead else 0.0
	if sway_factor > 0:
		weapon_sway += delta * footwork.speed * 0.8
	model.position.x += sin(weapon_sway * 2.3) * 0.003 * sway_factor
	var transition_drop := (locomotion_start_weight * 0.032 + locomotion_stop_weight * 0.045) if not dodging else 0.0
	model.position.y = lerpf(model.position.y,
		sin(weapon_sway * 4.6) * 0.001 * sway_factor - transition_drop,
		1.0 - exp(-delta * 18.0))
	footwork.get_skeleton().advance(delta)

func fire(counter := false) -> void:
	# Firing must never wait behind a cosmetic draw animation. Movement normally draws the
	# rifle first; this snap is the responsive fallback for a shot from a long idle.
	ready_weapon(true)
	fire_counter = counter
	# The first displacement is visible on the discharge frame; velocity carries it into a
	# forceful kick and the spring returns it to the shoulder before the next legal shot.
	recoil = maxf(recoil, 0.16 if counter else 0.12)
	recoil_velocity += 21.0 if counter else 16.5
	recoil_lateral = 0.06 if recoil_lateral == 0.0 else recoil_lateral
	recoil_lateral_velocity += 7.0 if counter else 4.5
	# Subtle backward lunge — a brief step that sells the rifle's report weight.
	lunge = maxf(lunge, 0.12 if counter else 0.06)
	lunge_velocity += 4.0
	shot_time = 0.16 if counter else 0.13
	animation_tree.set("parameters/fire_seek/seek_request", 0.0)
	animation_tree.set("parameters/fire_layer/blend_amount", 1.0)
	if counter:
		spin_time = 0.5
		animation_tree.set("parameters/spin_seek/seek_request", 0.0)
	sound.volume_db = -10 if counter else -12
	flash_time = 0.045
	muzzle_fx.fire(counter)
	sound.play()
	
	# UniMate shoot animation
	if unimate_anims:
		unimate_anims.on_fire(counter)

func action_weight(time_left: float, duration: float) -> float:
	if time_left <= 0.0:
		return 0.0
	var elapsed := duration - time_left
	return minf(elapsed / 0.02, 1.0) * minf(time_left / 0.10, 1.0)

func reload() -> void:
	if dead:
		return
	ready_weapon(true)
	reload_time = RELOAD_DURATION
	animation_tree.set("parameters/reload_seek/seek_request", 0.0)
	animation_tree.set("parameters/reload_layer/blend_amount", 1.0)
	
	# UniMate reload animation
	if unimate_anims:
		unimate_anims.on_reload()

func melee() -> void:
	if dead:
		return
	ready_weapon(true)
	melee_time = MELEE_DURATION
	animation_tree.set("parameters/melee_seek/seek_request", 0.0)
	animation_tree.set("parameters/melee_layer/blend_amount", 1.0)
	
	# UniMate melee animation
	if unimate_anims:
		unimate_anims.on_melee()

func ability() -> void:
	if dead:
		return
	ready_weapon(true)
	ability_time = ABILITY_DURATION
	animation_tree.set("parameters/ability_seek/seek_request", 0.0)
	animation_tree.set("parameters/ability_layer/blend_amount", 1.0)

func muzzle_position() -> Vector3:
	return muzzle_socket.global_position

func setup_directional_blend() -> void:
	var graph = AnimationNodeBlendTree.new()
	var locomotion = AnimationNodeBlendSpace2D.new()
	locomotion.min_space = Vector2(-1,-1)
	locomotion.max_space = Vector2(1,1)
	locomotion.sync = true
	var clips = {"idle":Vector2.ZERO,"run":Vector2(0,1),
		"run_backward":Vector2(0,-1),"strafe_left":Vector2(-1,0),"strafe_right":Vector2(1,0)}
	for clip in clips:
		var node = AnimationNodeAnimation.new()
		node.animation = clip
		locomotion.add_blend_point(node,clips[clip],-1,clip)
	graph.add_node("locomotion",locomotion)
	graph.add_node("cadence",AnimationNodeTimeScale.new())
	var dodge_clip = AnimationNodeAnimation.new()
	dodge_clip.animation = "dodge"
	graph.add_node("dodge",dodge_clip)
	graph.add_node("dodge_speed",AnimationNodeTimeScale.new())
	graph.add_node("dodge_seek",AnimationNodeTimeSeek.new())
	graph.add_node("defense",AnimationNodeBlend2.new())
	graph.connect_node("cadence",0,"locomotion")
	graph.connect_node("dodge_speed",0,"dodge")
	graph.connect_node("dodge_seek",0,"dodge_speed")
	graph.connect_node("defense",0,"cadence")
	graph.connect_node("defense",1,"dodge_seek")

	# The concept's shouldered aim is a stable upper-body layer over every movement direction.
	# Dodge disables its weight so the committed defensive silhouette remains intact.
	var aim_clip = AnimationNodeAnimation.new()
	aim_clip.animation = "aim"
	var aim_layer = AnimationNodeBlend2.new()
	aim_layer.filter_enabled = true
	var aim_animation: Animation = anim.get_animation("aim")
	for track in aim_animation.get_track_count():
		var path := aim_animation.track_get_path(track)
		if path.get_subname_count() > 0 and WEAPON_UPPER_BONES.has(String(path.get_subname(0))):
			aim_layer.set_filter_path(path, true)
			if path not in aim_filter_paths:
				aim_filter_paths.append(path)
	graph.add_node("aim", aim_clip)
	graph.add_node("aim_layer", aim_layer)
	graph.connect_node("aim_layer", 0, "defense")
	graph.connect_node("aim_layer", 1, "aim")

	var hit_clip = AnimationNodeAnimation.new()
	hit_clip.animation = "hit"
	graph.add_node("hit",hit_clip)
	graph.add_node("hit_seek",AnimationNodeTimeSeek.new())
	graph.add_node("reaction",AnimationNodeBlend2.new())
	graph.connect_node("hit_seek",0,"hit")
	graph.connect_node("reaction",0,"aim_layer")
	graph.connect_node("reaction",1,"hit_seek")

	# Spin flourish node
	var spin_clip = AnimationNodeAnimation.new()
	spin_clip.animation = "spin"
	graph.add_node("spin", spin_clip)
	graph.add_node("spin_seek", AnimationNodeTimeSeek.new())
	graph.add_node("spin_blend", AnimationNodeBlend2.new())
	graph.connect_node("spin_seek", 0, "spin")
	graph.connect_node("spin_blend", 0, "reaction")
	graph.connect_node("spin_blend", 1, "spin_seek")

	# Inspect flourish node
	var inspect_clip = AnimationNodeAnimation.new()
	inspect_clip.animation = "inspect"
	graph.add_node("inspect", inspect_clip)
	graph.add_node("inspect_seek", AnimationNodeTimeSeek.new())
	graph.add_node("inspect_blend", AnimationNodeBlend2.new())
	graph.connect_node("inspect_seek", 0, "inspect")
	graph.connect_node("inspect_blend", 0, "spin_blend")
	graph.connect_node("inspect_blend", 1, "inspect_seek")

	# Concept actions are layered in priority order. They remain interruptible and never replace
	# lower-body locomotion; fire can override them immediately, preserving weapon response.
	var reload_clip = AnimationNodeAnimation.new()
	reload_clip.animation = "reload"
	graph.add_node("reload", reload_clip)
	graph.add_node("reload_seek", AnimationNodeTimeSeek.new())
	var reload_layer = AnimationNodeBlend2.new()
	reload_layer.filter_enabled = true
	var reload_animation: Animation = anim.get_animation("reload")
	for track in reload_animation.get_track_count():
		var path := reload_animation.track_get_path(track)
		if path.get_subname_count() > 0 and WEAPON_UPPER_BONES.has(String(path.get_subname(0))):
			reload_layer.set_filter_path(path, true)
			if path not in reload_filter_paths:
				reload_filter_paths.append(path)
	graph.add_node("reload_layer", reload_layer)
	graph.connect_node("reload_seek", 0, "reload")
	graph.connect_node("reload_layer", 0, "inspect_blend")
	graph.connect_node("reload_layer", 1, "reload_seek")

	var melee_clip = AnimationNodeAnimation.new()
	melee_clip.animation = "melee"
	graph.add_node("melee", melee_clip)
	graph.add_node("melee_seek", AnimationNodeTimeSeek.new())
	var melee_layer = AnimationNodeBlend2.new()
	melee_layer.filter_enabled = true
	var melee_animation: Animation = anim.get_animation("melee")
	for track in melee_animation.get_track_count():
		var path := melee_animation.track_get_path(track)
		if path.get_subname_count() > 0 and WEAPON_UPPER_BONES.has(String(path.get_subname(0))):
			melee_layer.set_filter_path(path, true)
			if path not in melee_filter_paths:
				melee_filter_paths.append(path)
	graph.add_node("melee_layer", melee_layer)
	graph.connect_node("melee_seek", 0, "melee")
	graph.connect_node("melee_layer", 0, "reload_layer")
	graph.connect_node("melee_layer", 1, "melee_seek")

	var ability_clip = AnimationNodeAnimation.new()
	ability_clip.animation = "ability"
	graph.add_node("ability", ability_clip)
	graph.add_node("ability_seek", AnimationNodeTimeSeek.new())
	var ability_layer = AnimationNodeBlend2.new()
	ability_layer.filter_enabled = true
	var ability_animation: Animation = anim.get_animation("ability")
	for track in ability_animation.get_track_count():
		var path := ability_animation.track_get_path(track)
		if path.get_subname_count() > 0 and WEAPON_UPPER_BONES.has(String(path.get_subname(0))):
			ability_layer.set_filter_path(path, true)
			if path not in ability_filter_paths:
				ability_filter_paths.append(path)
	graph.add_node("ability_layer", ability_layer)
	graph.connect_node("ability_seek", 0, "ability")
	graph.connect_node("ability_layer", 0, "melee_layer")
	graph.connect_node("ability_layer", 1, "ability_seek")

	# Fire is an upper-body one-shot so shooting never cancels strafing, backpedalling or foot
	# plants. Death remains downstream and therefore always wins over a late discharge.
	var fire_clip = AnimationNodeAnimation.new()
	fire_clip.animation = "fire"
	graph.add_node("fire", fire_clip)
	graph.add_node("fire_seek", AnimationNodeTimeSeek.new())
	var fire_layer = AnimationNodeBlend2.new()
	fire_layer.filter_enabled = true
	var fire_animation: Animation = anim.get_animation("fire")
	for track in fire_animation.get_track_count():
		var path := fire_animation.track_get_path(track)
		if path.get_subname_count() > 0 and WEAPON_UPPER_BONES.has(String(path.get_subname(0))):
			fire_layer.set_filter_path(path, true)
			if path not in fire_filter_paths:
				fire_filter_paths.append(path)
	graph.add_node("fire_layer", fire_layer)
	graph.connect_node("fire_seek", 0, "fire")
	graph.connect_node("fire_layer", 0, "ability_layer")
	graph.connect_node("fire_layer", 1, "fire_seek")

	var death_clip = AnimationNodeAnimation.new()
	death_clip.animation = "death"
	graph.add_node("death",death_clip)
	graph.add_node("death_seek",AnimationNodeTimeSeek.new())
	graph.add_node("defeat",AnimationNodeBlend2.new())
	graph.connect_node("death_seek",0,"death")
	graph.connect_node("defeat",0,"fire_layer")
	graph.connect_node("defeat",1,"death_seek")

	# The GLB exporter force-samples constraint-baked actions, so even the authored upper-body
	# clips contain lower-body tracks. Filter the final blend by semantic bone name to keep the
	# locomotion legs underneath sheath, unsheath and the slung idle. All three weapon clips
	# contribute so a track carried by only one of them still stays on the weapon layer.
	var sheath_clip = AnimationNodeAnimation.new()
	sheath_clip.animation = "sheath"
	var unsheath_clip = AnimationNodeAnimation.new()
	unsheath_clip.animation = "unsheath"
	var sheathed_clip = AnimationNodeAnimation.new()
	sheathed_clip.animation = "sheathed_idle"
	graph.add_node("sheath", sheath_clip)
	graph.add_node("unsheath", unsheath_clip)
	graph.add_node("sheathed_idle", sheathed_clip)
	graph.add_node("sheath_seek", AnimationNodeTimeSeek.new())
	graph.add_node("unsheath_seek", AnimationNodeTimeSeek.new())
	graph.add_node("weapon_motion", AnimationNodeBlend2.new())
	graph.add_node("weapon_pose", AnimationNodeBlend2.new())
	var weapon_layer = AnimationNodeBlend2.new()
	weapon_layer.filter_enabled = true
	for clip in ["sheath", "unsheath", "sheathed_idle"]:
		var weapon_animation: Animation = anim.get_animation(clip)
		for track in weapon_animation.get_track_count():
			var path := weapon_animation.track_get_path(track)
			if path.get_subname_count() > 0 and WEAPON_UPPER_BONES.has(String(path.get_subname(0))):
				weapon_layer.set_filter_path(path, true)
				if path not in weapon_filter_paths:
					weapon_filter_paths.append(path)
	graph.add_node("weapon_layer", weapon_layer)
	graph.connect_node("sheath_seek", 0, "sheath")
	graph.connect_node("unsheath_seek", 0, "unsheath")
	graph.connect_node("weapon_motion", 0, "sheath_seek")
	graph.connect_node("weapon_motion", 1, "unsheath_seek")
	graph.connect_node("weapon_pose", 0, "weapon_motion")
	graph.connect_node("weapon_pose", 1, "sheathed_idle")
	graph.connect_node("weapon_layer", 0, "defeat")
	graph.connect_node("weapon_layer", 1, "weapon_pose")
	graph.connect_node("output",0,"weapon_layer")

	animation_tree = AnimationTree.new()
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(anim)
	animation_tree.tree_root = graph
	animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_tree.set("parameters/dodge_speed/scale",anim.get_animation("dodge").length/DEFAULT_DODGE_DURATION)
	animation_tree.set("parameters/aim_layer/blend_amount", 1.0)
	animation_tree.set("parameters/reload_layer/blend_amount", 0.0)
	animation_tree.set("parameters/melee_layer/blend_amount", 0.0)
	animation_tree.set("parameters/ability_layer/blend_amount", 0.0)
	animation_tree.set("parameters/fire_layer/blend_amount", 0.0)
	animation_tree.set("parameters/weapon_layer/blend_amount", 0.0)
	animation_tree.active = true

func update_weapon_state(delta: float, active: bool) -> void:
	if active:
		ready_weapon(false)
	elif weapon_state == "ready" and idle_clock >= SHEATH_DELAY:
		set_weapon_state("sheathing")
	weapon_state_time += delta
	if weapon_state == "sheathing" and weapon_state_time >= anim.get_animation("sheath").length:
		set_weapon_state("sheathed")
	elif weapon_state == "drawing" and weapon_state_time >= anim.get_animation("unsheath").length:
		set_weapon_state("ready")

func ready_weapon(snap: bool = false) -> void:
	if weapon_state == "ready":
		return
	set_weapon_state("ready" if snap else "drawing")
	if snap:
		# Apply the ready layer immediately so the muzzle flash starts at the barrel, not the rig.
		animation_tree.advance(0.0)

func set_weapon_state(next: String) -> void:
	if next == weapon_state:
		return
	weapon_state = next
	weapon_state_time = 0.0
	match next:
		"ready":
			animation_tree.set("parameters/weapon_layer/blend_amount", 0.0)
		"sheathing":
			animation_tree.set("parameters/weapon_motion/blend_amount", 0.0)
			animation_tree.set("parameters/weapon_pose/blend_amount", 0.0)
			animation_tree.set("parameters/weapon_layer/blend_amount", 1.0)
			animation_tree.set("parameters/sheath_seek/seek_request", 0.0)
		"sheathed":
			animation_tree.set("parameters/weapon_pose/blend_amount", 1.0)
			animation_tree.set("parameters/weapon_layer/blend_amount", 1.0)
		"drawing":
			animation_tree.set("parameters/weapon_motion/blend_amount", 1.0)
			animation_tree.set("parameters/weapon_pose/blend_amount", 0.0)
			animation_tree.set("parameters/weapon_layer/blend_amount", 1.0)
			animation_tree.set("parameters/unsheath_seek/seek_request", 0.0)
	
	# UniMate weapon state change
	if unimate_anims:
		unimate_anims.on_weapon_state_changed(next)

func begin_dodge(duration: float, direction: Vector3) -> void:
	dodge_duration = maxf(duration, 0.01)
	dodge_elapsed = 0.0
	dodge_direction = direction.normalized() if direction.length_squared() > 0.001 else -global_basis.z
	dodge_started = true
	ready_weapon(true)
	animation_tree.set("parameters/dodge_speed/scale", anim.get_animation("dodge").length/dodge_duration)
	animation_tree.set("parameters/dodge_seek/seek_request", 0.0)
	footwork.begin_dodge(dodge_duration, dodge_direction)
	
	# UniMate dodge animation
	if unimate_anims:
		unimate_anims.play_dodge(dodge_direction)

func dodge_phase() -> float:
	return clampf(dodge_elapsed / maxf(dodge_duration, 0.01), 0.0, 1.0)

func hit(source_direction: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	if source_direction.length_squared() > 0.001:
		hit_direction = (global_basis.inverse() * source_direction.normalized())
		death_direction = hit_direction
	hit_time = HIT_DURATION
	hit_elapsed = 0.0
	ready_weapon(true)
	animation_tree.set("parameters/hit_seek/seek_request",0.0)

func die(source_direction: Vector3 = Vector3.ZERO) -> void:
	if dead:
		return
	if source_direction.length_squared() > 0.001:
		death_direction = global_basis.inverse() * source_direction.normalized()
	dead = true
	ready_weapon(true)
	hit_time = 0.0
	animation_tree.set("parameters/death_seek/seek_request",0.0)
