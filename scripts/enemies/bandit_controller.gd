extends "res://scripts/common/humanoid_controller.gd"
## Basic bandit controller.  Uses the ybot_root skin with the same animation
## library and AnimationTree state machine as the player.  Movement is driven
## by AI (NavigationAgent3D) instead of player input.

signal health_changed(current: float, maximum: float)
signal died()

# Phase 3: per-alert-level movement speeds
@export var speed_curious: float = 3.0    ## cautious walk when curious
@export var speed_alert: float = 4.5      ## jog when actively searching
@export var speed_combat: float = 6.0     ## sprint when far from the player
@export var chase_stop_distance: float = 1.6
@export var chase_resume_distance: float = 2.2
@export var chase_walk_distance: float = 3.0
@export var chase_jog_distance: float = 3.5
@export var chase_run_distance: float = 14.0

## Maximum distance the bandit is allowed to travel from his spawn point.
@export var leash_radius: float = 100.0
@export_group("Vitals")
@export var max_health: float = 65.0
@export_group("Death")
@export var death_anims: DeathAnimationSet

# Idle variety
var _idle_variant_timer: float = 0.0
var _brain: Node
var _torch_search: Node
var _combat_holding_position: bool = false
var _health: float = 0.0
var _is_dead: bool = false
var _health_bar: Node3D
var _current_combat_blend: Vector2 = Vector2.ZERO
var _in_combat_tree: bool = false
var _fsm: BanditStateMachine


func _on_controller_ready() -> void:
	_init_default_death_anims()
	_health = max_health
	if not is_in_group("bandit"):
		add_to_group("bandit")
	_brain = get_node_or_null("BanditBrain")
	_torch_search = get_node_or_null("BanditTorchSearch")
	if _brain and _brain.has_signal("heard_noise"):
		_brain.heard_noise.connect(look_toward)
	if _brain and _brain.has_signal("alert_level_changed"):
		_brain.alert_level_changed.connect(_on_alert_level_changed)
	# Spawn the FSM
	_fsm = BanditStateMachine.new()
	_fsm.name = "BanditFSM"
	add_child(_fsm)
	# Wire brain signals to FSM
	if _brain:
		if _brain.has_signal("entered_combat"):
			_brain.entered_combat.connect(_on_brain_entered_combat)
		if _brain.has_signal("heard_noise"):
			_brain.heard_noise.connect(_on_brain_heard_noise)
		if _brain.has_signal("alert_level_changed"):
			_brain.alert_level_changed.connect(_on_brain_alert_changed)
	_spawn_health_bar()
	_spawn_heart_indicator()
	health_changed.emit(_health, max_health)


func _before_move(_delta: float) -> void:
	if _is_dead:
		return
	if is_action_locked():
		return
	if global_position.distance_to(home_position) > leash_radius:
		if _brain and _brain.has_method("reset_alert"):
			_brain.reset_alert()
		set_target_position(home_position)
		return
	_update_combat_pursuit()


func _update_combat_pursuit() -> void:
	if _is_dead:
		_combat_holding_position = false
		return
	if _current_alert < 3 or not _brain:
		_combat_holding_position = false
		return
	if _torch_search and _torch_search.has_method("is_searching") and _torch_search.is_searching():
		_combat_holding_position = false
		return
	if not _brain.has_method("has_visual_contact") or not _brain.has_method("get_player_position"):
		_combat_holding_position = false
		return
	if not _brain.has_visual_contact():
		_combat_holding_position = false
		_target_speed = speed_combat
		return
	var player_pos: Vector3 = _brain.get_player_position()
	if player_pos == Vector3.INF:
		_combat_holding_position = false
		return
	var to_player := player_pos - global_position
	to_player.y = 0.0
	var distance := to_player.length()
	if _combat_holding_position:
		if distance <= chase_resume_distance:
			_target_speed = 0.0
			clear_target()
			look_toward(player_pos)
			return
		_combat_holding_position = false
	_target_speed = _get_chase_speed_for_distance(distance)
	if distance <= chase_stop_distance or to_player.length_squared() <= 0.0001:
		_combat_holding_position = true
		_target_speed = 0.0
		clear_target()
		look_toward(player_pos)
		return
	set_target_position(player_pos - to_player.normalized() * chase_stop_distance)


func _get_chase_speed_for_distance(distance: float) -> float:
	if distance <= chase_stop_distance:
		return 0.0
	if distance <= chase_walk_distance:
		return lerpf(0.0, speed_curious, _distance_range_t(distance, chase_stop_distance, chase_walk_distance))
	if distance <= chase_jog_distance:
		return lerpf(speed_curious, speed_alert, _distance_range_t(distance, chase_walk_distance, chase_jog_distance))
	if distance <= chase_run_distance:
		return lerpf(speed_alert, speed_combat, _distance_range_t(distance, chase_jog_distance, chase_run_distance))
	return speed_combat


func _distance_range_t(value: float, start: float, finish: float) -> float:
	var span := maxf(finish - start, 0.001)
	return clampf((value - start) / span, 0.0, 1.0)


func set_target_position(pos: Vector3) -> void:
	var offset := pos - home_position
	if offset.length() > leash_radius:
		pos = home_position + offset.normalized() * leash_radius
	super.set_target_position(pos)


func _on_alert_level_changed(level: int) -> void:
	set_alert_level(level)
	if _health_bar:
		_health_bar.call("set_persistent_visible", level >= 3 and not _is_dead)
		if level >= 3:
			_health_bar.call("show_temporarily", 2.0)
	match level:
		1: _target_speed = speed_curious
		2: _target_speed = speed_alert
		3: _target_speed = speed_combat


# ── Brain → FSM signal bridges ──────────────────────────────────────────────

func _on_brain_entered_combat() -> void:
	if _fsm:
		_fsm.on_player_spotted()


func _on_brain_heard_noise(source_pos: Vector3) -> void:
	if _fsm:
		_fsm.on_noise_heard(source_pos)


func _on_brain_alert_changed(level: int) -> void:
	if not _fsm:
		return
	# Sync FSM with brain alert level changes
	if level >= 3:
		_fsm.on_player_spotted()
	elif level == 0:
		# Only return to patrol if we're in investigate/curious
		if _fsm.current_state_name in [&"investigate", &"curious"]:
			_fsm.change_state(&"patrol")


func get_health() -> float:
	return _health


func is_dead() -> bool:
	return _is_dead


func get_fsm() -> BanditStateMachine:
	return _fsm


func get_weapon_component():
	var combat := get_node_or_null("BanditCombat")
	if combat and combat.has_method("get_weapon_component"):
		return combat.get_weapon_component()
	return null


func has_weapon() -> bool:
	var weapon = get_weapon_component()
	return weapon != null and bool(weapon.get("has_weapon"))


func take_damage(amount: float, from_world_pos: Vector3 = Vector3.INF) -> void:
	## Legacy flat-damage path (environmental, fall damage, etc.)
	if _is_dead or amount <= 0.0:
		return
	_health = clampf(_health - amount, 0.0, max_health)
	health_changed.emit(_health, max_health)
	if _health_bar:
		_health_bar.call("set_health_ratio", _health / maxf(max_health, 0.001))
		_health_bar.call("show_temporarily", 2.0)
	if _health <= 0.0:
		_die(from_world_pos)
		return
	if _brain and from_world_pos != Vector3.INF and _brain.has_method("force_combat"):
		_brain.force_combat(from_world_pos)
	var combat := get_node_or_null("BanditCombat")
	if combat and combat.has_method("receive_hit"):
		combat.receive_hit(from_world_pos)


func take_combat_damage(amount: float, from_world_pos: Vector3, attack_kind: String) -> Dictionary:
	## Player melee hit — routes through the FSM vulnerability system.
	## Returns { "deflected": bool } so the player can react.
	var result := { "deflected": false }
	if _is_dead or amount <= 0.0:
		return result

	var combat := get_node_or_null("BanditCombat")

	# ── Fatally wounded: any hit = mercy kill ────────────────────────────
	if _fsm and _fsm.current_state_name == &"fatally_wounded":
		if _fsm.has_method("on_silenced"):
			_fsm.on_silenced()
		return result

	# ── Blocking check (before vulnerability gate) ──────────────────────
	if combat and combat.has_method("is_blocking") and combat.is_blocking():
		if attack_kind == "heavy" and combat.has_method("on_block_heavy_hit"):
			combat.on_block_heavy_hit()
		elif combat.has_method("on_block_light_hit"):
			combat.on_block_light_hit()
		result["blocked"] = true
		return result

	# ── Poise check — heavy wind-up absorbs light hits ──────────────────
	if attack_kind == "light" and combat and combat.has_method("has_poise") and combat.has_poise():
		return result

	# ── Heavy attack (Committed Thrust) routing ─────────────────────────
	if attack_kind == "heavy":
		if _fsm and _fsm.current_state_name in [&"deep_stagger", &"micro_stagger"]:
			# 2nd thrust on staggered enemy → fatal blow
			_fsm.change_state(&"fatally_wounded")
			_update_health_bar()
			return result
		if _fsm and _fsm.is_vulnerable():
			# 1st thrust on vulnerable enemy → deep stagger (applies 50% max HP internally)
			_fsm.change_state(&"deep_stagger")
			_update_health_bar()
			return result
		# Not vulnerable → deflected
		result["deflected"] = true
		_ensure_combat_from_hit(from_world_pos)
		return result

	# ── Light attack routing ────────────────────────────────────────────
	if attack_kind == "light":
		if _fsm and _fsm.current_state_name in [&"deep_stagger", &"micro_stagger"]:
			# Light on staggered → micro_stagger (resets timer, keeps combo alive)
			_fsm.change_state(&"micro_stagger")
			_apply_light_damage(amount)
			if combat and combat.has_method("register_light_hit_received"):
				combat.register_light_hit_received()
			return result
		if _fsm and _fsm.is_vulnerable():
			# Light on other vulnerable state → micro_stagger + damage
			_fsm.change_state(&"micro_stagger")
			_apply_light_damage(amount)
			return result
		# Not vulnerable → deflected
		result["deflected"] = true
		_ensure_combat_from_hit(from_world_pos)
		return result

	# ── Kick routing ────────────────────────────────────────────────────
	if attack_kind == "kick":
		# Kicks always connect — apply damage and knockback
		_apply_light_damage(amount)
		_ensure_combat_from_hit(from_world_pos)
		if combat and combat.has_method("receive_hit"):
			combat.receive_hit(from_world_pos)
		return result

	# ── Fallback ────────────────────────────────────────────────────────
	if _fsm and not _fsm.is_vulnerable():
		result["deflected"] = true
		_ensure_combat_from_hit(from_world_pos)
		return result
	_apply_light_damage(amount)
	return result


func _apply_light_damage(amount: float) -> void:
	_health = clampf(_health - amount, 0.0, max_health)
	health_changed.emit(_health, max_health)
	_update_health_bar()


func _update_health_bar() -> void:
	if _health_bar:
		_health_bar.call("set_health_ratio", _health / maxf(max_health, 0.001))
		_health_bar.call("show_temporarily", 2.0)


func _ensure_combat_from_hit(from_world_pos: Vector3) -> void:
	if _brain and from_world_pos != Vector3.INF and _brain.has_method("force_combat"):
		_brain.force_combat(from_world_pos)


func _die(from_world_pos: Vector3 = Vector3.INF) -> void:
	if _is_dead:
		return
	_is_dead = true
	_health = 0.0
	_target_speed = 0.0
	_combat_holding_position = false
	clear_target()
	velocity = Vector3.ZERO
	remove_from_group("bandit")
	if _health_bar:
		_health_bar.call("hide_immediately")
	if anim_tree:
		anim_tree.active = false
	set_action_locked(true)
	var combat := get_node_or_null("BanditCombat")
	if combat and combat.has_method("stop_combat"):
		combat.stop_combat()
	for node_name in ["BanditBrain", "BanditPerception", "BanditTorchSearch", "BanditPatrol", "BanditBodyDetector", "BanditDebugVision"]:
		var node := get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is VisualInstance3D:
				node.visible = false
	var death_anim := _resolve_death_animation(from_world_pos)
	if anim_player and anim_player.has_animation(death_anim):
		anim_player.play(death_anim, 0.08)
	died.emit()


func _init_default_death_anims() -> void:
	if not death_anims:
		death_anims = DeathAnimationSet.new()
		death_anims.from_front = &"PlayerDeaths/standing_death_backward_01"
		death_anims.from_back = &"PlayerDeaths/standing_death_forward_01"
		death_anims.from_left = &"PlayerDeaths/standing_death_left_01"
		death_anims.from_right = &"PlayerDeaths/standing_death_right_01"


func _resolve_death_animation(from_world_pos: Vector3) -> StringName:
	var local := to_local(from_world_pos) if from_world_pos != Vector3.INF else Vector3.INF
	var raw := death_anims.resolve(local)
	var resolved := AnimationResolver.resolve(raw, anim_player)
	if anim_player and anim_player.has_animation(resolved):
		return resolved
	for candidate in [death_anims.from_front, death_anims.from_back, death_anims.from_left, death_anims.from_right]:
		var alt := AnimationResolver.resolve(candidate, anim_player)
		if anim_player and anim_player.has_animation(alt):
			return alt
	return resolved


func _spawn_health_bar() -> void:
	if not visual_root:
		return
	var skeleton := visual_root.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if not skeleton:
		return
	var bone_idx := -1
	for bone_name in ["head", "Head", "mixamorig:Head", "spine.002", "Spine2", "neck", "Neck"]:
		bone_idx = skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			break
	if bone_idx < 0:
		return
	var health_bar_script := preload("res://scripts/ui/world_health_bar_3d.gd")
	_health_bar = Node3D.new()
	_health_bar.set_script(health_bar_script)
	add_child(_health_bar)
	_health_bar.call("setup_bone", skeleton, bone_idx)
	_health_bar.call("set_health_ratio", 1.0)


func _update_animation_state(is_moving: bool, delta: float) -> void:
	if _current_alert >= 3 and _is_unarmed_combatant():
		_play_unarmed_combat_animation(is_moving)
		_was_moving = is_moving
		return
	if is_moving and anim_tree and not anim_tree.active:
		anim_tree.active = true

	if not is_moving:
		if _was_moving:
			_play_alert_idle()
			_idle_variant_timer = randf_range(8.0, 15.0)
		else:
			_idle_variant_timer -= delta
			if _idle_variant_timer <= 0.0:
				_play_alert_idle()
				_idle_variant_timer = randf_range(8.0, 15.0)
	elif anim_player and anim_player.is_playing():
		anim_player.stop()

	# ── Combat mode: use Combat BlendSpace2D ────────────────────────────
	if _current_alert >= 3:
		anim_player.speed_scale = _get_combat_playback_scale(is_moving)
		_set_anim_condition("is_moving", false)
		_set_anim_condition("is_stopping", false)
		var playback: AnimationNodeStateMachinePlayback = _get_anim_playback()
		if playback and not _in_combat_tree:
			playback.travel("Combat")
			_in_combat_tree = true
		var target_blend: Vector2 = _get_combat_strafe_blend() if is_moving else Vector2.ZERO
		_current_combat_blend = _current_combat_blend.move_toward(target_blend, blend_lerp_speed * delta)
		_set_combat_blend(_current_combat_blend)
		_was_moving = is_moving
		return

	# ── Normal mode: Idle / Locomotion ──────────────────────────────────
	anim_player.speed_scale = 1.0
	if _in_combat_tree:
		_in_combat_tree = false
		var playback: AnimationNodeStateMachinePlayback = _get_anim_playback()
		if playback:
			playback.travel("Idle")

	_set_anim_condition("is_moving", is_moving)
	_set_anim_condition("is_stopping", _was_moving and not is_moving)

	var loco_target: float = 1.0 if is_moving else 0.0
	_current_loco_blend = move_toward(_current_loco_blend, loco_target, blend_lerp_speed * delta)
	_set_locomotion_blend(_current_loco_blend)

	_was_moving = is_moving


func _should_block_horizontal_motion() -> bool:
	return false


func _should_force_idle() -> bool:
	return _combat_holding_position


func _get_combat_strafe_blend() -> Vector2:
	if not visual_root:
		return Vector2.ZERO
	var desired := _get_desired_move_direction()
	if desired.length_squared() <= 0.0001:
		return Vector2.ZERO
	var forward := Vector2(visual_root.global_transform.basis.z.x,
						   visual_root.global_transform.basis.z.z)
	var right := Vector2(-visual_root.global_transform.basis.x.x,
						 -visual_root.global_transform.basis.x.z)
	if forward.length_squared() < 0.001 or right.length_squared() < 0.001:
		return Vector2.ZERO
	forward = forward.normalized()
	right = right.normalized()
	desired = desired.normalized()
	var raw := Vector2(
		clampf(right.dot(desired), -1.0, 1.0),
		clampf(forward.dot(desired), -1.0, 1.0)
	)
	# Snap to cardinal direction (no diagonals)
	if abs(raw.x) >= abs(raw.y):
		return Vector2(signf(raw.x), 0.0)
	var vertical := signf(raw.y)
	if vertical <= 0.0:
		return Vector2(0.0, vertical)
	return Vector2(0.0, _get_forward_chase_blend())


func refresh_idle_animation() -> void:
	_play_alert_idle()


func _get_desired_move_direction() -> Vector2:
	if nav_agent and not nav_agent.is_navigation_finished():
		var dir := nav_agent.get_next_path_position() - global_position
		dir.y = 0.0
		var desired := Vector2(dir.x, dir.z)
		if desired.length() > 0.05:
			return desired
	var vel2d := Vector2(velocity.x, velocity.z)
	if vel2d.length() > 0.05:
		return vel2d
	return Vector2.ZERO


func _get_combat_playback_scale(is_moving: bool) -> float:
	if not is_moving:
		return 1.0
	var chase_t := _get_forward_chase_t()
	return lerpf(1.0, 1.15, chase_t)


func _get_action_playback_scale() -> float:
	var combat := get_node_or_null("BanditCombat")
	if combat and combat.has_method("get_action_animation_speed_scale"):
		return float(combat.get_action_animation_speed_scale())
	return 1.0


func _get_forward_chase_blend() -> float:
	return lerpf(1.0, 2.0, _get_forward_chase_t())


func _get_forward_chase_t() -> float:
	var speed_span := maxf(speed_combat - speed_alert, 0.001)
	return clampf((_target_speed - speed_alert) / speed_span, 0.0, 1.0)


func _play_alert_idle() -> void:
	if not anim_player:
		return
	if _is_dead:
		return
	if _current_alert >= 3 and _is_unarmed_combatant():
		_play_unarmed_combat_animation(false)
		return
	# Combat idle: use the animation tree's Combat state at blend (0,0)
	if _current_alert >= 3:
		if anim_tree and not anim_tree.active:
			anim_tree.active = true
		_current_combat_blend = Vector2.ZERO
		_set_combat_blend(_current_combat_blend)
		var playback: AnimationNodeStateMachinePlayback = _get_anim_playback()
		if playback:
			playback.travel("Combat")
			_in_combat_tree = true
		return
	# Non-combat idle: play directly on AnimationPlayer
	if anim_tree:
		anim_tree.active = false
	_in_combat_tree = false
	var anim_name: String
	match _current_alert:
		0:
			anim_name = "npc_axe/unarmed_idle"
		1:
			anim_name = "npc_axe/standing_idle_looking_ver_001"
		2:
			anim_name = "npc_axe/unarmed_idle_looking_ver"
		_:
			var opts: Array[String] = ["npc_axe/standing_idle", "npc_axe/standing_idle_looking_ver"]
			anim_name = opts.pick_random()
	if anim_player.has_animation(anim_name):
		anim_player.play(anim_name, 0.3)


func _is_unarmed_combatant() -> bool:
	var combat := get_node_or_null("BanditCombat")
	return combat and combat.has_method("is_unarmed") and bool(combat.is_unarmed())


func _play_unarmed_combat_animation(is_moving: bool) -> void:
	if anim_tree:
		anim_tree.active = false
	_in_combat_tree = false
	if not anim_player:
		return
	var anim_name := "npc_axe/unarmed_idle"
	if is_moving:
		var desired := _get_desired_move_direction()
		var move_dot := 1.0
		if desired.length_squared() > 0.0001 and visual_root:
			var forward := Vector2(visual_root.global_transform.basis.z.x, visual_root.global_transform.basis.z.z)
			if forward.length_squared() > 0.0001:
				move_dot = forward.normalized().dot(desired.normalized())
		var running := _target_speed >= speed_combat * 0.8
		if move_dot < -0.2:
			anim_name = "npc_axe/unarmed_run_back" if running else "npc_axe/unarmed_walk_back"
		else:
			anim_name = "npc_axe/unarmed_run_forward" if running else "npc_axe/unarmed_walk_forward"
	if anim_player.current_animation != anim_name or not anim_player.is_playing():
		if anim_player.has_animation(anim_name):
			anim_player.play(anim_name, 0.12)
const _HEART_SCRIPT := preload("res://scripts/enemies/heart_indicator.gd")


func _spawn_heart_indicator() -> void:
	var skel: Skeleton3D = visual_root.get_node_or_null("Armature/Skeleton3D")
	if not skel:
		push_warning("[HeartSpawn] ", name, ": No Armature/Skeleton3D under visual_root")
		return
	var all_bones: PackedStringArray = []
	for i in skel.get_bone_count():
		all_bones.append(skel.get_bone_name(i))
	print("[HeartSpawn] ", name, ": skeleton bones = ", all_bones)
	var bone_idx := -1
	var matched_bone_name := ""
	for bone_name in ["spine.002", "Spine2", "spine2", "spine_02", "chest", "Spine1", "spine1"]:
		bone_idx = skel.find_bone(bone_name)
		if bone_idx >= 0:
			matched_bone_name = bone_name
			print("[HeartSpawn] ", name, ": matched bone '", bone_name, "' idx=", bone_idx)
			break
	if bone_idx < 0:
		push_warning("[HeartSpawn] ", name, ": No chest bone found in skeleton! Tried spine.002/Spine2/spine_02/chest/Spine1")
		return

	var attachment := BoneAttachment3D.new()
	attachment.bone_name = matched_bone_name
	skel.add_child(attachment)
	attachment.bone_idx = bone_idx

	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.85, 0.12, 0.1, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.12, 0.1, 1.0)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = quad
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.set_script(_HEART_SCRIPT)
	visual_root.add_child(mesh_inst)
	mesh_inst.call("setup_bone", skel, bone_idx)
	print("[HeartSpawn] ", name, ": heart MeshInstance3D created (child of visual_root, manual bone tracking)")
