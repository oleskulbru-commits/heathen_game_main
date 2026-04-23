extends "res://scripts/common/icombat_target.gd"
## Player controller built around root-motion locomotion with Witcher 3-style
## orbit camera.  The camera orbits freely around the player via mouse; WASD
## movement is relative to the camera.  The visual mesh rotates to face the
## movement direction independently of the camera.

# ── Exports ──────────────────────────────────────────────────────────────────
@export var mouse_sensitivity: float = 0.0025
@export var gravity_scale: float = 1.35
@export var rotation_speed: float = 10.0
@export var head_track_speed: float = 4.5
@export var head_max_yaw_deg: float = 70.0
@export var head_max_pitch_deg: float = 25.0
@export var head_idle_weight: float = 0.55
@export var head_move_weight: float = 0.12
@export var blend_lerp_speed: float = 8.0
@export_group("Focus Mode")
@export var focus_zoom_fov: float = 35.0
@export var focus_zoom_speed: float = 3.0
@export var focus_arm_length: float = 2.0
@export var heartbeat_sound: AudioStream
@export_group("Combat Mode")
@export var combat_enter_range: float = 10.0
@export var combat_retain_range: float = 12.0
@export var combat_target_angle_deg: float = 75.0
@export var combat_target_grace: float = 1.2
@export var combat_speed_scale: float = 1.5
@export_group("Combat Camera")
@export var lock_on_yaw_speed: float = 3.0   ## How fast yaw tracks the target (rad/s)
@export var lock_on_pitch_speed: float = 1.5 ## How fast pitch nudges toward target
@export var lock_on_pitch_offset: float = -0.12 ## Slight downward bias so camera looks at chest
@export var traversal_shoulder_offset: float = 0.0 ## Centered camera offset outside combat
@export var combat_shoulder_offset: float = 0.9 ## X offset during combat (pushes player to left third)
@export var shoulder_lerp_speed: float = 4.0  ## How fast the offset transitions
@export var combat_yaw_bias: float = 0.18     ## Yaw offset to push enemy to right third (rad)
@export_group("Handheld Shake")
@export var shake_intensity: float = 0.015 ## Max rotation offset in radians (~0.86 deg)
@export var shake_speed: float = 0.00125     ## How fast the noise scrolls
@export_group("Camera Auto-Follow")
@export var follow_yaw_speed: float = 1.5   ## Recentering speed when walking (rad/s)
@export var follow_sprint_speed: float = 3.0 ## Recentering speed when sprinting
@export var follow_mouse_delay: float = 1.0  ## Seconds after last mouse input before recentering
@export var follow_deadzone_deg: float = 10.0 ## Ignore recentering within this angle
@export_group("Weapon Draw / Sheath")
@export var draw_weapon_anim: StringName = &"npc_sword_shield/draw_sword_2"
@export var sheath_weapon_anim: StringName = &"npc_sword_shield/sheath_sword_1"
# ── Node references ──────────────────────────────────────────────────────────
@onready var camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var visual_root: Node3D = $xbot_root
@onready var anim_player: AnimationPlayer = $xbot_root/AnimationPlayer
@onready var anim_tree: AnimationTree = $xbot_root/AnimationTree
@onready var _skeleton: Skeleton3D = $xbot_root/Armature/Skeleton3D
@onready var _foot_ik: Node = $FootIK
@onready var _player_combat: Node = $PlayerCombat

# ── Camera state ─────────────────────────────────────────────────────────────
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _shake_noise: FastNoiseLite
var _shake_time: float = 0.0
var _mouse_idle_time: float = 10.0  ## Starts high so follow works immediately

# ── Head look state ──────────────────────────────────────────────────────────
var _look_chain: Array = []  # [{idx, yaw_frac, pitch_frac}]
var _head_look_current: Vector2 = Vector2.ZERO  # x = pitch, y = yaw (radians)
var _look_weight: float = 0.0

# ── Focus mode ───────────────────────────────────────────────────────────────
signal focus_changed(active: bool)
signal combat_target_changed(target: CharacterBody3D)
signal died()
var _focus_active: bool = false
var _default_fov: float
var _default_arm_length: float
var _default_shoulder_x: float
var _heartbeat_player: AudioStreamPlayer
var _heartbeat_tween: Tween

# ── Player mode ──────────────────────────────────────────────────────────────
enum PlayerMode { TRAVERSAL, STEALTH, COMBAT }
var _mode: PlayerMode = PlayerMode.TRAVERSAL
var _combat_target: CharacterBody3D
var _combat_target_lost_time: float = 0.0
var _attack_hold_time: float = 0.0
var _attack_held: bool = false
@export var heavy_attack_hold_threshold: float = 0.3

# ── Health & Stamina ─────────────────────────────────────────────────────────
signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)

@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_regen_rate: float = 15.0
@export var sprint_stamina_cost: float = 12.0
@export_group("Death")
@export var death_from_front_anim: StringName = &"PlayerDeaths/standing_death_backward_01"
@export var death_from_back_anim: StringName = &"PlayerDeaths/standing_death_forward_01"
@export var death_from_left_anim: StringName = &"PlayerDeaths/standing_death_left_01"
@export var death_from_right_anim: StringName = &"PlayerDeaths/standing_death_right_01"

var _health: float = 100.0
var _stamina: float = 100.0
var is_sprinting: bool = false
var is_moving: bool = false
var _is_dead: bool = false
var _action_locked: bool = false
var _external_locomotion_modifier: float = 1.0
var _weapon_drawn: bool = false
var _draw_sheath_active: bool = false
var _drawing_weapon: bool = false   # true = drawing, false = sheathing (while anim plays)
var _seax_node: Node
var _right_arm_indices: Array[int] = []
var _right_arm_bone_names: Array[String] = []
var _draw_sheath_player: AnimationPlayer

func get_health() -> float:
	return _health

func get_stamina() -> float:
	return _stamina


func drain_stamina(amount: float) -> void:
	if _is_dead or amount <= 0.0:
		return
	_stamina = clampf(_stamina - amount, 0.0, max_stamina)
	stamina_changed.emit(_stamina, max_stamina)

func is_dead() -> bool:
	return _is_dead


func take_damage(amount: float, from_world_pos: Vector3 = Vector3.INF) -> void:
	if _is_dead or amount <= 0.0:
		return
	var blocked := false
	var dodged := false
	if _player_combat and _player_combat.has_method("process_incoming_hit"):
		var response: Dictionary = _player_combat.process_incoming_hit(amount, from_world_pos)
		amount = float(response.get("damage", amount))
		blocked = bool(response.get("blocked", false))
		dodged = bool(response.get("dodged", false))
	if dodged or amount <= 0.0:
		return
	# Enter combat when taking damage from a known source
	if from_world_pos != Vector3.INF:
		_enter_combat_from_damage(from_world_pos)
	_health = clampf(_health - amount, 0.0, max_health)
	health_changed.emit(_health, max_health)
	if _health <= 0.0:
		_die(from_world_pos)
	elif not blocked and _player_combat and _player_combat.has_method("receive_hit"):
		_player_combat.receive_hit(from_world_pos)

func heal(amount: float) -> void:
	if _is_dead or amount <= 0.0:
		return
	_health = clampf(_health + amount, 0.0, max_health)
	health_changed.emit(_health, max_health)

func is_in_stealth() -> bool:
	return _mode == PlayerMode.STEALTH

func is_in_combat_mode() -> bool:
	return _mode == PlayerMode.COMBAT

func is_focused() -> bool:
	return _focus_active

func get_combat_target() -> CharacterBody3D:
	return _combat_target


func enter_combat_mode() -> void:
	if _is_dead:
		return
	if _mode == PlayerMode.STEALTH:
		_set_mode(PlayerMode.TRAVERSAL)
	if _mode != PlayerMode.COMBAT:
		_set_mode(PlayerMode.COMBAT)
	if not _weapon_drawn and not _draw_sheath_active:
		_play_draw_weapon()


func is_action_locked() -> bool:
	return _action_locked


func set_action_locked(value: bool) -> void:
	_action_locked = value
	if value:
		velocity.x = 0.0
		velocity.z = 0.0

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	anim_tree.active = true
	_init_look_chain()
	add_to_group("player")
	health_changed.emit(_health, max_health)
	stamina_changed.emit(_stamina, max_stamina)
	# Focus mode defaults
	_default_fov = _camera.fov
	_default_arm_length = _spring_arm.spring_length
	_default_shoulder_x = traversal_shoulder_offset
	_spring_arm.position.x = _default_shoulder_x
	# Heartbeat audio
	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.bus = &"Master"
	_heartbeat_player.volume_db = -80.0
	add_child(_heartbeat_player)
	# Handheld camera shake noise
	_shake_noise = FastNoiseLite.new()
	_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shake_noise.frequency = 0.8
	_shake_noise.seed = randi()
	# Weapon starts sheathed (hidden)
	_seax_node = find_child("Seax", true, false)
	if _seax_node:
		_seax_node.visible = false
	_init_right_arm_bones()
	_init_draw_sheath_player()

func _unhandled_input(event: InputEvent) -> void:
	# Camera orbit always works, even while action-locked or dead
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * mouse_sensitivity
		_cam_pitch -= event.relative.y * mouse_sensitivity
		_cam_pitch = clampf(_cam_pitch, deg_to_rad(-60.0), deg_to_rad(35.0))
		camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
		_mouse_idle_time = 0.0
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		return
	if _is_dead or _action_locked:
		return
	if event.is_action_pressed("draw_weapon"):
		
		_toggle_weapon()
		return
	if event.is_action_pressed("crouch"):
		_toggle_crouch()

func _physics_process(delta: float) -> void:
	_update_handheld_shake(delta)
	if _is_dead:
		_clear_head_look_overrides()
		if _foot_ik and _foot_ik.has_method("clear_overrides"):
			_foot_ik.clear_overrides()
		if not is_on_floor():
			velocity += get_gravity() * gravity_scale * delta
		else:
			velocity.x = 0.0
			velocity.z = 0.0
		move_and_slide()
		return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := camera_pivot.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var move_dir := cam_right * input.x + cam_forward * -input.y
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()

	_update_combat_target(delta)
	_update_combat_camera(delta)
	_sync_block_state()
	if _action_locked:
		_clear_head_look_overrides()
		anim_player.speed_scale = _get_locked_action_speed_scale()
		# Keep facing the combat target even while action-locked (blocking, etc.)
		if _mode == PlayerMode.COMBAT and is_instance_valid(_combat_target):
			_face_combat_target(delta)
		# Buffer inputs during action lock so queued actions fire on release
		_buffer_inputs_while_locked(delta, input, move_dir)
		if not is_on_floor():
			velocity += get_gravity() * gravity_scale * delta
		var locked_motion := _get_action_root_motion_velocity(delta)
		if _player_combat and _player_combat.has_method("get_locked_horizontal_velocity"):
			var combat_locked_motion: Vector3 = _player_combat.get_locked_horizontal_velocity()
			if combat_locked_motion.length_squared() > 0.0000001:
				locked_motion = combat_locked_motion
		velocity.x = locked_motion.x
		velocity.z = locked_motion.z
		move_and_slide()
		return
	if _player_combat and _player_combat.has_method("request_dodge"):
		if Input.is_action_just_pressed("dodge_modifier"):
			if _player_combat.request_dodge(move_dir, input, false):
				if not is_on_floor():
					velocity += get_gravity() * gravity_scale * delta
				move_and_slide()
				return
		if Input.is_action_just_pressed("jump"):
			if _player_combat.request_dodge(move_dir, input, true):
				if not is_on_floor():
					velocity += get_gravity() * gravity_scale * delta
				move_and_slide()
				return
	if Input.is_action_just_pressed("attack"):
		_attack_held = true
		_attack_hold_time = 0.0
	if _attack_held:
		_attack_hold_time += delta
		if not Input.is_action_pressed("attack"):
			# Released — light attack
			_attack_held = false
			if _player_combat and _player_combat.has_method("request_attack"):
				_player_combat.request_attack(false)
			else:
				_handle_attack_intent()
		elif _attack_hold_time >= heavy_attack_hold_threshold:
			# Held long enough — heavy attack
			_attack_held = false
			if _player_combat and _player_combat.has_method("request_attack"):
				_player_combat.request_attack(true)
			else:
				_handle_attack_intent()
	if Input.is_action_just_pressed("evade") and _player_combat and _player_combat.has_method("request_kick"):
		_player_combat.request_kick()

	# ── Gravity ──────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	# ── Input → world-space move direction (relative to camera) ──────────
	is_moving = move_dir.length() > 0.1
	is_sprinting = is_moving and Input.is_action_pressed("sprint")

	# ── Stamina ─────────────────────────────────────────────────────────
	if is_sprinting:
		_stamina = clampf(_stamina - sprint_stamina_cost * delta, 0.0, max_stamina)
		if _stamina <= 0.0:
			is_sprinting = false
	elif _stamina < max_stamina:
		_stamina = clampf(_stamina + stamina_regen_rate * delta, 0.0, max_stamina)
	stamina_changed.emit(_stamina, max_stamina)

	# ── Sprint exits stealth / combat ───────────────────────────────────
	if is_sprinting and _mode == PlayerMode.STEALTH:
		_set_mode(PlayerMode.TRAVERSAL)
	if is_sprinting and _mode == PlayerMode.COMBAT:
		_exit_combat_mode()

	# ── Rotate visual mesh ───────────────────────────────────────────────
	if _mode == PlayerMode.COMBAT and is_instance_valid(_combat_target):
		_face_combat_target(delta)
	elif is_moving:
		_face_direction(move_dir, delta)

	# ── Camera auto-follow (Witcher 3 style) ─────────────────────────────
	_update_camera_auto_follow(is_moving, is_sprinting, delta)

	# ── Update animation state machine ───────────────────────────────────
	_update_animation(is_moving, is_sprinting, delta, move_dir)

	# ── Apply motion ─────────────────────────────────────────────────────
	_apply_motion(delta, move_dir)

	move_and_slide()

# ── Head look-at ─────────────────────────────────────────────────────────────

func _init_look_chain() -> void:
	# Candidates: [bone_names_to_try, yaw_share, pitch_share]
	# Shares are normalised later so missing bones don't break the split.
	var candidates := [
		[["spine.002", "Spine2", "spine_02", "chest"],  0.12, 0.10],
		[["neck",      "Neck",   "neck_01"],              0.33, 0.35],
		[["head",      "Head"],                             0.55, 0.55],
	]
	_look_chain.clear()
	var total_yaw := 0.0
	var total_pitch := 0.0
	for entry in candidates:
		var idx := -1
		for bone_name in entry[0]:
			idx = _skeleton.find_bone(bone_name)
			if idx >= 0:
				break
		if idx >= 0:
			_look_chain.append({"idx": idx, "yaw_frac": entry[1], "pitch_frac": entry[2]})
			total_yaw += entry[1]
			total_pitch += entry[2]
	# Normalise so fractions always sum to 1.0
	if total_yaw > 0.0:
		for e in _look_chain:
			e.yaw_frac /= total_yaw
			e.pitch_frac /= total_pitch

func _process(delta: float) -> void:
	if _is_dead:
		_clear_head_look_overrides()
		if _draw_sheath_active:
			_cancel_draw_sheath()
		return
	if _draw_sheath_active and _action_locked:
		_cancel_draw_sheath()
	if _action_locked:
		_clear_head_look_overrides()
		if _foot_ik and _foot_ik.has_method("update"):
			_foot_ik.update(delta)
		return
	_update_focus(delta)
	if _foot_ik:
		_foot_ik.update(delta)
	var _is_blocking := _player_combat and _player_combat.has_method("is_blocking") and bool(_player_combat.is_blocking())
	if _is_blocking and _player_combat.has_method("apply_block_overlay"):
		_player_combat.apply_block_overlay()
	elif _draw_sheath_active:
		_clear_head_look_overrides()
	else:
		_apply_head_look(delta)


func _clear_head_look_overrides() -> void:
	if _look_chain.is_empty() or not _skeleton:
		return
	_head_look_current = Vector2.ZERO
	_look_weight = 0.0
	for entry in _look_chain:
		_skeleton.set_bone_global_pose_override(entry.idx, Transform3D.IDENTITY, 0.0, true)


func _get_action_root_motion_velocity(delta: float) -> Vector3:
	if delta <= 0.0:
		return Vector3.ZERO
	var root_motion := Vector3.ZERO
	if anim_tree:
		root_motion = anim_tree.get_root_motion_position()
	if root_motion.length_squared() <= 0.0000001 and anim_player:
		root_motion = anim_player.get_root_motion_position()
	if root_motion.length_squared() <= 0.0000001:
		return Vector3.ZERO
	var root_basis := visual_root.global_transform.basis if visual_root else global_transform.basis
	var root_world := root_basis * root_motion
	return Vector3(root_world.x / delta, 0.0, root_world.z / delta)


func _get_combat_action_speed_scale() -> float:
	if _player_combat and _player_combat.has_method("get_action_animation_speed_scale"):
		return float(_player_combat.get_action_animation_speed_scale())
	return combat_speed_scale


func _get_locked_action_speed_scale() -> float:
	if _player_combat and _player_combat.has_method("get_locked_animation_speed_scale"):
		return float(_player_combat.get_locked_animation_speed_scale())
	return _get_combat_action_speed_scale()

func _apply_head_look(delta: float) -> void:
	if _look_chain.is_empty():
		return

	# ── Target angles: offset between camera look dir and character facing ──
	var cam_fwd := -camera_pivot.global_transform.basis.z
	# Model faces +Z at rest — basis.z IS the true forward.
	var char_fwd := visual_root.global_transform.basis.z

	# Horizontal yaw – signed angle from character forward to camera forward
	var cam_h := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
	var char_h := Vector3(char_fwd.x, 0.0, char_fwd.z)
	if cam_h.length_squared() < 0.001 or char_h.length_squared() < 0.001:
		return
	cam_h = cam_h.normalized()
	char_h = char_h.normalized()
	var target_yaw := cam_h.signed_angle_to(char_h, Vector3.UP)

	# Vertical pitch – how far the camera looks above/below horizontal
	var target_pitch := -asin(clampf(cam_fwd.y, -1.0, 1.0))

	# Clamp to comfortable range
	var max_yaw := deg_to_rad(head_max_yaw_deg)
	var max_pitch := deg_to_rad(head_max_pitch_deg)
	target_yaw = clampf(target_yaw, -max_yaw, max_yaw)
	target_pitch = clampf(target_pitch, -max_pitch, max_pitch)

	# ── Movement dampening – body already faces move dir, reduce tracking ──
	var input_len := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back").length()
	var target_w := lerpf(head_idle_weight, head_move_weight,
		clampf(input_len * 2.0, 0.0, 1.0))
	_look_weight = lerpf(_look_weight, target_w, clampf(3.0 * delta, 0.0, 1.0))

	# Weighted targets
	var w_yaw := target_yaw * _look_weight
	var w_pitch := target_pitch * _look_weight

	# ── Smooth interpolation ────────────────────────────────────────────────
	var t := clampf(head_track_speed * delta, 0.0, 1.0)
	_head_look_current.y = lerp_angle(_head_look_current.y, w_yaw, t)
	_head_look_current.x = lerp_angle(_head_look_current.x, w_pitch, t)
	# Step 1: Clear all overrides so we read the clean animated poses.
	for entry in _look_chain:
		_skeleton.set_bone_global_pose_override(entry.idx, Transform3D.IDENTITY, 0.0, true)

	# Step 2: Read clean animated poses, then apply our rotation on top.
	for entry in _look_chain:
		var bone_yaw: float = _head_look_current.y * entry.yaw_frac
		var bone_pitch: float = _head_look_current.x * entry.pitch_frac
		var bone_pose := _skeleton.get_bone_global_pose(entry.idx)
		# Pre-multiply so rotation happens in skeleton (≈ character) space,
		# independent of each bone's rest orientation.
		var extra := Basis(Vector3.UP, bone_yaw) * Basis(Vector3.RIGHT, bone_pitch)
		var modified := bone_pose
		modified.basis = extra * bone_pose.basis
		_skeleton.set_bone_global_pose_override(entry.idx, modified, 1.0, true)

# ── Focus Mode ───────────────────────────────────────────────────────────────

func _update_focus(delta: float) -> void:
	var wants_focus := Input.is_action_pressed("focus")
	if _mode == PlayerMode.COMBAT:
		wants_focus = false
	elif _player_combat and _player_combat.has_method("is_blocking") and bool(_player_combat.is_blocking()):
		wants_focus = false
	if wants_focus != _focus_active:
		_focus_active = wants_focus
		focus_changed.emit(_focus_active)
		_update_heartbeat()

	var t := clampf(focus_zoom_speed * delta, 0.0, 1.0)
	var target_fov := focus_zoom_fov if _focus_active else _default_fov
	var target_arm := focus_arm_length if _focus_active else _default_arm_length
	_camera.fov = lerpf(_camera.fov, target_fov, t)
	_spring_arm.spring_length = lerpf(_spring_arm.spring_length, target_arm, t)

func _update_heartbeat() -> void:
	if _heartbeat_tween:
		_heartbeat_tween.kill()
	if _focus_active:
		if heartbeat_sound and not _heartbeat_player.playing:
			_heartbeat_player.stream = heartbeat_sound
			_heartbeat_player.play()
		_heartbeat_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		_heartbeat_tween.tween_property(_heartbeat_player, "volume_db", -6.0, 0.6)
	else:
		_heartbeat_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_heartbeat_tween.tween_property(_heartbeat_player, "volume_db", -80.0, 0.4)
		_heartbeat_tween.tween_callback(_heartbeat_player.stop)

# ── Animation ────────────────────────────────────────────────────────────────

var _was_moving := false
var _current_loco_blend: float = 0.0
var _current_crouch_blend: float = 0.0
var _current_combat_blend: Vector2 = Vector2.ZERO

func _update_animation(moving: bool, sprinting: bool, delta: float, move_dir: Vector3) -> void:
	if _mode == PlayerMode.COMBAT:
		# Clear traversal conditions so auto-transitions don't fight travel()
		anim_tree.set("parameters/StateMachine/conditions/is_moving", false)
		anim_tree.set("parameters/StateMachine/conditions/is_stopping", false)
		var is_blocking := _player_combat and _player_combat.has_method("is_blocking") and bool(_player_combat.is_blocking())
		anim_player.speed_scale = _get_combat_action_speed_scale() if is_blocking else combat_speed_scale
		var playback: AnimationNodeStateMachinePlayback = anim_tree["parameters/StateMachine/playback"]
		var current_node := playback.get_current_node()
		if current_node != &"Combat":
			playback.travel("Combat")
		var target_blend := _get_combat_strafe_blend(move_dir) if moving else Vector2.ZERO
		_current_combat_blend = _current_combat_blend.move_toward(target_blend, blend_lerp_speed * delta)
		anim_tree.set("parameters/StateMachine/Combat/blend_position", _current_combat_blend)
		_was_moving = moving
		return

	anim_player.speed_scale = 1.0
	anim_tree.set("parameters/StateMachine/conditions/is_moving", moving)
	anim_tree.set("parameters/StateMachine/conditions/is_stopping", _was_moving and not moving)

	if _mode == PlayerMode.STEALTH:
		var target := 1.0 if moving else 0.0
		_current_crouch_blend = move_toward(_current_crouch_blend, target, blend_lerp_speed * delta)
		anim_tree.set("parameters/StateMachine/CrouchLocomotion/blend_position", _current_crouch_blend)
	else:
		var target := 0.0
		if moving:
			target = 2.0 if sprinting else 1.0
		_current_loco_blend = move_toward(_current_loco_blend, target, blend_lerp_speed * delta)
		anim_tree.set("parameters/StateMachine/Locomotion/blend_position", _current_loco_blend)

	_was_moving = moving

# ── Mode switching ───────────────────────────────────────────────────────────

func _toggle_crouch() -> void:
	if _is_dead:
		return
	if _mode == PlayerMode.COMBAT:
		return
	if _mode == PlayerMode.TRAVERSAL:
		_set_mode(PlayerMode.STEALTH)
	else:
		_set_mode(PlayerMode.TRAVERSAL)

func _set_mode(new_mode: PlayerMode) -> void:
	if new_mode == _mode:
		return
	_mode = new_mode
	var playback: AnimationNodeStateMachinePlayback = anim_tree["parameters/StateMachine/playback"]
	var current := playback.get_current_node()
	if _mode == PlayerMode.COMBAT:
		_current_combat_blend = Vector2.ZERO
		anim_tree.set("parameters/StateMachine/Combat/blend_position", _current_combat_blend)
		playback.travel("Combat")
	elif _mode == PlayerMode.STEALTH:
		if current == &"Locomotion":
			playback.travel("CrouchLocomotion")
		else:
			playback.travel("CrouchIdle")
	else:
		_current_combat_blend = Vector2.ZERO
		anim_tree.set("parameters/StateMachine/Combat/blend_position", _current_combat_blend)
		var wants_move := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1
		if current == &"CrouchLocomotion":
			playback.travel("Locomotion")
		elif wants_move:
			playback.travel("Locomotion")
		else:
			playback.travel("Idle")

# ── Facing ───────────────────────────────────────────────────────────────────

func _face_direction(dir: Vector3, delta: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	var current_angle := visual_root.rotation.y
	visual_root.rotation.y = lerp_angle(current_angle, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))


func _get_combat_strafe_blend(move_dir: Vector3) -> Vector2:
	if move_dir.length_squared() <= 0.0001:
		return Vector2.ZERO
	# Model faces +Z at rest — basis.z IS forward, -basis.x IS right.
	var forward := visual_root.global_transform.basis.z
	forward.y = 0.0
	var right := -visual_root.global_transform.basis.x
	right.y = 0.0
	if forward.length_squared() <= 0.0001 or right.length_squared() <= 0.0001:
		return Vector2.ZERO
	forward = forward.normalized()
	right = right.normalized()
	var raw := Vector2(
		clampf(right.dot(move_dir), -1.0, 1.0),
		clampf(forward.dot(move_dir), -1.0, 1.0)
	)
	# Map circular input into the combat blend-space diamond so diagonals
	# blend between cardinals instead of snapping to one axis.
	var diamond_scale := maxf(absf(raw.x) + absf(raw.y), 1.0)
	return raw / diamond_scale

# ── Root Motion ──────────────────────────────────────────────────────────────

func _apply_motion(delta: float, _move_dir: Vector3) -> void:
	var loco_mod := _get_locomotion_modifier()
	var root_motion := anim_tree.get_root_motion_position()
	root_motion = visual_root.global_transform.basis * root_motion
	root_motion *= loco_mod
	if delta > 0.0:
		velocity.x = root_motion.x / delta
		velocity.z = root_motion.z / delta


func _handle_attack_intent() -> void:
	if _is_dead:
		return
	var target := _acquire_combat_target(combat_enter_range)
	if not target:
		return
	_set_combat_target(target)
	_combat_target_lost_time = 0.0
	if _mode != PlayerMode.COMBAT:
		_set_mode(PlayerMode.COMBAT)


func ensure_combat_target(max_range: float = -1.0) -> CharacterBody3D:
	var target_range := combat_enter_range if max_range < 0.0 else max_range
	var target := _acquire_combat_target(target_range)
	if not target:
		target = _combat_target if is_instance_valid(_combat_target) else null
	if not target:
		return null
	_set_combat_target(target)
	_combat_target_lost_time = 0.0
	if _mode != PlayerMode.COMBAT:
		_set_mode(PlayerMode.COMBAT)
	return target


func _update_combat_target(delta: float) -> void:
	if _is_dead:
		return

	var aggro_range := combat_retain_range if _mode == PlayerMode.COMBAT else combat_enter_range
	var aggro_target := _acquire_aggro_combat_target(aggro_range)
	if _mode != PlayerMode.COMBAT:
		if aggro_target:
			_set_combat_target(aggro_target)
			_combat_target_lost_time = 0.0
			enter_combat_mode()
		return

	if aggro_target:
		_set_combat_target(aggro_target)
		_combat_target_lost_time = 0.0
		return

	var target := _combat_target
	if is_instance_valid(target):
		if target.has_method("is_dead") and bool(target.is_dead()):
			target = null
		else:
			var target_dist := global_position.distance_to(target.global_position)
			if target_dist <= combat_retain_range:
				_combat_target_lost_time = 0.0
				return

	target = _acquire_combat_target(combat_retain_range)
	if target:
		_set_combat_target(target)
		_combat_target_lost_time = 0.0
		return

	_combat_target_lost_time += delta
	if _combat_target_lost_time >= combat_target_grace:
		_exit_combat_mode()


func _acquire_aggro_combat_target(max_range: float) -> CharacterBody3D:
	var best_target: CharacterBody3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("bandit"):
		var candidate := node as CharacterBody3D
		if not _is_valid_combat_candidate(candidate):
			continue
		if not _is_aggroed_enemy(candidate):
			continue
		var dist := global_position.distance_to(candidate.global_position)
		if dist > max_range:
			continue
		if dist < best_dist:
			best_dist = dist
			best_target = candidate
	return best_target


func _acquire_combat_target(max_range: float) -> CharacterBody3D:
	var cam_forward := -camera_pivot.global_transform.basis.z
	cam_forward.y = 0.0
	if cam_forward.length_squared() > 0.0001:
		cam_forward = cam_forward.normalized()
	else:
		cam_forward = -visual_root.global_transform.basis.z
		cam_forward.y = 0.0
		cam_forward = cam_forward.normalized()

	var best_target: CharacterBody3D = null
	var best_score := -INF
	var nearest_target: CharacterBody3D = null
	var nearest_dist := INF
	var min_dot := cos(deg_to_rad(combat_target_angle_deg))
	for node in get_tree().get_nodes_in_group("bandit"):
		var candidate := node as CharacterBody3D
		if not _is_valid_combat_candidate(candidate):
			continue
		var to_target := candidate.global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()
		if dist <= 0.01 or dist > max_range:
			continue
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_target = candidate
		var dir := to_target / dist
		var alignment := cam_forward.dot(dir)
		if alignment < min_dot and dist > 1.75:
			continue
		var score := alignment * 2.5 - (dist / max_range)
		if score > best_score:
			best_score = score
			best_target = candidate
	return best_target if best_target else nearest_target


func _is_valid_combat_candidate(candidate: CharacterBody3D) -> bool:
	if not candidate or not is_instance_valid(candidate):
		return false
	if candidate.has_method("is_dead") and bool(candidate.is_dead()):
		return false
	return true


func _is_aggroed_enemy(candidate: CharacterBody3D) -> bool:
	if not _is_valid_combat_candidate(candidate):
		return false
	var brain := candidate.get_node_or_null("BanditBrain")
	if not brain:
		return false
	# Only treat the enemy as aggroed when fully in combat (alert level 3)
	if brain.has_method("is_aggroed") and bool(brain.is_aggroed()):
		return true
	return false


func _set_combat_target(target: CharacterBody3D) -> void:
	if _combat_target == target:
		return
	_combat_target = target
	combat_target_changed.emit(_combat_target)


func _exit_combat_mode() -> void:
	_set_combat_target(null)
	_combat_target_lost_time = 0.0
	if _mode == PlayerMode.COMBAT:
		_set_mode(PlayerMode.TRAVERSAL)

# ── Weapon Draw / Sheath ─────────────────────────────────────────────────────

func is_weapon_drawn() -> bool:
	return _weapon_drawn


func _toggle_weapon() -> void:
	if _weapon_drawn:
		_play_sheath_weapon()
	else:
		_play_draw_weapon()


func _play_draw_weapon() -> void:
	if _weapon_drawn or _draw_sheath_active:
		return
	if not _draw_sheath_player or not _draw_sheath_player.has_animation(&"draw"):
		_weapon_drawn = true
		if _seax_node:
			_seax_node.visible = true
		return
	_drawing_weapon = true
	_draw_sheath_active = true
	if _seax_node:
		_seax_node.visible = true
	_draw_sheath_player.play_with_capture(&"draw", 0.2)


func _play_sheath_weapon() -> void:
	if not _weapon_drawn or _draw_sheath_active:
		return
	if _mode == PlayerMode.COMBAT:
		return
	if not _draw_sheath_player or not _draw_sheath_player.has_animation(&"sheath"):
		push_warning("[Player] Missing filtered sheath animation")
		_weapon_drawn = false
		if _seax_node:
			_seax_node.visible = false
		return
	_drawing_weapon = false
	_draw_sheath_active = true
	_draw_sheath_player.play_with_capture(&"sheath", 0.2)


func _on_draw_sheath_finished(_anim_name: StringName) -> void:
	_draw_sheath_active = false
	_weapon_drawn = _drawing_weapon
	if not _weapon_drawn and _seax_node:
		_seax_node.visible = false


func _cancel_draw_sheath() -> void:
	if _draw_sheath_player:
		_draw_sheath_player.stop()
	_draw_sheath_active = false
	if _drawing_weapon and _seax_node:
		_seax_node.visible = false


func _init_right_arm_bones() -> void:
	if not _skeleton:
		return
	# Collect right-arm chain
	for candidate in ["shoulder.R", "arm.R", "upper_arm.R", "UpperArm.R", "RightArm", "right_upper_arm"]:
		var idx := _skeleton.find_bone(candidate)
		if idx >= 0:
			_right_arm_indices = _collect_bone_descendants_sorted(idx)
			for bone_idx in _right_arm_indices:
				_right_arm_bone_names.append(_skeleton.get_bone_name(bone_idx))
			break
	# Add spine chain (above hips) for upper-body blend
	for spine_bone in ["spine", "spine1", "spine2", "neck", "head", "headtop_end",
			"Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop_End"]:
		var idx := _skeleton.find_bone(spine_bone)
		if idx >= 0 and spine_bone not in _right_arm_bone_names:
			_right_arm_bone_names.append(spine_bone)
	if _right_arm_bone_names.is_empty():
		push_warning("[DrawSheath] Could not find right arm or spine bones.")


func _collect_bone_descendants_sorted(parent_idx: int) -> Array[int]:
	var result: Array[int] = [parent_idx]
	for child_idx in _skeleton.get_bone_children(parent_idx):
		result.append_array(_collect_bone_descendants_sorted(child_idx))
	result.sort()
	return result


func _init_draw_sheath_player() -> void:
	_draw_sheath_player = AnimationPlayer.new()
	_draw_sheath_player.name = "DrawSheathPlayer"
	visual_root.add_child(_draw_sheath_player)
	_draw_sheath_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	_draw_sheath_player.animation_finished.connect(_on_draw_sheath_finished)
	var lib := AnimationLibrary.new()
	var draw_filtered := _create_arm_filtered_animation(draw_weapon_anim)
	if draw_filtered:
		lib.add_animation(&"draw", draw_filtered)
	var sheath_filtered := _create_arm_filtered_animation(sheath_weapon_anim)
	if sheath_filtered:
		lib.add_animation(&"sheath", sheath_filtered)
	_draw_sheath_player.add_animation_library(&"", lib)


func _create_arm_filtered_animation(source_name: StringName) -> Animation:
	if not anim_player.has_animation(source_name):
		push_warning("[Player] Source animation '%s' not found for arm filter" % source_name)
		return null
	var source := anim_player.get_animation(source_name)
	if not source:
		return null
	var filtered := Animation.new()
	filtered.length = source.length
	filtered.loop_mode = source.loop_mode
	for t in source.get_track_count():
		var path_str := str(source.track_get_path(t))
		var colon := path_str.rfind(":")
		if colon < 0:
			continue
		var bone_name := path_str.substr(colon + 1)
		if bone_name not in _right_arm_bone_names:
			continue
		var idx := filtered.add_track(source.track_get_type(t))
		filtered.track_set_path(idx, source.track_get_path(t))
		filtered.track_set_interpolation_type(idx, source.track_get_interpolation_type(t))
		for k in source.track_get_key_count(t):
			filtered.track_insert_key(
				idx,
				source.track_get_key_time(t, k),
				source.track_get_key_value(t, k),
				source.track_get_key_transition(t, k)
			)
	if filtered.get_track_count() == 0:
		push_warning("[Player] No right-arm tracks found in '%s' (arm bones: %s)" % [source_name, _right_arm_bone_names])
		return null
	return filtered

func _face_combat_target(delta: float) -> void:
	if not is_instance_valid(_combat_target):
		return
	var to_target := _combat_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return
	_face_direction(to_target.normalized(), delta)


func _update_handheld_shake(delta: float) -> void:
	_shake_time += delta * shake_speed
	var yaw_offset := _shake_noise.get_noise_2d(_shake_time * 80.0, 0.0) * shake_intensity
	var pitch_offset := _shake_noise.get_noise_2d(0.0, _shake_time * 80.0) * shake_intensity
	var roll_offset := _shake_noise.get_noise_2d(_shake_time * 60.0, _shake_time * 60.0) * shake_intensity * 0.5
	_camera.rotation = Vector3(pitch_offset, yaw_offset, roll_offset)


func _update_camera_auto_follow(moving: bool, sprinting: bool, delta: float) -> void:
	_mouse_idle_time += delta
	# Skip when: not moving, in combat (lock-on handles it), or mouse was used recently
	if not moving:
		return
	if _mode == PlayerMode.COMBAT:
		return
	if _mouse_idle_time < follow_mouse_delay:
		return
	# Target yaw: behind the character (visual_root faces +Z)
	var char_forward := visual_root.global_transform.basis.z
	char_forward.y = 0.0
	if char_forward.length_squared() < 0.001:
		return
	var desired_yaw := atan2(-char_forward.x, -char_forward.z)
	var yaw_diff := angle_difference(_cam_yaw, desired_yaw)
	# Deadzone — don't recenter if already close enough
	if abs(yaw_diff) < deg_to_rad(follow_deadzone_deg):
		return
	var speed := follow_sprint_speed if sprinting else follow_yaw_speed
	_cam_yaw += yaw_diff * clampf(speed * delta, 0.0, 1.0)
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _update_combat_camera(delta: float) -> void:
	# Shoulder offset — smooth transition in/out of combat
	var target_x := combat_shoulder_offset if _mode == PlayerMode.COMBAT else _default_shoulder_x
	_spring_arm.position.x = lerpf(_spring_arm.position.x, target_x, clampf(shoulder_lerp_speed * delta, 0.0, 1.0))
	if _mode != PlayerMode.COMBAT or not is_instance_valid(_combat_target):
		return
	# Target point: enemy chest height
	var target_pos := _combat_target.global_position + Vector3(0.0, 1.2, 0.0)
	var to_target := target_pos - camera_pivot.global_position
	# Yaw: angle on the XZ plane, biased to place enemy on right third
	var desired_yaw := atan2(-to_target.x, -to_target.z) + combat_yaw_bias
	var yaw_diff := angle_difference(_cam_yaw, desired_yaw)
	_cam_yaw += yaw_diff * clampf(lock_on_yaw_speed * delta, 0.0, 1.0)
	# Pitch: vertical angle toward target
	var horizontal_dist := Vector2(to_target.x, to_target.z).length()
	var desired_pitch := atan2(to_target.y, horizontal_dist) + lock_on_pitch_offset
	desired_pitch = clampf(desired_pitch, deg_to_rad(-60.0), deg_to_rad(35.0))
	var pitch_diff := angle_difference(_cam_pitch, desired_pitch)
	_cam_pitch += pitch_diff * clampf(lock_on_pitch_speed * delta, 0.0, 1.0)
	_cam_pitch = clampf(_cam_pitch, deg_to_rad(-60.0), deg_to_rad(35.0))
	camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)


func _enter_combat_from_damage(from_world_pos: Vector3) -> void:
	if is_instance_valid(_combat_target):
		if _mode != PlayerMode.COMBAT:
			enter_combat_mode()
		return
	var best: CharacterBody3D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("bandit"):
		var candidate := node as CharacterBody3D
		if not _is_valid_combat_candidate(candidate):
			continue
		var dist := candidate.global_position.distance_to(from_world_pos)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	if best:
		_set_combat_target(best)
		_combat_target_lost_time = 0.0
		enter_combat_mode()


func _buffer_inputs_while_locked(delta: float, input: Vector2, move_dir: Vector3) -> void:
	if not _player_combat:
		return
	# Buffer dodge during action lock
	if _player_combat.has_method("buffer_dodge"):
		if Input.is_action_just_pressed("dodge_modifier"):
			_player_combat.buffer_dodge(move_dir, input, false)
			return
		if Input.is_action_just_pressed("jump"):
			_player_combat.buffer_dodge(move_dir, input, true)
			return
	# Buffer attack — track hold for heavy vs light
	if Input.is_action_just_pressed("attack"):
		_attack_held = true
		_attack_hold_time = 0.0
	if _attack_held:
		_attack_hold_time += delta
		if not Input.is_action_pressed("attack"):
			_attack_held = false
			if _player_combat.has_method("buffer_attack"):
				_player_combat.buffer_attack(false)
		elif _attack_hold_time >= heavy_attack_hold_threshold:
			_attack_held = false
			if _player_combat.has_method("buffer_attack"):
				_player_combat.buffer_attack(true)
	# Buffer kick
	if Input.is_action_just_pressed("evade") and _player_combat.has_method("request_kick"):
		_player_combat.request_kick()


func _sync_block_state() -> void:
	if not _player_combat or not _player_combat.has_method("set_blocking"):
		return
	if not Input.is_action_pressed("focus"):
		_player_combat.set_blocking(false)
		return
	# Blocking is only available in combat mode
	if _mode != PlayerMode.COMBAT:
		_player_combat.set_blocking(false)
		return
	if not is_instance_valid(_combat_target):
		ensure_combat_target()
	_player_combat.set_blocking(true)


# ── Terrain locomotion helpers ───────────────────────────────────────────────

func _get_locomotion_modifier() -> float:
	var loco_node := get_node_or_null("TerrainLocomotion")
	var terrain_modifier := 1.0
	if loco_node and "locomotion_modifier" in loco_node:
		terrain_modifier = loco_node.locomotion_modifier
	return terrain_modifier * _external_locomotion_modifier


func set_external_locomotion_modifier(value: float) -> void:
	_external_locomotion_modifier = maxf(value, 0.0)


func clear_external_locomotion_modifier() -> void:
	_external_locomotion_modifier = 1.0


func _get_stamina_mult() -> float:
	var loco_node := get_node_or_null("TerrainLocomotion")
	if loco_node and "stamina_mult" in loco_node:
		return loco_node.stamina_mult
	return 1.0


func _die(from_world_pos: Vector3 = Vector3.INF) -> void:
	if _is_dead:
		return
	_is_dead = true
	_action_locked = true
	is_sprinting = false
	is_moving = false
	velocity = Vector3.ZERO
	_focus_active = false
	_exit_combat_mode()
	_update_heartbeat()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if anim_tree:
		anim_tree.active = false
	if _player_combat and _player_combat.has_method("stop_combat"):
		_player_combat.stop_combat()
	var death_anim := _resolve_death_animation(from_world_pos)
	if anim_player and anim_player.has_animation(death_anim):
		anim_player.play(death_anim, 0.08)
	died.emit()


func _resolve_death_animation(from_world_pos: Vector3) -> StringName:
	if from_world_pos == Vector3.INF:
		var defaults: Array[StringName] = [death_from_front_anim, death_from_back_anim, death_from_left_anim, death_from_right_anim]
		for candidate in defaults:
			candidate = _resolve_loaded_death_animation(candidate)
			if anim_player and anim_player.has_animation(candidate):
				return candidate
		return death_from_front_anim
	var local := to_local(from_world_pos)
	if absf(local.x) > absf(local.z):
		if local.x >= 0.0:
			var right_alt := _resolve_loaded_death_animation(&"PlayerDeaths/standing_death_right_02")
			if anim_player and anim_player.has_animation(right_alt):
				return right_alt
			return _resolve_loaded_death_animation(death_from_right_anim)
		var left_alt := _resolve_loaded_death_animation(&"PlayerDeaths/standing_death_left_02")
		if anim_player and anim_player.has_animation(left_alt):
			return left_alt
		return _resolve_loaded_death_animation(death_from_left_anim)
	return _resolve_loaded_death_animation(death_from_front_anim if local.z < 0.0 else death_from_back_anim)


func _resolve_loaded_death_animation(anim_name: StringName) -> StringName:
	if not anim_player:
		return anim_name
	var raw := str(anim_name)
	var candidates: Array[String] = [raw]
	if raw.contains("PlayerDeaths/"):
		candidates.append(raw.replace("PlayerDeaths/", "player_deaths/"))
	elif raw.contains("player_deaths/"):
		candidates.append(raw.replace("player_deaths/", "PlayerDeaths/"))
	for candidate in candidates:
		var animation_name := StringName(candidate)
		if anim_player.has_animation(animation_name):
			return animation_name
	return anim_name
