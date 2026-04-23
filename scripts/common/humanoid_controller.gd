extends "res://scripts/common/icombat_target.gd"
## Shared locomotion/body controller for Mixamo humanoids.
## Owns movement, navigation handoff, root motion, and locomotion tree updates.

const FOOT_IK_SCRIPT := preload("res://scripts/player/foot_ik.gd")

@export var move_speed: float = 3.5
@export var rotation_speed: float = 10.0
@export var gravity_scale: float = 1.35
@export var blend_lerp_speed: float = 8.0
@export var min_root_motion_speed: float = 0.35
@export var speed_lerp_rate: float = 4.0
@export var combat_speed_scale: float = 1.5

@export var visual_root_path: NodePath = ^"ybot_root"
@export var anim_tree_path: NodePath = ^"ybot_root/AnimationTree"
@export var anim_player_path: NodePath = ^"ybot_root/AnimationPlayer"
@export var nav_agent_path: NodePath = ^"NavigationAgent3D"
@export var foot_ik_path: NodePath = ^"FootIK"

@export var look_duration: float = 2.0
@export var look_speed: float = 3.0

var visual_root: Node3D
var anim_tree: AnimationTree
var nav_agent: NavigationAgent3D
var anim_player: AnimationPlayer
var foot_ik: Node

var _was_moving := false
var _current_loco_blend: float = 0.0
var _frozen := false
var _freeze_remaining: float = 0.0
var _action_locked: bool = false
var home_position: Vector3
var _current_alert: int = 0
var _target_speed: float = 0.0
var _look_target: Vector3 = Vector3.INF
var _look_timer: float = 0.0


func _ready() -> void:
	set_process(false)
	_resolve_nodes()
	_ensure_foot_ik_node()
	if anim_tree:
		anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		anim_tree.active = true
	if nav_agent and nav_agent.avoidance_enabled and not nav_agent.velocity_computed.is_connected(_on_velocity_computed):
		nav_agent.velocity_computed.connect(_on_velocity_computed)
	home_position = global_position
	_target_speed = move_speed
	_on_controller_ready()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	move_speed = move_toward(move_speed, _target_speed, speed_lerp_rate * delta)
	_before_move(delta)
	if _action_locked:
		if anim_player:
			anim_player.speed_scale = _get_action_playback_scale()
		var locked_motion := _get_action_root_motion_velocity(delta)
		velocity.x = locked_motion.x
		velocity.z = locked_motion.z
		_process_idle_look(false, delta)
		move_and_slide()
		_update_foot_ik(delta)
		return

	var is_moving := false
	var move_dir := Vector3.ZERO
	var force_idle := _should_force_idle()
	if not force_idle and nav_agent and not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var dir := next_pos - global_position
		dir.y = 0.0
		if dir.length() > 0.1:
			is_moving = true
			move_dir = dir.normalized()
			_face_direction(move_dir, delta)

	_process_idle_look(is_moving, delta)
	_update_animation_state(is_moving, delta)
	_apply_horizontal_motion(is_moving, move_dir, delta)

	if nav_agent:
		if nav_agent.avoidance_enabled:
			nav_agent.set_velocity(velocity)
		else:
			move_and_slide()
	else:
		move_and_slide()
	_update_foot_ik(delta)


func freeze(duration: float) -> void:
	_frozen = true
	_freeze_remaining = duration
	_clear_foot_ik_overrides()
	set_physics_process(false)
	set_process(true)
	_set_anim_condition("is_moving", false)
	_set_anim_condition("is_stopping", true)


func unfreeze() -> void:
	_frozen = false
	_freeze_remaining = 0.0
	set_process(false)
	set_physics_process(true)


func _process(delta: float) -> void:
	if not _frozen:
		set_process(false)
		return
	_freeze_remaining -= delta
	if _freeze_remaining <= 0.0:
		unfreeze()


func set_target_position(pos: Vector3) -> void:
	if nav_agent:
		nav_agent.target_position = pos


func set_target(pos: Vector3) -> void:
	set_target_position(pos)


func clear_target() -> void:
	if nav_agent:
		nav_agent.target_position = global_position


func look_toward(world_pos: Vector3) -> void:
	_look_target = world_pos
	_look_timer = look_duration


func clear_look_toward() -> void:
	_look_target = Vector3.INF
	_look_timer = 0.0


func set_alert_level(level: int) -> void:
	_current_alert = level


func set_desired_move_speed(value: float) -> void:
	_target_speed = maxf(value, 0.0)


func set_action_locked(value: bool) -> void:
	_action_locked = value
	if value:
		velocity.x = 0.0
		velocity.z = 0.0
		if nav_agent:
			nav_agent.target_position = global_position


func is_action_locked() -> bool:
	return _action_locked


func get_desired_move_speed() -> float:
	return _target_speed


func is_navigation_finished() -> bool:
	return nav_agent == null or nav_agent.is_navigation_finished()


func is_moving_now() -> bool:
	return Vector2(velocity.x, velocity.z).length() > 0.05


func _get_action_playback_scale() -> float:
	return 1.0


func _on_controller_ready() -> void:
	pass


func _before_move(_delta: float) -> void:
	pass


func _update_animation_state(is_moving: bool, delta: float) -> void:
	_set_anim_condition("is_moving", is_moving)
	_set_anim_condition("is_stopping", _was_moving and not is_moving)
	var loco_target := 1.0 if is_moving else 0.0
	_current_loco_blend = move_toward(_current_loco_blend, loco_target, blend_lerp_speed * delta)
	_set_locomotion_blend(_current_loco_blend)
	_was_moving = is_moving


func _should_block_horizontal_motion() -> bool:
	return false


func _should_force_idle() -> bool:
	return false


func _get_fallback_move_speed() -> float:
	return move_speed


func _apply_horizontal_motion(is_moving: bool, move_dir: Vector3, delta: float) -> void:
	if anim_tree and is_moving and not _should_block_horizontal_motion():
		var rm_local: Vector3 = anim_tree.get_root_motion_position()
		var rm_basis: Basis = global_transform.basis
		if visual_root:
			rm_basis = visual_root.global_transform.basis
		var rm_world: Vector3 = rm_basis * rm_local
		var rm_velocity: Vector3 = rm_world / maxf(delta, 0.001)
		var rm_speed := Vector2(rm_velocity.x, rm_velocity.z).length()
		if rm_speed >= min_root_motion_speed:
			velocity.x = rm_velocity.x
			velocity.z = rm_velocity.z
		else:
			var fallback_speed := _get_fallback_move_speed()
			velocity.x = move_dir.x * fallback_speed
			velocity.z = move_dir.z * fallback_speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0


func _get_action_root_motion_velocity(delta: float) -> Vector3:
	if delta <= 0.0 or not anim_player:
		return Vector3.ZERO
	var root_motion: Vector3 = anim_player.get_root_motion_position()
	if root_motion.length_squared() <= 0.0000001:
		return Vector3.ZERO
	var root_basis: Basis = global_transform.basis
	if visual_root:
		root_basis = visual_root.global_transform.basis
	var root_world: Vector3 = root_basis * root_motion
	return Vector3(root_world.x / delta, 0.0, root_world.z / delta)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if not nav_agent or not nav_agent.avoidance_enabled:
		return
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()


func _process_idle_look(is_moving: bool, delta: float) -> void:
	if is_moving or _look_timer <= 0.0:
		return
	_look_timer = maxf(_look_timer - delta, 0.0)
	var look_dir := _look_target - global_position
	look_dir.y = 0.0
	if look_dir.length() > 0.1:
		_face_direction(look_dir.normalized(), delta * look_speed / max(rotation_speed, 0.001))


func _face_direction(dir: Vector3, delta: float) -> void:
	if not visual_root:
		return
	var target_angle := atan2(dir.x, dir.z)
	var current_angle := visual_root.rotation.y
	visual_root.rotation.y = lerp_angle(current_angle, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))


func _set_anim_condition(condition: String, value: bool) -> void:
	if not anim_tree:
		return
	var wrapped_path := "parameters/StateMachine/conditions/" + condition
	var base_path := "parameters/conditions/" + condition
	if anim_tree.get(wrapped_path) != null:
		anim_tree.set(wrapped_path, value)
	else:
		anim_tree.set(base_path, value)


func _set_locomotion_blend(value: float) -> void:
	if not anim_tree:
		return
	var wrapped_path := "parameters/StateMachine/Locomotion/blend_position"
	var base_path := "parameters/Locomotion/blend_position"
	if anim_tree.get(wrapped_path) != null:
		anim_tree.set(wrapped_path, value)
	else:
		anim_tree.set(base_path, value)


func _set_combat_blend(value: Vector2) -> void:
	if not anim_tree:
		return
	var wrapped_path := "parameters/StateMachine/Combat/blend_position"
	var base_path := "parameters/Combat/blend_position"
	if anim_tree.get(wrapped_path) != null:
		anim_tree.set(wrapped_path, value)
	else:
		anim_tree.set(base_path, value)


func _get_anim_playback() -> AnimationNodeStateMachinePlayback:
	if not anim_tree:
		return null
	var wrapped: AnimationNodeStateMachinePlayback = anim_tree.get("parameters/StateMachine/playback") as AnimationNodeStateMachinePlayback
	if wrapped:
		return wrapped as AnimationNodeStateMachinePlayback
	return anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback


func _resolve_nodes() -> void:
	visual_root = _resolve_node(visual_root_path, "ybot_root") as Node3D
	anim_tree = _resolve_node(anim_tree_path, "AnimationTree") as AnimationTree
	anim_player = _resolve_node(anim_player_path, "AnimationPlaye	r") as AnimationPlayer
	nav_agent = _resolve_node(nav_agent_path, "NavigationAgent3D") as NavigationAgent3D


func _resolve_node(path: NodePath, fallback_name: String) -> Node:
	if not path.is_empty():
		var node := get_node_or_null(path)
		if node:
			return node
	for child in get_children():
		if child is Node3D or fallback_name == "NavigationAgent3D":
			var found := child.find_child(fallback_name, true, false)
			if found:
				return found
	return find_child(fallback_name, true, false)


func _ensure_foot_ik_node() -> void:
	foot_ik = get_node_or_null(foot_ik_path)
	if foot_ik:
		return
	var ik := Node.new()
	ik.name = "FootIK"
	ik.set_script(FOOT_IK_SCRIPT)
	ik.set("skeleton_path", _get_foot_ik_skeleton_path())
	add_child(ik)
	foot_ik = ik


func _get_foot_ik_skeleton_path() -> NodePath:
	if not visual_root_path.is_empty():
		return NodePath("%s/Armature/Skeleton3D" % str(visual_root_path))
	if visual_root:
		return NodePath("%s/Armature/Skeleton3D" % visual_root.name)
	return ^"Armature/Skeleton3D"


func _update_foot_ik(delta: float) -> void:
	if foot_ik and foot_ik.has_method("update"):
		foot_ik.update(delta)


func _clear_foot_ik_overrides() -> void:
	if foot_ik and foot_ik.has_method("clear_overrides"):
		foot_ik.clear_overrides()
