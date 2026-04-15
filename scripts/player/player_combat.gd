extends Node

enum AttackKind { NONE, LIGHT, HEAVY, KICK }

@export_group("Animations")
@export var light_attack_anim: StringName = &"npc_axe/standing_melee_attack_downward"
@export var heavy_attack_anim: StringName = &"npc_axe/standing_melee_attack_backhand"
@export var kick_attack_anim: StringName = &"npc_axe/standing_melee_attack_kick_ver"
@export var hit_react_left_anim: StringName = &"npc_axe/standing_react_large_from_left"
@export var hit_react_right_anim: StringName = &"npc_axe/standing_react_large_from_right"
@export var hit_react_gut_anim: StringName = &"npc_axe/standing_react_large_gut"
@export var block_idle_anim: StringName = &"npc_axe/standing_block_idle"
@export var block_react_anim: StringName = &"npc_axe/standing_block_react_large"
@export var dodge_forward_anim: StringName = &"player_combat/standing_dodge_forward"
@export var dodge_backward_anim: StringName = &"player_combat/standing_dodge_backward"
@export var dodge_left_anim: StringName = &"player_combat/standing_dodge_left"
@export var dodge_right_anim: StringName = &"player_combat/standing_dodge_right"
@export var dive_roll_anim: StringName = &"player_combat/standing_dive_forward"

@export_group("Combat")
@export var light_damage: float = 18.0
@export var heavy_damage: float = 28.0
@export var kick_damage: float = 10.0
@export var engage_range: float = 2.6
@export var light_range: float = 1.9
@export var heavy_range: float = 2.2
@export var kick_range: float = 1.35
@export var attack_angle_deg: float = 55.0
@export var block_angle_deg: float = 75.0
@export_range(0.0, 1.0) var block_damage_multiplier: float = 0.15

@export_group("Cadence")
@export var light_cooldown: float = 0.7
@export var heavy_cooldown: float = 1.05
@export var kick_cooldown: float = 0.95

@export_group("Hit Windows")
@export_range(0.0, 1.0) var light_active_start_norm: float = 0.24
@export_range(0.0, 1.0) var light_active_end_norm: float = 0.46
@export_range(0.0, 1.0) var heavy_active_start_norm: float = 0.28
@export_range(0.0, 1.0) var heavy_active_end_norm: float = 0.58
@export_range(0.0, 1.0) var kick_active_start_norm: float = 0.3
@export_range(0.0, 1.0) var kick_active_end_norm: float = 0.52

@export_group("Dodge")
@export var dodge_distance: float = 3.4
@export var dive_distance: float = 4.8
@export_range(0.0, 1.0) var dodge_iframe_start_norm: float = 0.08
@export_range(0.0, 1.0) var dodge_iframe_end_norm: float = 0.72
@export_range(0.0, 1.0) var dive_iframe_start_norm: float = 0.05
@export_range(0.0, 1.0) var dive_iframe_end_norm: float = 0.84
@export_range(0.0, 1.0) var dodge_early_exit_norm: float = 0.7  ## Fraction of dodge anim where movement resumes
@export_range(0.0, 1.0) var attack_early_exit_norm: float = 0.85 ## Fraction of attack anim where movement resumes

var _player: CharacterBody3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _weapon_hitbox: Area3D
var _weapon_hit_shape: CollisionShape3D

var _current_attack: AttackKind = AttackKind.NONE
var _attack_elapsed: float = 0.0
var _attack_duration: float = 0.0
var _attack_window_open: bool = false
var _cooldown_remaining: float = 0.0
var _react_lock_remaining: float = 0.0
var _block_react_remaining: float = 0.0
var _dodge_elapsed: float = 0.0
var _dodge_duration: float = 0.0
var _dodge_velocity: Vector3 = Vector3.ZERO
var _dodge_iframe_start: float = 0.0
var _dodge_iframe_end: float = 0.0
var _dodge_movement_ended: bool = false
var _blocking: bool = false
var _hit_targets: Array[Node] = []
var _disabled: bool = false
var _skeleton: Skeleton3D
var _upper_body_indices: Array[int] = []
var _block_local_poses: Dictionary = {}


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if not _player:
		return
	_anim_player = _player.get_node_or_null("xbot_root/AnimationPlayer") as AnimationPlayer
	_anim_tree = _player.get_node_or_null("xbot_root/AnimationTree") as AnimationTree
	var seax := _player.find_child("Seax", true, false)
	if seax:
		_weapon_hitbox = seax.find_child("Hitbox", true, false) as Area3D
	if _weapon_hitbox:
		_weapon_hit_shape = _weapon_hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not _weapon_hitbox.body_entered.is_connected(_on_weapon_body_entered):
			_weapon_hitbox.body_entered.connect(_on_weapon_body_entered)
	_set_weapon_window(false)
	_skeleton = _player.get_node_or_null("xbot_root/Armature/Skeleton3D") as Skeleton3D
	_init_upper_body_bones()
	_cache_block_poses.call_deferred()


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
	var block_anim_name := _resolve_animation_name(block_idle_anim)
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
	if _player.has_method("is_dead") and bool(_player.is_dead()):
		return

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
	return _blocking or _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0 or _block_react_remaining > 0.0 or _dodge_duration > 0.0


func request_attack(heavy: bool) -> bool:
	if _disabled or _blocking or _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0 or _block_react_remaining > 0.0 or _dodge_duration > 0.0 or _cooldown_remaining > 0.0:
		return false
	if _player.has_method("is_weapon_drawn") and not _player.is_weapon_drawn():
		return false
	if _player.has_method("enter_combat_mode"):
		_player.enter_combat_mode()
	var target: CharacterBody3D = _player.ensure_combat_target() as CharacterBody3D
	return _start_attack(AttackKind.HEAVY if heavy else AttackKind.LIGHT, target)


func request_kick() -> bool:
	if _disabled or _blocking or _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0 or _block_react_remaining > 0.0 or _dodge_duration > 0.0 or _cooldown_remaining > 0.0:
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
	if move_dir.length_squared() <= 0.0001:
		return false
	var anim := _get_dodge_animation(move_input, dive)
	if anim.is_empty() or not _anim_player or not _anim_player.has_animation(anim):
		push_warning("[PlayerCombat] Missing dodge animation '%s' on %s" % [anim, _player.name])
		return false
	_blocking = false
	_hit_targets.clear()
	_begin_action_lock()
	var travel_dir := move_dir.normalized()
	if dive and _player.has_method("_face_direction"):
		_player._face_direction(travel_dir, 1.0)
	_anim_player.play(anim, 0.12)
	var anim_res := _anim_player.get_animation(anim)
	_dodge_duration = maxf(anim_res.length if anim_res else 0.45, 0.1)
	_dodge_elapsed = 0.0
	_dodge_movement_ended = false
	_dodge_iframe_start = dive_iframe_start_norm if dive else dodge_iframe_start_norm
	_dodge_iframe_end = dive_iframe_end_norm if dive else dodge_iframe_end_norm
	var distance := dive_distance if dive else dodge_distance
	_dodge_velocity = travel_dir * (distance / _dodge_duration)
	return true


func set_blocking(active: bool) -> void:
	if _disabled or not _player or not _anim_player:
		return
	if _player.has_method("is_dead") and bool(_player.is_dead()):
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
	if _disabled or (_player.has_method("is_dead") and bool(_player.is_dead())):
		return
	if not _anim_player:
		return
	if _current_attack != AttackKind.NONE:
		_finish_attack()
	var anim := _resolve_hit_react(from_world_pos)
	if anim.is_empty() or not _anim_player.has_animation(anim):
		return
	_begin_action_lock()
	_anim_player.play(anim, 0.1)
	var anim_res := _anim_player.get_animation(anim)
	_react_lock_remaining = anim_res.length if anim_res else 0.45


func stop_combat() -> void:
	_disabled = true
	if _current_attack != AttackKind.NONE:
		_set_attack_window(false)
	_current_attack = AttackKind.NONE
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	_react_lock_remaining = 0.0
	_block_react_remaining = 0.0
	_dodge_elapsed = 0.0
	_dodge_duration = 0.0
	_dodge_velocity = Vector3.ZERO
	_dodge_movement_ended = false
	_blocking = false
	_hit_targets.clear()
	clear_block_overlay()
	_finish_action_lock()
	set_physics_process(false)


func get_locked_horizontal_velocity() -> Vector3:
	return _dodge_velocity if _dodge_duration > 0.0 else Vector3.ZERO


func _start_attack(kind: AttackKind, target: CharacterBody3D = null) -> bool:
	if not _anim_player:
		return false
	if is_instance_valid(target):
		var to_target := target.global_position - _player.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001 and _player.has_method("_face_direction"):
			_player._face_direction(to_target.normalized(), 1.0)
	var anim := _get_attack_animation(kind)
	if anim.is_empty() or not _anim_player.has_animation(anim):
		push_warning("[PlayerCombat] Missing attack animation '%s' on %s" % [anim, _player.name])
		return false
	_current_attack = kind
	_attack_elapsed = 0.0
	_attack_window_open = false
	_hit_targets.clear()
	_begin_action_lock()
	_anim_player.play(anim, 0.15)
	var anim_res := _anim_player.get_animation(anim)
	_attack_duration = maxf(anim_res.length if anim_res else 0.5, 0.1)
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

	var start_t := _get_attack_window_start(_current_attack) * _attack_duration
	var end_t := _get_attack_window_end(_current_attack) * _attack_duration
	var should_open := _attack_elapsed >= start_t and _attack_elapsed <= end_t
	if should_open != _attack_window_open:
		_set_attack_window(should_open)
	if _attack_window_open:
		_poll_attack_hits()
	if _attack_elapsed >= _attack_duration * attack_early_exit_norm:
		_finish_attack()


func _update_dodge(delta: float) -> void:
	var speed: float = _anim_player.speed_scale if _anim_player else 1.0
	_dodge_elapsed += delta * speed

	# After early-exit point the player may queue new actions (attacks, blocks).
	if not _dodge_movement_ended and _dodge_elapsed >= _dodge_duration * dodge_early_exit_norm:
		_dodge_movement_ended = true

	# Full clip finished: clean up and hand back to AnimationTree.
	if _dodge_elapsed >= _dodge_duration:
		_dodge_elapsed = 0.0
		_dodge_duration = 0.0
		_dodge_velocity = Vector3.ZERO
		_dodge_iframe_start = 0.0
		_dodge_iframe_end = 0.0
		_dodge_movement_ended = false
		_finish_action_lock()


func _finish_attack() -> void:
	_set_attack_window(false)
	_cooldown_remaining = _get_attack_cooldown(_current_attack)
	_current_attack = AttackKind.NONE
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	_hit_targets.clear()
	_finish_action_lock()


func _begin_action_lock() -> void:
	if _anim_tree:
		_anim_tree.active = false
	if _player.has_method("set_action_locked"):
		_player.set_action_locked(true)


func finish_action_lock() -> void:
	_finish_action_lock()


func _finish_action_lock() -> void:
	_set_weapon_window(false)
	_react_lock_remaining = 0.0
	if _anim_player:
		_anim_player.stop()
	if _player and _player.has_method("set_action_locked"):
		_player.set_action_locked(false)
	if _anim_tree:
		# Pre-set Combat state BEFORE reactivating so the tree doesn't flash
		# the old state (Idle/Locomotion) for a frame before traveling.
		if _player and _player.has_method("is_in_combat_mode") and _player.is_in_combat_mode():
			var playback: AnimationNodeStateMachinePlayback = _anim_tree["parameters/playback"]
			playback.start("Combat", true)
		_anim_tree.active = true


func _maintain_block() -> void:
	var block_anim := _resolve_animation_name(block_idle_anim)
	if not block_anim.is_empty() and _anim_player.current_animation != String(block_anim):
		_anim_player.play(block_anim, 0.08)


func _play_block_idle() -> void:
	var block_anim := _resolve_animation_name(block_idle_anim)
	if block_anim.is_empty() or not _anim_player or not _anim_player.has_animation(block_anim):
		return
	_anim_player.play(block_anim, 0.05)


func _play_block_react() -> void:
	var react_anim := _resolve_animation_name(block_react_anim)
	if react_anim.is_empty() or not _anim_player or not _anim_player.has_animation(react_anim):
		return
	clear_block_overlay()
	_begin_action_lock()
	_anim_player.play(react_anim, 0.08)
	var anim_res := _anim_player.get_animation(react_anim)
	_block_react_remaining = anim_res.length if anim_res else 0.25


func _set_attack_window(active: bool) -> void:
	_attack_window_open = active
	var use_weapon := _current_attack == AttackKind.LIGHT or _current_attack == AttackKind.HEAVY
	_set_weapon_window(active and use_weapon)


func _set_weapon_window(active: bool) -> void:
	if not _weapon_hitbox:
		return
	_weapon_hitbox.monitoring = active
	_weapon_hitbox.collision_mask = 2 if active else 0
	if _weapon_hit_shape:
		_weapon_hit_shape.disabled = not active


func _poll_attack_hits() -> void:
	match _current_attack:
		AttackKind.LIGHT, AttackKind.HEAVY:
			_deal_targeted_weapon_hit()
			_deal_weapon_overlap_hits()
		AttackKind.KICK:
			_deal_kick_hit()


func _deal_targeted_weapon_hit() -> void:
	var target := _get_melee_target_candidate(_get_attack_range(_current_attack))
	if not target or not is_instance_valid(target) or target in _hit_targets:
		return
	if target.has_method("is_dead") and bool(target.is_dead()):
		return
	var to_target: Vector3 = target.global_position - _player.global_position
	to_target.y = 0.0
	if not _is_valid_attack_range(_current_attack, to_target.length()):
		return
	if not _is_facing_target(to_target):
		return
	_try_hit_target(target, _get_attack_damage(_current_attack))


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
		if not _is_facing_target(to_candidate):
			continue
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
	if candidate.has_method("is_dead") and bool(candidate.is_dead()):
		return false
	var to_candidate := candidate.global_position - _player.global_position
	to_candidate.y = 0.0
	return to_candidate.length() <= max_distance


func _deal_weapon_overlap_hits() -> void:
	if not _weapon_hitbox:
		return
	for body in _weapon_hitbox.get_overlapping_bodies():
		_try_hit_target(body, _get_attack_damage(_current_attack))


func _deal_kick_hit() -> void:
	for node in _player.get_tree().get_nodes_in_group("bandit"):
		var target: CharacterBody3D = node as CharacterBody3D
		if not target or not is_instance_valid(target) or target in _hit_targets:
			continue
		if target.has_method("is_dead") and bool(target.is_dead()):
			continue
		var to_target: Vector3 = target.global_position - _player.global_position
		to_target.y = 0.0
		if to_target.length() > kick_range:
			continue
		if not _is_facing_target(to_target):
			continue
		_try_hit_target(target, kick_damage)
		break


func _try_hit_target(body: Node, damage: float) -> void:
	if not body or body == _player or body in _hit_targets:
		return
	if body.has_method("is_dead") and bool(body.is_dead()):
		return
	if not body.is_in_group("bandit"):
		return
	if not body.has_method("take_damage"):
		return
	print("[PlayerCombat] HIT %s for %.1f damage" % [body.name, damage])
	body.take_damage(damage, _player.global_position)
	_hit_targets.append(body)


func _on_weapon_body_entered(body: Node) -> void:
	if not _attack_window_open:
		return
	_try_hit_target(body, _get_attack_damage(_current_attack))


func _is_valid_attack_range(kind: AttackKind, distance: float) -> bool:
	match kind:
		AttackKind.LIGHT:
			return distance <= light_range
		AttackKind.HEAVY:
			return distance <= heavy_range
		AttackKind.KICK:
			return distance <= kick_range
		_:
			return false


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


func _get_attack_animation(kind: AttackKind) -> StringName:
	match kind:
		AttackKind.LIGHT:
			return _resolve_animation_name(light_attack_anim)
		AttackKind.HEAVY:
			return _resolve_animation_name(heavy_attack_anim)
		AttackKind.KICK:
			return _resolve_animation_name(kick_attack_anim)
		_:
			return StringName()


func _get_dodge_animation(move_input: Vector2, dive: bool) -> StringName:
	if dive:
		return _resolve_animation_name(dive_roll_anim)
	if absf(move_input.x) > absf(move_input.y):
		return _resolve_animation_name(dodge_right_anim if move_input.x > 0.0 else dodge_left_anim)
	if move_input.y > 0.0:
		return _resolve_animation_name(dodge_backward_anim)
	return _resolve_animation_name(dodge_forward_anim)


func _resolve_hit_react(from_world_pos: Vector3) -> StringName:
	if from_world_pos == Vector3.INF:
		return _resolve_animation_name(hit_react_gut_anim)
	var local := _player.to_local(from_world_pos)
	if absf(local.x) > absf(local.z):
		return _resolve_animation_name(hit_react_right_anim if local.x >= 0.0 else hit_react_left_anim)
	return _resolve_animation_name(hit_react_gut_anim)


func _resolve_animation_name(raw_name: StringName) -> StringName:
	if not _anim_player:
		return raw_name
	var raw := str(raw_name)
	var candidates: Array[String] = [raw]
	if raw.contains("npc/axe/"):
		candidates.append(raw.replace("npc/axe/", "npc_axe/"))
	if raw.contains("/"):
		candidates.append(raw.replace("/", "_"))
	if raw.begins_with("npc_axe_"):
		candidates.append(raw.replace("npc_axe_", "npc_axe/"))
	if raw.begins_with("player_combat_"):
		candidates.append(raw.replace("player_combat_", "player_combat/"))
	if raw.contains(" "):
		candidates.append(raw.replace(" ", "_"))
	if raw.contains(" from ") or raw.contains(" left") or raw.contains(" right"):
		var normalized := raw.replace(" from ", "_from_")
		normalized = normalized.replace(" left", "_left")
		normalized = normalized.replace(" right", "_right")
		candidates.append(normalized)
		if normalized.begins_with("npc_axe_"):
			candidates.append(normalized.replace("npc_axe_", "npc_axe/"))
	for candidate in candidates:
		var animation_name := StringName(candidate)
		if _anim_player.has_animation(animation_name):
			return animation_name

	var target_key := _normalize_anim_key(raw)
	var best_suffix := StringName()
	for anim_name in _anim_player.get_animation_list():
		var anim_text := str(anim_name)
		var anim_key := _normalize_anim_key(anim_text)
		if anim_key == target_key:
			return anim_name
		if anim_key.ends_with(target_key) or target_key.ends_with(anim_key):
			best_suffix = anim_name
	if not best_suffix.is_empty():
		return best_suffix

	for anim_name in _anim_player.get_animation_list():
		var anim_key := _normalize_anim_key(str(anim_name))
		if target_key.contains("downward") and anim_key.contains("meleeattack") and anim_key.contains("downward"):
			return anim_name
		if target_key.contains("backhand") and anim_key.contains("meleeattack") and anim_key.contains("backhand"):
			return anim_name
		if target_key.contains("kick") and anim_key.contains("kick"):
			return anim_name
		if target_key.contains("reactlarge") and anim_key.contains("react") and anim_key.contains("large"):
			if target_key.contains("gut") and anim_key.contains("gut"):
				return anim_name
			if target_key.contains("left") and anim_key.contains("left"):
				return anim_name
			if target_key.contains("right") and anim_key.contains("right"):
				return anim_name
		if target_key.contains("block") and anim_key.contains("block"):
			return anim_name
		if target_key.contains("dodge") and anim_key.contains("dodge"):
			return anim_name
		if target_key.contains("dive") and anim_key.contains("dive"):
			return anim_name

	return StringName(candidates[-1])


func _normalize_anim_key(value: String) -> String:
	var lowered := value.to_lower()
	var result := ""
	for ch in lowered:
		if ch >= "a" and ch <= "z":
			result += ch
		elif ch >= "0" and ch <= "9":
			result += ch
	return result


func _get_attack_damage(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_damage
		AttackKind.HEAVY:
			return heavy_damage
		AttackKind.KICK:
			return kick_damage
		_:
			return 0.0


func _get_attack_range(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_range
		AttackKind.HEAVY:
			return heavy_range
		AttackKind.KICK:
			return kick_range
		_:
			return engage_range


func _get_attack_cooldown(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_cooldown
		AttackKind.HEAVY:
			return heavy_cooldown
		AttackKind.KICK:
			return kick_cooldown
		_:
			return 0.0


func _get_attack_window_start(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_active_start_norm
		AttackKind.HEAVY:
			return heavy_active_start_norm
		AttackKind.KICK:
			return kick_active_start_norm
		_:
			return 0.0


func _get_attack_window_end(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_active_end_norm
		AttackKind.HEAVY:
			return heavy_active_end_norm
		AttackKind.KICK:
			return kick_active_end_norm
		_:
			return 0.0
