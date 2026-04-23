extends BaseCombatComponent

@export_group("Dodge")
@export var dodge_data: DodgeData
@export var dive_data: DodgeData
@export var dodge_unlock_time: float = 0.8

@export_group("Playback")
@export var action_animation_speed_scale: float = 1.5

@export_group("Block")
@export var block_idle_anim: StringName = &"npc_axe/standing_block_idle"
@export var block_react_anim: StringName = &"npc_axe/standing_block_react_large"
@export var block_angle_deg: float = 75.0
@export_range(0.0, 1.0) var block_damage_multiplier: float = 0.15

@export_group("Input Buffer")
@export var buffer_window: float = 0.4  ## Seconds a buffered input stays valid

@export_group("Stamina")
@export var heavy_stamina_cost_ratio: float = 0.25  ## Fraction of max_stamina drained by Committed Thrust

@export_group("Hit-Stop")
@export var hitstop_duration: float = 0.12        ## Seconds of time-scale freeze
@export var hitstop_time_scale: float = 0.05     ## Engine.time_scale during freeze
@export var hitstop_camera_trauma: float = 0.45   ## Camera shake intensity (0-1)

enum BufferedInput { NONE, LIGHT_ATTACK, HEAVY_ATTACK, KICK, DODGE, DIVE }
var _buffered_input: BufferedInput = BufferedInput.NONE
var _buffer_time_remaining: float = 0.0
var _buffered_move_dir: Vector3 = Vector3.ZERO
var _buffered_move_input: Vector2 = Vector2.ZERO

var _player: CharacterBody3D  ## Alias for _owner_body
var _block_react_remaining: float = 0.0
var _dodge_elapsed: float = 0.0
var _dodge_duration: float = 0.0
var _dodge_iframe_start: float = 0.0
var _dodge_iframe_end: float = 0.0
var _dodge_movement_ended: bool = false
var _dodge_unlock_elapsed: float = 0.0
var _dodge_travel_local: Vector2 = Vector2.ZERO
var _blocking: bool = false
var _pending_block_stagger_pos: Vector3 = Vector3.INF  ## Set when attack hits a block; fires after swing ends
var _xbot_root: Node3D  # xbot_animation_library.gd — has play_action/abort_action
var _skeleton: Skeleton3D
var _anim_tree: AnimationTree
var _upper_body_indices: Array[int] = []
var _block_local_poses: Dictionary = {}


func _setup_combat() -> void:
	_player = _owner_body
	_xbot_root = _player.get_node_or_null("xbot_root") as Node3D
	_anim_player = _player.get_node_or_null("xbot_root/AnimationPlayer") as AnimationPlayer
	_anim_tree = _player.get_node_or_null("xbot_root/AnimationTree") as AnimationTree
	var seax := _player.find_child("Seax", true, false)
	if seax:
		_weapon_hitbox = seax.find_child("Hitbox", true, false) as Area3D
	_wire_weapon_hitbox()
	_skeleton = _player.get_node_or_null("xbot_root/Armature/Skeleton3D") as Skeleton3D
	_init_upper_body_bones()
	_cache_block_poses.call_deferred()


func _init_default_resources() -> void:
	if not light_attack:
		light_attack = AttackData.new()
		light_attack.damage = 18.0
		light_attack.range_m = 3.0
		light_attack.cooldown = 0.15
		light_attack.stamina_cost = 8.0
		light_attack.animation = &"npc_axe/standing_melee_attack_downward"
		light_attack.hit_window_start = 0.24
		light_attack.hit_window_end = 0.46
		light_attack.early_exit_norm = 0.65
	if not heavy_attack:
		heavy_attack = AttackData.new()
		heavy_attack.damage = 28.0
		heavy_attack.range_m = 3.0
		heavy_attack.cooldown = 0.35
		heavy_attack.stamina_cost = 0.0  # Uses heavy_stamina_cost_ratio instead
		heavy_attack.animation = &"npc_axe/standing_melee_attack_backhand"
		heavy_attack.hit_window_start = 0.28
		heavy_attack.hit_window_end = 0.58
		heavy_attack.early_exit_norm = 0.65
	if not kick_attack:
		kick_attack = AttackData.new()
		kick_attack.damage = 10.0
		kick_attack.range_m = 2.0
		kick_attack.cooldown = 0.3
		kick_attack.stamina_cost = 12.0
		kick_attack.animation = &"npc_axe/standing_melee_attack_kick_ver"
		kick_attack.hit_window_start = 0.3
		kick_attack.hit_window_end = 0.52
		kick_attack.early_exit_norm = 0.65
	if not dodge_data:
		dodge_data = DodgeData.new()
		dodge_data.distance = 3.4
		dodge_data.iframe_start_norm = 0.08
		dodge_data.iframe_end_norm = 0.72
		dodge_data.early_exit_norm = 0.7
		dodge_data.forward_anim = &"player_combat/standing_dodge_forward"
		dodge_data.backward_anim = &"player_combat/standing_dodge_backward"
		dodge_data.left_anim = &"player_combat/standing_dodge_left"
		dodge_data.right_anim = &"player_combat/standing_dodge_right"
	if not dive_data:
		dive_data = DodgeData.new()
		dive_data.distance = 4.8
		dive_data.iframe_start_norm = 0.05
		dive_data.iframe_end_norm = 0.84
		dive_data.early_exit_norm = 0.7
		dive_data.forward_anim = &"player_combat/standing_dive_forward"
	if not hit_reacts:
		hit_reacts = HitReactSet.new()
		hit_reacts.from_left = &"npc_axe/standing_react_large_from_left"
		hit_reacts.from_right = &"npc_axe/standing_react_large_from_right"
		hit_reacts.from_front = &"npc_axe/standing_react_large_gut"
		hit_reacts.block_react = &"npc_axe/standing_block_react_large"
func _init_upper_body_bones() -> void:
	if not _skeleton:
		return
	var spine_idx := _skeleton.find_bone("spine")
	if spine_idx < 0:
		return
	_upper_body_indices = _collect_bone_descendants(spine_idx)
	_upper_body_indices.sort()


func _collect_bone_descendants(parent_idx: int) -> Array[int]:
	var result: Array[int] = [parent_idx]
	for child_idx in _skeleton.get_bone_children(parent_idx):
		result.append_array(_collect_bone_descendants(child_idx))
	return result


func _cache_block_poses() -> void:
	if not _anim_player or not _skeleton or _upper_body_indices.is_empty():
		return
	var block_anim_name := AnimationResolver.resolve(block_idle_anim, _anim_player)
	if block_anim_name.is_empty() or not _anim_player.has_animation(block_anim_name):
		return
	var was_tree_active := _anim_tree.active if _anim_tree else false
	if _anim_tree:
		_anim_tree.active = false
	_anim_player.play(block_anim_name)
	_anim_player.seek(0.0, true)
	for bone_idx in _upper_body_indices:
		var parent_idx := _skeleton.get_bone_parent(bone_idx)
		var bone_global := _skeleton.get_bone_global_pose(bone_idx)
		if parent_idx >= 0:
			var parent_global := _skeleton.get_bone_global_pose(parent_idx)
			_block_local_poses[bone_idx] = parent_global.affine_inverse() * bone_global
		else:
			_block_local_poses[bone_idx] = bone_global
	_anim_player.stop()
	if _anim_tree:
		_anim_tree.active = was_tree_active


func apply_block_overlay() -> void:
	if not _blocking or not _skeleton or _block_local_poses.is_empty():
		return
	# Clear overrides first to read clean animated poses
	for bone_idx in _upper_body_indices:
		_skeleton.set_bone_global_pose_override(bone_idx, Transform3D.IDENTITY, 0.0, true)
	# Apply block pose in parent-to-child order
	for bone_idx in _upper_body_indices:
		if not _block_local_poses.has(bone_idx):
			continue
		var parent_idx := _skeleton.get_bone_parent(bone_idx)
		var parent_global: Transform3D
		if parent_idx >= 0:
			parent_global = _skeleton.get_bone_global_pose(parent_idx)
		else:
			parent_global = Transform3D.IDENTITY
		var override: Transform3D = parent_global * Transform3D(_block_local_poses[bone_idx])
		_skeleton.set_bone_global_pose_override(bone_idx, override, 1.0, true)


func clear_block_overlay() -> void:
	if not _skeleton:
		return
	for bone_idx in _upper_body_indices:
		_skeleton.set_bone_global_pose_override(bone_idx, Transform3D.IDENTITY, 0.0, true)


func _physics_process(delta: float) -> void:
	if _disabled or not _player or not _anim_player:
		return
	if _player.is_dead():
		return

	if _buffer_time_remaining > 0.0:
		_buffer_time_remaining -= delta
		if _buffer_time_remaining <= 0.0:
			_buffered_input = BufferedInput.NONE

	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

	if _react_lock_remaining > 0.0:
		_react_lock_remaining = maxf(_react_lock_remaining - delta, 0.0)
		if _react_lock_remaining <= 0.0:
			_finish_action_lock()
		return

	if _block_react_remaining > 0.0:
		_block_react_remaining = maxf(_block_react_remaining - delta, 0.0)
		if _block_react_remaining <= 0.0:
			_finish_action_lock()
		return

	if _dodge_duration > 0.0:
		_update_dodge(delta)
		return

	if _current_attack != AttackKind.NONE:
		_update_attack(delta)
		return

	if _blocking:
		pass  # Block overlay handled via bone pose overrides in _process


func is_blocking() -> bool:
	return _blocking


func is_busy() -> bool:
	return super.is_busy() or _blocking or _block_react_remaining > 0.0 or _dodge_duration > 0.0


func request_attack(heavy: bool) -> bool:
	if _disabled:
		return false
	if _blocking or _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0 or _block_react_remaining > 0.0 or _dodge_duration > 0.0 or _cooldown_remaining > 0.0:
		buffer_attack(heavy)
		return false
	if _player.has_method("is_weapon_drawn") and not _player.is_weapon_drawn():
		return false
	if _player.has_method("enter_combat_mode"):
		_player.enter_combat_mode()
	var target: CharacterBody3D = _player.ensure_combat_target() as CharacterBody3D
	return _start_attack(AttackKind.HEAVY if heavy else AttackKind.LIGHT, target)


func request_kick() -> bool:
	if _disabled:
		return false
	if _blocking or _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0 or _block_react_remaining > 0.0 or _dodge_duration > 0.0 or _cooldown_remaining > 0.0:
		buffer_attack_kind(AttackKind.KICK)
		return false
	if _player.has_method("is_weapon_drawn") and not _player.is_weapon_drawn():
		return false
	if _player.has_method("enter_combat_mode"):
		_player.enter_combat_mode()
	var target: CharacterBody3D = _player.ensure_combat_target() as CharacterBody3D
	return _start_attack(AttackKind.KICK, target)


func request_dodge(move_dir: Vector3, move_input: Vector2, dive: bool) -> bool:
	if _disabled or _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0 or _block_react_remaining > 0.0:
		return false
	if _dodge_duration > 0.0 and not _dodge_movement_ended:
		return false
	var resolved_move_input := move_input
	var travel_dir := move_dir
	if travel_dir.length_squared() <= 0.0001:
		travel_dir = _get_default_dodge_world_direction(dive)
		if not dive and resolved_move_input.length_squared() <= 0.0001 and _player and _player.has_method("get_combat_target"):
			var combat_target := _player.get_combat_target() as CharacterBody3D
			if is_instance_valid(combat_target):
				resolved_move_input = Vector2(0.0, 1.0)
	if travel_dir.length_squared() <= 0.0001:
		return false
	var anim := _get_dodge_animation(resolved_move_input, dive)
	if anim.is_empty() or not _anim_player or not _anim_player.has_animation(anim):
		_finish_action_lock()
		return false
	_blocking = false
	_hit_targets.clear()
	_begin_action_lock()
	_anim_player.speed_scale = 1.0
	travel_dir = travel_dir.normalized()
	var d: DodgeData = dive_data if dive else dodge_data
	_dodge_travel_local = _get_dodge_local_vector(resolved_move_input, dive)
	if dive and _player.has_method("_face_direction"):
		_player._face_direction(travel_dir, 1.0)
	if _xbot_root and _xbot_root.has_method("play_action"):
		if _xbot_root.has_method("set_action_left_arm_filter"):
			_xbot_root.set_action_left_arm_filter(true)
		_xbot_root.play_action(anim, 0.12, 0.2)
	else:
		_anim_player.play(anim, 0.12)
	var anim_res := _anim_player.get_animation(anim)
	_dodge_duration = maxf(anim_res.length if anim_res else 0.45, 0.1)
	_dodge_elapsed = 0.0
	_dodge_movement_ended = false
	_dodge_unlock_elapsed = minf(dodge_unlock_time, _dodge_duration * d.early_exit_norm)
	_dodge_iframe_start = d.iframe_start_norm
	_dodge_iframe_end = d.iframe_end_norm
	return true


func _get_default_dodge_world_direction(dive: bool) -> Vector3:
	if not _player:
		return Vector3.ZERO
	if not dive and _player.has_method("get_combat_target"):
		var combat_target := _player.get_combat_target() as CharacterBody3D
		if is_instance_valid(combat_target):
			var away_from_target := _player.global_position - combat_target.global_position
			away_from_target.y = 0.0
			if away_from_target.length_squared() > 0.0001:
				return away_from_target.normalized()
	var visual := _player.get_node_or_null("xbot_root") as Node3D
	var basis := visual.global_transform.basis if visual else _player.global_transform.basis
	var forward := basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.ZERO
	return forward.normalized()


func _get_dodge_animation(move_input: Vector2, dive: bool) -> StringName:
	if dive:
		return AnimationResolver.resolve(dive_data.forward_anim, _anim_player)
	if absf(move_input.x) > absf(move_input.y):
		return AnimationResolver.resolve(dodge_data.right_anim if move_input.x > 0.0 else dodge_data.left_anim, _anim_player)
	if move_input.y > 0.0:
		return AnimationResolver.resolve(dodge_data.backward_anim, _anim_player)
	return AnimationResolver.resolve(dodge_data.forward_anim, _anim_player)


func _get_dodge_local_vector(move_input: Vector2, dive: bool) -> Vector2:
	if dive:
		return Vector2(0.0, 1.0)
	var dodge_input := Vector2(move_input.x, -move_input.y)
	if dodge_input.length_squared() <= 0.0001:
		return Vector2(0.0, 1.0)
	return dodge_input.normalized()


func set_blocking(active: bool) -> void:
	if _disabled or not _player or not _anim_player:
		return
	if _player.is_dead():
		return
	if active:
		if _blocking or _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0 or _block_react_remaining > 0.0 or _dodge_duration > 0.0:
			return
		_blocking = true
		return
	if not _blocking:
		return
	_blocking = false
	clear_block_overlay()


func process_incoming_hit(amount: float, from_world_pos: Vector3 = Vector3.INF) -> Dictionary:
	var response: Dictionary = {
		"damage": amount,
		"blocked": false,
		"dodged": false,
	}
	if _disabled or amount <= 0.0:
		return response
	if _is_dodge_invulnerable():
		response["damage"] = 0.0
		response["dodged"] = true
		return response
	if _blocking and _can_block_hit(from_world_pos):
		response["damage"] = amount * block_damage_multiplier
		response["blocked"] = true
		_play_block_react()
	return response


func receive_hit(from_world_pos: Vector3 = Vector3.INF) -> void:
	if _disabled or _player.is_dead():
		return
	if not _anim_player:
		return
	_clear_buffer()  # Getting hit invalidates queued actions
	if _current_attack != AttackKind.NONE:
		_finish_attack()
	var anim := _resolve_hit_react_anim(from_world_pos)
	if anim.is_empty() or not _anim_player.has_animation(anim):
		return
	_begin_action_lock()
	_anim_player.speed_scale = get_action_animation_speed_scale()
	if _xbot_root and _xbot_root.has_method("play_action"):
		_xbot_root.play_action(anim, 0.1, 0.25)
	var anim_res := _anim_player.get_animation(anim)
	_react_lock_remaining = (anim_res.length if anim_res else 0.45) / get_action_animation_speed_scale()


func _on_combat_stopped() -> void:
	_clear_buffer()
	_block_react_remaining = 0.0
	_dodge_elapsed = 0.0
	_dodge_duration = 0.0
	_dodge_movement_ended = false
	_dodge_unlock_elapsed = 0.0
	_dodge_travel_local = Vector2.ZERO
	_blocking = false
	clear_block_overlay()


func get_locked_horizontal_velocity() -> Vector3:
	if _dodge_duration <= 0.0 or _dodge_movement_ended or not _player:
		return Vector3.ZERO
	var root_motion := Vector3.ZERO
	if _anim_tree:
		root_motion = _anim_tree.get_root_motion_position()
	if root_motion.length_squared() <= 0.0000001 and _anim_player:
		root_motion = _anim_player.get_root_motion_position()
	var root_distance := Vector2(root_motion.x, root_motion.z).length()
	if root_distance <= 0.0000001:
		return Vector3.ZERO
	var visual := _player.get_node_or_null("xbot_root") as Node3D
	var basis := visual.global_transform.basis if visual else _player.global_transform.basis
	var forward := Vector3(basis.z.x, 0.0, basis.z.z)
	var right := Vector3(-basis.x.x, 0.0, -basis.x.z)
	if forward.length_squared() <= 0.0001 or right.length_squared() <= 0.0001:
		return Vector3.ZERO
	var world_dir := right.normalized() * _dodge_travel_local.x + forward.normalized() * _dodge_travel_local.y
	if world_dir.length_squared() <= 0.0001:
		return Vector3.ZERO
	var delta := get_physics_process_delta_time()
	if delta <= 0.0:
		return Vector3.ZERO
	var speed := root_distance / delta
	world_dir = world_dir.normalized()
	return Vector3(world_dir.x * speed, 0.0, world_dir.z * speed)


func _start_attack(kind: AttackKind, target: CharacterBody3D = null) -> bool:
	var atk := _attack_for(kind)
	var anim := _resolve_attack_anim(atk)
	if anim.is_empty():
		return false
	var stamina_cost := _get_stamina_cost(kind)
	if float(_player.get_stamina()) < stamina_cost:
		return false
	if stamina_cost > 0.0:
		_player.drain_stamina(stamina_cost)
	if is_instance_valid(target):
		var to_target := target.global_position - _player.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001 and _player.has_method("_face_direction"):
			_player._face_direction(to_target.normalized(), 1.0)
	_enter_attack_state(kind, anim)
	# Enable leg filter so locomotion drives legs while moving
	_sync_leg_filter()
	_anim_player.speed_scale = get_action_animation_speed_scale()
	if _xbot_root and _xbot_root.has_method("play_action"):
		_xbot_root.play_action(anim, 0.15, 0.25)
	return true


func _update_attack(delta: float) -> void:
	var speed: float = _anim_player.speed_scale if _anim_player else 1.0
	_attack_elapsed += delta * speed
	var target: CharacterBody3D = _player.get_combat_target() as CharacterBody3D
	if is_instance_valid(target):
		var to_target: Vector3 = target.global_position - _player.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001 and _player.has_method("_face_direction"):
			_player._face_direction(to_target.normalized(), delta)
	_tick_attack_window()
	_sync_leg_filter()
	var atk := _attack_for(_current_attack)
	if _attack_elapsed >= _attack_duration * atk.early_exit_norm:
		_finish_attack()


func _update_dodge(delta: float) -> void:
	var speed: float = _anim_player.speed_scale if _anim_player else 1.0
	_dodge_elapsed += delta * speed

	# After early-exit point the player may queue new actions (attacks, blocks).
	if not _dodge_movement_ended and _dodge_elapsed >= _dodge_unlock_elapsed:
		_dodge_movement_ended = true
		if _player and _player.has_method("set_action_locked"):
			_player.set_action_locked(false)

	# Full clip finished: clean up and hand back to AnimationTree.
	if _dodge_elapsed >= _dodge_duration:
		_dodge_elapsed = 0.0
		_dodge_duration = 0.0
		_dodge_iframe_start = 0.0
		_dodge_iframe_end = 0.0
		_dodge_movement_ended = false
		_dodge_unlock_elapsed = 0.0
		_dodge_travel_local = Vector2.ZERO
		_finish_dodge_action_lock()


func _finish_attack() -> void:
	_disable_leg_filter()
	_clear_attack_state()
	# ── Deferred block stagger: if we hit the bandit's guard, go straight
	#    into stagger without a frame of unlock in between. ──
	if _pending_block_stagger_pos != Vector3.INF:
		var stagger_pos := _pending_block_stagger_pos
		_pending_block_stagger_pos = Vector3.INF
		receive_hit(stagger_pos)
		return  # Skip buffer consume — stagger overrides queued actions
	# No stagger pending — unlock movement and let the swing blend out.
	if _player and _player.has_method("set_action_locked"):
		_player.set_action_locked(false)
	_consume_buffer()


func _begin_action_lock() -> void:
	if _player.has_method("set_action_locked"):
		_player.set_action_locked(true)


func finish_action_lock() -> void:
	_finish_action_lock()


func _finish_action_lock() -> void:
	super._finish_action_lock()
	_disable_leg_filter()
	_disable_left_arm_filter()
	if _xbot_root and _xbot_root.has_method("abort_action"):
		_xbot_root.abort_action()
	if _player and _player.has_method("set_action_locked"):
		_player.set_action_locked(false)
	_consume_buffer()


func _finish_dodge_action_lock() -> void:
	super._finish_action_lock()
	_disable_leg_filter()
	_disable_left_arm_filter()
	if _player and _player.has_method("set_action_locked"):
		_player.set_action_locked(false)
	_consume_buffer()


# ── Leg Filter (locomotion legs during attacks) ─────────────────────────────

## Check if player is moving and toggle the ActionShot leg filter accordingly.
func _sync_leg_filter() -> void:
	if not _xbot_root or not _xbot_root.has_method("set_action_leg_filter"):
		return
	var moving: bool = _player.is_moving if "is_moving" in _player else false
	_xbot_root.set_action_leg_filter(moving)


func _disable_leg_filter() -> void:
	if not _xbot_root or not _xbot_root.has_method("set_action_leg_filter"):
		return
	_xbot_root.set_action_leg_filter(false)


func _disable_left_arm_filter() -> void:
	if not _xbot_root or not _xbot_root.has_method("set_action_left_arm_filter"):
		return
	_xbot_root.set_action_left_arm_filter(false)


func get_action_animation_speed_scale() -> float:
	return maxf(action_animation_speed_scale, 0.01)


func get_locked_animation_speed_scale() -> float:
	if _dodge_duration > 0.0 and not _dodge_movement_ended:
		return 1.0
	return get_action_animation_speed_scale()


# ── Input Buffer ─────────────────────────────────────────────────────────────

func buffer_attack(heavy: bool) -> void:
	_buffered_input = BufferedInput.HEAVY_ATTACK if heavy else BufferedInput.LIGHT_ATTACK
	_buffer_time_remaining = buffer_window


func buffer_attack_kind(kind: AttackKind) -> void:
	match kind:
		AttackKind.LIGHT:
			_buffered_input = BufferedInput.LIGHT_ATTACK
		AttackKind.HEAVY:
			_buffered_input = BufferedInput.HEAVY_ATTACK
		AttackKind.KICK:
			_buffered_input = BufferedInput.KICK
		_:
			return
	_buffer_time_remaining = buffer_window


func buffer_dodge(move_dir: Vector3, move_input: Vector2, dive: bool) -> void:
	_buffered_input = BufferedInput.DIVE if dive else BufferedInput.DODGE
	_buffered_move_dir = move_dir
	_buffered_move_input = move_input
	_buffer_time_remaining = buffer_window


func _consume_buffer() -> void:
	if _buffered_input == BufferedInput.NONE or _buffer_time_remaining <= 0.0:
		return
	if _disabled or _player.is_dead():
		_clear_buffer()
		return
	var intent := _buffered_input
	var move_d := _buffered_move_dir
	var move_i := _buffered_move_input
	_clear_buffer()
	match intent:
		BufferedInput.LIGHT_ATTACK:
			request_attack(false)
		BufferedInput.HEAVY_ATTACK:
			request_attack(true)
		BufferedInput.KICK:
			request_kick()
		BufferedInput.DODGE:
			request_dodge(move_d, move_i, false)
		BufferedInput.DIVE:
			request_dodge(move_d, move_i, true)


func _clear_buffer() -> void:
	_buffered_input = BufferedInput.NONE
	_buffer_time_remaining = 0.0
	_buffered_move_dir = Vector3.ZERO
	_buffered_move_input = Vector2.ZERO


func _maintain_block() -> void:
	var block_anim := AnimationResolver.resolve(block_idle_anim, _anim_player)
	if not block_anim.is_empty() and _anim_player.current_animation != String(block_anim):
		if _xbot_root and _xbot_root.has_method("play_action"):
			_xbot_root.play_action(block_anim, 0.08, 0.2)


func _play_block_idle() -> void:
	var block_anim := AnimationResolver.resolve(block_idle_anim, _anim_player)
	if block_anim.is_empty() or not _anim_player or not _anim_player.has_animation(block_anim):
		return
	_anim_player.speed_scale = get_action_animation_speed_scale()
	if _xbot_root and _xbot_root.has_method("play_action"):
		_xbot_root.play_action(block_anim, 0.05, 0.2)


func _play_block_react() -> void:
	var react_anim := AnimationResolver.resolve(hit_reacts.block_react, _anim_player)
	if react_anim.is_empty() or not _anim_player or not _anim_player.has_animation(react_anim):
		return
	clear_block_overlay()
	_begin_action_lock()
	_anim_player.speed_scale = get_action_animation_speed_scale()
	if _xbot_root and _xbot_root.has_method("play_action"):
		_xbot_root.play_action(react_anim, 0.08, 0.25)
	var anim_res := _anim_player.get_animation(react_anim)
	_block_react_remaining = (anim_res.length if anim_res else 0.25) / get_action_animation_speed_scale()


func _poll_attack_hits() -> void:
	match _current_attack:
		AttackKind.LIGHT, AttackKind.HEAVY:
			_deal_targeted_weapon_hit()
			_deal_weapon_overlap_hits()
		AttackKind.KICK:
			_deal_kick_hit()


func _deal_targeted_weapon_hit() -> void:
	var atk := _attack_for(_current_attack)
	var target := _get_melee_target_candidate(atk.range_m)
	if not target or not is_instance_valid(target) or target in _hit_targets:
		return
	if target is ICombatTarget and target.is_dead():
		return
	var to_target: Vector3 = target.global_position - _player.global_position
	to_target.y = 0.0
	if to_target.length() > atk.range_m:
		return
	if not _is_facing_target(to_target):
		return
	_try_hit_target(target, atk.get_damage())

func _get_melee_target_candidate(max_distance: float) -> CharacterBody3D:
	var locked_target := _player.get_combat_target() as CharacterBody3D
	if _is_valid_melee_target(locked_target, max_distance):
		return locked_target
	var nearest_target: CharacterBody3D = null
	var nearest_dist := INF
	for node in _player.get_tree().get_nodes_in_group("bandit"):
		var candidate := node as CharacterBody3D
		if not _is_valid_melee_target(candidate, max_distance):
			continue
		var to_candidate := candidate.global_position - _player.global_position
		to_candidate.y = 0.0
		var dist := to_candidate.length()
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_target = candidate
	if nearest_target and _player.has_method("enter_combat_mode"):
		_player.enter_combat_mode()
	return nearest_target


func _is_valid_melee_target(candidate: CharacterBody3D, max_distance: float) -> bool:
	if not candidate or not is_instance_valid(candidate):
		return false
	if candidate in _hit_targets:
		return false
	if candidate is ICombatTarget and candidate.is_dead():
		return false
	var to_candidate := candidate.global_position - _player.global_position
	to_candidate.y = 0.0
	return to_candidate.length() <= max_distance


func _deal_kick_hit() -> void:
	for node in _player.get_tree().get_nodes_in_group("bandit"):
		var target: CharacterBody3D = node as CharacterBody3D
		if not target or not is_instance_valid(target) or target in _hit_targets:
			continue
		if target is ICombatTarget and target.is_dead():
			continue
		var to_target: Vector3 = target.global_position - _player.global_position
		to_target.y = 0.0
		if to_target.length() > kick_attack.range_m:
			continue
		if not _is_facing_target(to_target):
			continue
		_try_hit_target(target, kick_attack.get_damage())


func _try_hit_target(body: Node, damage: float) -> void:
	var target := body as CharacterBody3D
	if not target or target == _player or target in _hit_targets:
		return
	if not target.is_in_group("bandit"):
		return
	if not (target is ICombatTarget):
		return
	if target.is_dead():
		return
	var kind_str := "none"
	match _current_attack:
		AttackKind.LIGHT:
			kind_str = "light"
		AttackKind.HEAVY:
			kind_str = "heavy"
		AttackKind.KICK:
			kind_str = "kick"
	print("[PlayerCombat] HIT %s for %.1f damage (%s)" % [target.name, damage, kind_str])
	var result: Dictionary = {}
	if target.has_method("take_combat_damage"):
		result = target.take_combat_damage(damage, _player.global_position, kind_str)
	else:
		target.take_damage(damage, _player.global_position)
	if result.get("blocked", false):
		_pending_block_stagger_pos = target.global_position
	elif result.get("deflected", false):
		if kind_str == "heavy":
			_on_attack_deflected(target)
	elif kind_str == "heavy":
		_trigger_hit_stop()
	_hit_targets.append(target)


func _is_facing_target(to_target: Vector3) -> bool:
	if to_target.length_squared() <= 0.0001:
		return true
	var visual_root: Node3D = _player.get_node_or_null("xbot_root") as Node3D
	if not visual_root:
		return true
	# Model faces +Z at rest — basis.z IS the true forward (not -basis.z).
	var forward: Vector3 = visual_root.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return true
	return forward.normalized().dot(to_target.normalized()) >= cos(deg_to_rad(attack_angle_deg))


func _can_block_hit(from_world_pos: Vector3) -> bool:
	if from_world_pos == Vector3.INF:
		return true
	var visual_root: Node3D = _player.get_node_or_null("xbot_root") as Node3D
	if not visual_root:
		return true
	var to_attacker := from_world_pos - _player.global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() <= 0.0001:
		return true
	# Model faces +Z at rest — basis.z IS the true forward.
	var forward := visual_root.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return true
	return forward.normalized().dot(to_attacker.normalized()) >= cos(deg_to_rad(maxf(block_angle_deg, 110.0)))


func _is_dodge_invulnerable() -> bool:
	if _dodge_duration <= 0.0:
		return false
	var progress := _dodge_elapsed / _dodge_duration
	return progress >= _dodge_iframe_start and progress <= _dodge_iframe_end


# ── Stamina ──────────────────────────────────────────────────────────────────

func _get_stamina_cost(kind: AttackKind) -> float:
	var atk := _attack_for(kind)
	if not atk:
		return 0.0
	# Heavy uses ratio of max_stamina
	if kind == AttackKind.HEAVY and atk.stamina_cost <= 0.0:
		if _player and "max_stamina" in _player:
			return float(_player.max_stamina) * heavy_stamina_cost_ratio
		return 80.0
	return atk.stamina_cost


# ── Deflection ───────────────────────────────────────────────────────────────

func _on_attack_deflected(enemy: Node) -> void:
	## Player attacked a non-vulnerable, aware enemy — they punish us.
	print("[PlayerCombat] DEFLECTED by %s — player staggered!" % enemy.name)
	# Interrupt whatever attack we were doing
	if _current_attack != AttackKind.NONE:
		_finish_attack()
	# Play a heavy hit react on the player (the bandit counter-hits us)
	receive_hit(enemy.global_position if enemy is Node3D else Vector3.INF)


# ── Hit-Stop ─────────────────────────────────────────────────────────────────

var _hitstop_tween: Tween

func _trigger_hit_stop() -> void:
	## Committed Thrust connected — freeze time, shake camera, vibrate controller.
	if _hitstop_tween and _hitstop_tween.is_valid():
		_hitstop_tween.kill()
	Engine.time_scale = hitstop_time_scale
	# Camera trauma
	if _player and _player.has_method("apply_camera_trauma"):
		_player.apply_camera_trauma(hitstop_camera_trauma)
	# Controller vibration
	Input.start_joy_vibration(0, 0.8, 0.8, hitstop_duration)
	# Restore time scale after duration (use real-time, not game-time)
	_hitstop_tween = _player.create_tween() if _player else create_tween()
	_hitstop_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# The tween duration is in game-time, so divide by time_scale to get real-time
	_hitstop_tween.tween_callback(func(): Engine.time_scale = 1.0).set_delay(hitstop_duration / maxf(hitstop_time_scale, 0.001))
