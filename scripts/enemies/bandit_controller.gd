extends CharacterBody3D
## Basic bandit controller.  Uses the ybot_root skin with the same animation
## library and AnimationTree state machine as the player.  Movement is driven
## by AI (NavigationAgent3D) instead of player input.

@export var move_speed: float = 3.5
@export var rotation_speed: float = 10.0
@export var gravity_scale: float = 1.35
@export var blend_lerp_speed: float = 8.0

# Phase 3: per-alert-level movement speeds
@export var speed_curious: float = 3.0    ## cautious walk when curious
@export var speed_alert: float = 4.5      ## jog when actively searching
@export var speed_combat: float = 6.0     ## sprint when in combat

## Maximum distance the bandit is allowed to travel from his spawn point.
@export var leash_radius: float = 100.0

@onready var visual_root: Node3D = $ybot_root
@onready var anim_tree: AnimationTree = $ybot_root/AnimationTree
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var _anim_player: AnimationPlayer = $ybot_root/AnimationPlayer

var _was_moving := false
var _current_loco_blend: float = 0.0
var _frozen := false
var _freeze_timer: SceneTreeTimer
var home_position: Vector3
var _current_alert: int = 0

# Smooth speed target — lerped into move_speed each frame so alert transitions ramp, not snap
var _target_speed: float = 3.5

# Turn-in-place state
var _turning: bool = false
var _turn_dir: int = 0  # -1 = left, +1 = right

# Idle variety
var _idle_variant_timer: float = 0.0

# Phase 4: Turn toward sound
var _look_target: Vector3 = Vector3.INF
var _look_timer: float = 0.0
const _LOOK_DURATION := 2.0
const _LOOK_SPEED := 3.0

func _ready() -> void:
	anim_tree.active = true
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	home_position = global_position
	# Phase 4: Connect heard_noise from perception
	var perception := get_node_or_null("BanditPerception")
	if perception and perception.has_signal("heard_noise"):
		perception.heard_noise.connect(look_toward)
	# Phase 3: Speed tiers per alert level
	if perception and perception.has_signal("alert_level_changed"):
		perception.alert_level_changed.connect(_on_alert_level_changed)
	# Focus mode: spawn heart indicator on chest bone
	_spawn_heart_indicator()

func freeze(duration: float) -> void:
	_frozen = true
	set_physics_process(false)
	# Use post-wrap parameter paths (patrol wraps tree_root in a BlendTree)
	anim_tree.set("parameters/StateMachine/conditions/is_moving", false)
	anim_tree.set("parameters/StateMachine/conditions/is_stopping", true)
	if _freeze_timer and _freeze_timer.time_left > 0.0:
		_freeze_timer.timeout.disconnect(unfreeze)
	_freeze_timer = get_tree().create_timer(duration)
	_freeze_timer.timeout.connect(unfreeze)


func unfreeze() -> void:
	_frozen = false
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	# Phase C: smoothly ramp move_speed toward the alert-tier target
	move_speed = move_toward(move_speed, _target_speed, 4.0 * delta)

	# Leash: if outside allowed radius, reset AI and navigate straight home.
	if global_position.distance_to(home_position) > leash_radius:
		var perception := get_node_or_null("BanditPerception")
		if perception and perception.has_method("reset_alert"):
			perception.reset_alert()
		nav_agent.target_position = home_position

	var is_moving := false
	if not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var dir := (next_pos - global_position)
		dir.y = 0.0
		if dir.length() > 0.1:
			is_moving = true
			_face_direction(dir.normalized(), delta)
			# Velocity is driven by root motion below — not dir * speed

	# Phase 4: Turn toward heard sound when idle
	if not is_moving and _look_timer > 0.0:
		_look_timer -= delta
		var look_dir := (_look_target - global_position)
		look_dir.y = 0.0
		if look_dir.length() > 0.1:
			_face_direction(look_dir.normalized(), delta * _LOOK_SPEED / rotation_speed)

	_update_animation(is_moving, delta)

	# Root motion drives XZ velocity so animation and ground contact stay in sync.
	# visual_root faces the movement direction, so local +Z becomes world forward.
	var rm_local := anim_tree.get_root_motion_position()
	var rm_world := visual_root.global_transform.basis * rm_local
	if is_moving and not _turning:
		velocity.x = rm_world.x / delta
		velocity.z = rm_world.z / delta
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	# Drive move_and_slide via avoidance callback (pass-through when avoidance off)
	nav_agent.set_velocity(velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()

func set_target(pos: Vector3) -> void:
	# Clamp the requested destination to within leash radius.
	var offset := pos - home_position
	if offset.length() > leash_radius:
		pos = home_position + offset.normalized() * leash_radius
	nav_agent.target_position = pos

func look_toward(world_pos: Vector3) -> void:
	_look_target = world_pos
	_look_timer = _LOOK_DURATION


# Called when BanditPerception.alert_level_changed fires
func _on_alert_level_changed(level: int) -> void:
	_current_alert = level
	# Set target; move_speed lerps toward it in _physics_process() — no instant snapping
	match level:
		1: _target_speed = speed_curious
		2: _target_speed = speed_alert
		3: _target_speed = speed_combat

func _face_direction(dir: Vector3, delta: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	var current_angle := visual_root.rotation.y
	visual_root.rotation.y = lerp_angle(current_angle, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))

func _update_animation(is_moving: bool, delta: float) -> void:
	# ── Idle variety ──────────────────────────────────────────────────────────
	if not is_moving:
		if _was_moving:
			# Just stopped — play appropriate idle immediately and reset timer
			_play_alert_idle()
			_idle_variant_timer = randf_range(8.0, 15.0)
		else:
			_idle_variant_timer -= delta
			if _idle_variant_timer <= 0.0:
				_play_alert_idle()
				_idle_variant_timer = randf_range(8.0, 15.0)

	# ── Turn-in-place ── play left/right turn clip when angle error is large ──
	if is_moving:
		var vel2d := Vector2(velocity.x, velocity.z)
		var face2d := Vector2(visual_root.global_transform.basis.z.x,
							  visual_root.global_transform.basis.z.z)
		if vel2d.length() > 0.05 and face2d.length() > 0.05:
			var angle_err := face2d.angle_to(vel2d.normalized())
			if abs(angle_err) > deg_to_rad(40.0) and move_speed < speed_alert:
				if not _turning:
					_turning = true
					_turn_dir = 1 if angle_err > 0.0 else -1
					var turn_anim := "npc_male_locomotion/right_turn" \
									 if _turn_dir > 0 else "npc_male_locomotion/left_turn"
					if _anim_player.has_animation(turn_anim):
						_anim_player.play(turn_anim, 0.15)
				_was_moving = is_moving
				return  # suppress BlendSpace while turning
			else:
				if _turning:
					_turning = false
					_anim_player.stop()  # hand back control to AnimationTree
	else:
		if _turning:
			_turning = false
			_anim_player.stop()

	# ── State machine parameters ──────────────────────────────────────────────
	anim_tree.set("parameters/StateMachine/conditions/is_moving", is_moving)
	anim_tree.set("parameters/StateMachine/conditions/is_stopping", _was_moving and not is_moving)

	# blend_position: 0=idle, 1.0=walk, 2.0=run. Alert 0-2 walk fast; only combat runs.
	# (1.5 removed — it was a dead zone between walk and run clips)
	var loco_target: float
	if is_moving:
		match _current_alert:
			0, 1, 2: loco_target = 1.0
			_:       loco_target = 2.0
	else:
		loco_target = 0.0
	_current_loco_blend = move_toward(_current_loco_blend, loco_target, blend_lerp_speed * delta)
	anim_tree.set("parameters/StateMachine/Locomotion/blend_position", _current_loco_blend)

	_was_moving = is_moving


func _play_alert_idle() -> void:
	if not _anim_player:
		return
	var anim_name: String
	match _current_alert:
		0:
			# Calm: rotate between two natural standing variants
			var opts: Array[String] = ["npc_axe/standing_idle", "npc_axe/standing_idle_looking_ver"]
			anim_name = opts.pick_random()
		1:
			anim_name = "npc_axe/standing_idle_looking_ver_001"  # nervous glance
		2:
			anim_name = "npc_axe/unarmed_idle_looking_ver"       # scanning
		_:
			anim_name = "npc_axe/standing_idle"                  # combat ready
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, 0.3)

# ── Focus Mode Heart Indicator ───────────────────────────────────────────────

const _HEART_SHADER := preload("res://assets/shaders/heart_icon.gdshader")
const _HEART_SCRIPT := preload("res://scripts/enemies/heart_indicator.gd")

func _spawn_heart_indicator() -> void:
	var skel: Skeleton3D = visual_root.get_node_or_null("Armature/Skeleton3D")
	if not skel:
		push_warning("[HeartSpawn] ", name, ": No Armature/Skeleton3D under visual_root")
		return
	# Dump all bone names once for diagnostics
	var all_bones: PackedStringArray = []
	for i in skel.get_bone_count():
		all_bones.append(skel.get_bone_name(i))
	print("[HeartSpawn] ", name, ": skeleton bones = ", all_bones)
	# Find a chest / upper-spine bone
	var bone_idx := -1
	var matched_bone_name := ""
	for bone_name in ["spine.002", "Spine2", "spine_02", "chest", "Spine1"]:
		bone_idx = skel.find_bone(bone_name)
		if bone_idx >= 0:
			matched_bone_name = bone_name
			print("[HeartSpawn] ", name, ": matched bone '", bone_name, "' idx=", bone_idx)
			break
	if bone_idx < 0:
		push_warning("[HeartSpawn] ", name, ": No chest bone found in skeleton! Tried spine.002/Spine2/spine_02/chest/Spine1")
		return

	# Set bone_name BEFORE add_child so BoneAttachment3D resolves the bone correctly
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = matched_bone_name
	skel.add_child(attachment)
	attachment.bone_idx = bone_idx  # Set idx after entering tree

	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)  # larger for reliable visibility

	var mat := ShaderMaterial.new()
	mat.shader = _HEART_SHADER
	mat.set_shader_parameter("heart_color", Color(0.85, 0.12, 0.1, 1.0))
	mat.set_shader_parameter("alpha_mult", 1.0)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = quad
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.set_script(_HEART_SCRIPT)
	# Parent to visual_root; heart_indicator.gd positions itself via bone pose each frame
	visual_root.add_child(mesh_inst)
	mesh_inst.call("setup_bone", skel, bone_idx)
	print("[HeartSpawn] ", name, ": heart MeshInstance3D created (child of visual_root, manual bone tracking)")
