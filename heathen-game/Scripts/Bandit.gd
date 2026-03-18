extends CharacterBody3D

enum AwarenessState {
	IDLE,
	SUSPICIOUS,
	ALERTED,
	ENGAGED
}

@export var chase_speed := 4.2
@export var acceleration := 14.0
@export var rotation_speed := 10.0
@export var detection_range := 24.0
@export var suspicious_range := 14.0
@export_range(10.0, 180.0, 1.0) var vision_angle_degrees := 85.0
@export var eye_height := 1.45
@export var suspicion_build_rate := 1.4
@export var suspicion_decay_rate := 0.75
@export_range(0.05, 0.95, 0.01) var suspicious_threshold := 0.32
@export_range(0.1, 1.0, 0.01) var alerted_threshold := 0.7
@export var search_duration := 4.5
@export var search_arrival_distance := 0.8
@export var attack_range := 1.55
@export var chase_resume_delay := 1.1
@export var slow_down_range := 4.0
@export_range(0.1, 1.0, 0.05) var close_speed_multiplier := 0.45
@export var attack_damage := 12.0
@export var attack_cooldown := 1.1
@export var attack_windup := 0.18
@export var attack_active_time := 0.22
@export var attack_recovery := 0.22
@export var max_health := 45.0
@export var sword_rest_rotation := Vector3(-8.0, -18.0, -38.0)
@export var sword_windup_rotation := Vector3(-6.0, -78.0, -96.0)
@export var sword_follow_through_rotation := Vector3(-6.0, 78.0, 96.0)
@export var hit_reaction_duration := 0.22
@export var block_reaction_duration := 0.16
@export var hit_reaction_tilt_degrees := 14.0
@export var block_reaction_sword_degrees := 18.0
@export var blocked_attack_recoil_duration := 0.14
@export var blocked_attack_recoil_blend := 0.7
@export var health_bar_offset := Vector3(0.0, 2.05, 0.0)
@export var health_bar_pixel_scale := 0.005

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var attack_cooldown_remaining := 0.0
var attack_phase_time_remaining := 0.0
var chase_resume_delay_remaining := 0.0
var is_attacking := false
var attack_hitbox_active := false
var hit_targets: Array[Node] = []
var blocked_attack_recoil_remaining := 0.0
var blocked_attack_recoil_from := Vector3.ZERO
var blocked_attack_recoil_target := Vector3.ZERO
var hit_reaction_remaining := 0.0
var block_reaction_remaining := 0.0
var hit_reaction_side := 1.0
var block_reaction_side := 1.0
var awareness_state := AwarenessState.IDLE
var suspicion := 0.0
var search_time_remaining := 0.0
var can_see_player := false
var has_last_known_player_position := false
var last_known_player_position := Vector3.ZERO
var health := 45.0
var player_target: CharacterBody3D
var health_bar_fill: ColorRect
var health_bar_sprite: Sprite3D
var health_bar_status_label: Label

@onready var body_mesh_node: MeshInstance3D = $BodyMesh
@onready var sword_pivot: Node3D = $SwordPivot
@onready var sword_hitbox: Area3D = $SwordPivot/SwordHitbox
@onready var sword_hitbox_shape_node: CollisionShape3D = $SwordPivot/SwordHitbox/CollisionShape3D

func _ready() -> void:
	add_to_group("enemy")
	health = max_health
	player_target = get_tree().get_first_node_in_group("player") as CharacterBody3D
	sword_hitbox.monitoring = false
	sword_pivot.rotation_degrees = sword_rest_rotation
	_setup_health_bar()
	_update_health_bar()
	_update_awareness_visuals()

func _physics_process(delta: float) -> void:
	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	if chase_resume_delay_remaining > 0.0:
		chase_resume_delay_remaining = maxf(chase_resume_delay_remaining - delta, 0.0)
	_update_attack(delta)
	_update_feedback_state(delta)

	if player_target == null or not is_instance_valid(player_target):
		player_target = get_tree().get_first_node_in_group("player") as CharacterBody3D

	_update_awareness_state(delta)

	var move_direction := Vector3.ZERO
	var current_chase_speed := chase_speed
	var look_direction := Vector3.ZERO
	if awareness_state == AwarenessState.ENGAGED and player_target != null:
		var to_player := player_target.global_position - global_position
		var planar_to_player := Vector3(to_player.x, 0.0, to_player.z)
		var distance_to_player := planar_to_player.length()
		look_direction = planar_to_player

		if distance_to_player <= attack_range:
			chase_resume_delay_remaining = chase_resume_delay

		if distance_to_player > attack_range or is_attacking:
			if is_attacking:
				move_direction = Vector3.ZERO
			elif chase_resume_delay_remaining <= 0.0 and planar_to_player.length_squared() > 0.0001:
				move_direction = planar_to_player.normalized()
				current_chase_speed = _get_chase_speed(distance_to_player)
		elif not is_attacking:
			_try_attack()
	elif awareness_state == AwarenessState.ALERTED or awareness_state == AwarenessState.SUSPICIOUS:
		if has_last_known_player_position:
			var to_search_point := last_known_player_position - global_position
			var planar_to_search := Vector3(to_search_point.x, 0.0, to_search_point.z)
			look_direction = planar_to_search
			var distance_to_search := planar_to_search.length()
			if distance_to_search > search_arrival_distance and not is_attacking:
				move_direction = planar_to_search.normalized()
				if awareness_state == AwarenessState.ALERTED:
					current_chase_speed = chase_speed * 0.82
				else:
					current_chase_speed = chase_speed * 0.55

	if look_direction.length_squared() > 0.0001:
		var target_yaw := Vector3.FORWARD.signed_angle_to(look_direction.normalized(), Vector3.UP)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rotation_speed * delta))

	var target_velocity := move_direction * current_chase_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()


func _update_awareness_state(delta: float) -> void:
	if player_target == null or not is_instance_valid(player_target):
		can_see_player = false
		suspicion = maxf(suspicion - suspicion_decay_rate * delta, 0.0)
		search_time_remaining = maxf(search_time_remaining - delta, 0.0)
		_set_awareness_state(AwarenessState.IDLE)
		return

	var visibility_result := _evaluate_player_visibility()
	can_see_player = bool(visibility_result.get("visible", false))
	var visibility_strength := float(visibility_result.get("visibility", 0.0))

	if can_see_player:
		suspicion = minf(1.0, suspicion + suspicion_build_rate * maxf(visibility_strength, 0.2) * delta)
		last_known_player_position = visibility_result.get("player_position", player_target.global_position)
		has_last_known_player_position = true
		search_time_remaining = search_duration
	else:
		suspicion = maxf(suspicion - suspicion_decay_rate * delta, 0.0)
		if search_time_remaining > 0.0:
			search_time_remaining = maxf(search_time_remaining - delta, 0.0)
		elif suspicion < suspicious_threshold * 0.5:
			has_last_known_player_position = false

	var next_state := AwarenessState.IDLE
	if can_see_player and suspicion >= alerted_threshold:
		next_state = AwarenessState.ENGAGED
	elif search_time_remaining > 0.0 and suspicion >= suspicious_threshold:
		next_state = AwarenessState.ALERTED
	elif suspicion >= suspicious_threshold or (has_last_known_player_position and search_time_remaining > 0.0):
		next_state = AwarenessState.SUSPICIOUS

	_set_awareness_state(next_state)


func _evaluate_player_visibility() -> Dictionary:
	var result := {
		"visible": false,
		"visibility": 0.0,
		"distance": INF,
		"player_position": Vector3.ZERO
	}
	if player_target == null or not is_instance_valid(player_target):
		return result

	var eye_position := global_position + Vector3.UP * eye_height
	var focus_position := player_target.global_position + Vector3.UP * 1.35
	if player_target.has_method("get_detection_focus_position"):
		focus_position = player_target.get_detection_focus_position()

	var to_player := focus_position - eye_position
	var planar_to_player := Vector3(to_player.x, 0.0, to_player.z)
	var distance_to_player := planar_to_player.length()
	result["distance"] = distance_to_player
	result["player_position"] = player_target.global_position

	var visibility_multiplier := 1.0
	if player_target.has_method("get_stealth_visibility_multiplier"):
		visibility_multiplier = clampf(player_target.get_stealth_visibility_multiplier(), 0.2, 1.2)

	var effective_detection_range := detection_range * visibility_multiplier
	var effective_suspicious_range := suspicious_range * visibility_multiplier
	if distance_to_player > effective_detection_range:
		return result

	if planar_to_player.length_squared() > 0.0001:
		var forward := -global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var facing_dot := forward.dot(planar_to_player.normalized())
		var required_dot := cos(deg_to_rad(vision_angle_degrees * 0.5))
		if facing_dot < required_dot and distance_to_player > attack_range * 1.35:
			return result

	if not _has_line_of_sight(eye_position, focus_position):
		return result

	var visibility_strength := 1.0 - distance_to_player / maxf(effective_suspicious_range, 0.001)
	result["visible"] = true
	result["visibility"] = clampf(maxf(visibility_strength, 0.12), 0.0, 1.0)
	return result


func _has_line_of_sight(from_position: Vector3, to_position: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from_position, to_position)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true

	var collider: Variant = result.get("collider")
	if collider == player_target:
		return true
	if collider is Area3D and (collider as Area3D).get_parent() == player_target:
		return true
	return false


func _set_awareness_state(next_state: int) -> void:
	if awareness_state == next_state:
		_update_awareness_visuals()
		return

	awareness_state = next_state
	_update_awareness_visuals()


func _update_awareness_visuals() -> void:
	if health_bar_status_label == null:
		return

	health_bar_status_label.text = get_awareness_state_name()
	match awareness_state:
		AwarenessState.IDLE:
			health_bar_status_label.modulate = Color(0.72, 0.82, 0.74, 0.95)
		AwarenessState.SUSPICIOUS:
			health_bar_status_label.modulate = Color(0.94, 0.82, 0.42, 1.0)
		AwarenessState.ALERTED:
			health_bar_status_label.modulate = Color(1.0, 0.58, 0.3, 1.0)
		AwarenessState.ENGAGED:
			health_bar_status_label.modulate = Color(1.0, 0.24, 0.22, 1.0)

func _get_chase_speed(distance_to_player: float) -> float:
	if slow_down_range <= attack_range or distance_to_player >= slow_down_range:
		return chase_speed

	var slow_down_alpha := inverse_lerp(attack_range, slow_down_range, distance_to_player)
	return chase_speed * lerpf(close_speed_multiplier, 1.0, slow_down_alpha)


func _setup_health_bar() -> void:
	var bar_size := Vector2(72.0, 10.0)
	var bar_padding := 2.0
	var label_height := 16.0
	var viewport_size := Vector2i(int(bar_size.x + bar_padding * 2.0), int(bar_size.y + bar_padding * 2.0 + label_height))

	var anchor := Node3D.new()
	anchor.name = "HealthBarAnchor"
	anchor.position = health_bar_offset
	add_child(anchor)

	var viewport := SubViewport.new()
	viewport.name = "HealthBarViewport"
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = viewport_size
	anchor.add_child(viewport)

	var root := Control.new()
	root.custom_minimum_size = Vector2(viewport_size)
	viewport.add_child(root)

	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(viewport_size)
	background.color = Color(0.08, 0.07, 0.08, 0.85)
	root.add_child(background)

	health_bar_fill = ColorRect.new()
	health_bar_fill.position = Vector2(bar_padding, bar_padding)
	health_bar_fill.size = bar_size
	health_bar_fill.color = Color(0.82, 0.17, 0.14, 1.0)
	root.add_child(health_bar_fill)

	health_bar_status_label = Label.new()
	health_bar_status_label.position = Vector2(0.0, bar_size.y + bar_padding * 2.0)
	health_bar_status_label.size = Vector2(viewport_size.x, label_height)
	health_bar_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_bar_status_label.text = get_awareness_state_name()
	root.add_child(health_bar_status_label)

	health_bar_sprite = Sprite3D.new()
	health_bar_sprite.name = "HealthBarSprite"
	health_bar_sprite.texture = viewport.get_texture()
	health_bar_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	health_bar_sprite.pixel_size = health_bar_pixel_scale
	health_bar_sprite.fixed_size = false
	health_bar_sprite.no_depth_test = true
	anchor.add_child(health_bar_sprite)


func _update_health_bar() -> void:
	if health_bar_fill == null:
		return

	var health_ratio := 0.0
	if max_health > 0.0:
		health_ratio = clampf(health / max_health, 0.0, 1.0)

	health_bar_fill.size.x = 72.0 * health_ratio
	health_bar_fill.color = Color(0.88, 0.16, 0.14, 1.0).lerp(Color(0.22, 0.82, 0.34, 1.0), health_ratio)
	if health_bar_sprite != null:
		health_bar_sprite.visible = health > 0.0

func _try_attack() -> void:
	if attack_cooldown_remaining > 0.0 or is_attacking:
		return
	if player_target == null or not player_target.has_method("take_damage"):
		return

	attack_cooldown_remaining = attack_cooldown
	is_attacking = true
	attack_phase_time_remaining = 0.0
	hit_targets.clear()
	_set_attack_hitbox_enabled(false)
	sword_pivot.rotation_degrees = sword_rest_rotation


func _update_attack(delta: float) -> void:
	if blocked_attack_recoil_remaining > 0.0:
		blocked_attack_recoil_remaining = maxf(blocked_attack_recoil_remaining - delta, 0.0)
		var recoil_alpha := 1.0
		if blocked_attack_recoil_duration > 0.0:
			recoil_alpha = 1.0 - blocked_attack_recoil_remaining / blocked_attack_recoil_duration
		sword_pivot.rotation_degrees = blocked_attack_recoil_from.lerp(blocked_attack_recoil_target, recoil_alpha)
		_set_attack_hitbox_enabled(false)
		if blocked_attack_recoil_remaining <= 0.0:
			sword_pivot.rotation_degrees = blocked_attack_recoil_target
		return

	if not is_attacking:
		sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(sword_rest_rotation, 1.0 - exp(-14.0 * delta))
		if attack_hitbox_active:
			_set_attack_hitbox_enabled(false)
		return

	attack_phase_time_remaining += delta
	var windup_end := attack_windup
	var active_end := attack_windup + attack_active_time
	var recovery_end := attack_windup + attack_active_time + attack_recovery

	if attack_phase_time_remaining <= windup_end:
		var windup_alpha := attack_phase_time_remaining / maxf(attack_windup, 0.001)
		sword_pivot.rotation_degrees = sword_rest_rotation.lerp(sword_windup_rotation, windup_alpha)
		_set_attack_hitbox_enabled(false)
	elif attack_phase_time_remaining <= active_end:
		var active_alpha := (attack_phase_time_remaining - windup_end) / maxf(attack_active_time, 0.001)
		sword_pivot.rotation_degrees = sword_windup_rotation.lerp(sword_follow_through_rotation, active_alpha)
		_set_attack_hitbox_enabled(true)
		_apply_hitbox_damage()
	elif attack_phase_time_remaining <= recovery_end:
		var recovery_alpha := (attack_phase_time_remaining - active_end) / maxf(attack_recovery, 0.001)
		sword_pivot.rotation_degrees = sword_follow_through_rotation.lerp(sword_rest_rotation, recovery_alpha)
		_set_attack_hitbox_enabled(false)
	else:
		is_attacking = false
		attack_phase_time_remaining = 0.0
		hit_targets.clear()
		_set_attack_hitbox_enabled(false)
		sword_pivot.rotation_degrees = sword_rest_rotation


func _set_attack_hitbox_enabled(is_enabled: bool) -> void:
	if attack_hitbox_active == is_enabled:
		return

	attack_hitbox_active = is_enabled
	sword_hitbox.monitoring = is_enabled


func _update_feedback_state(delta: float) -> void:
	if hit_reaction_remaining > 0.0:
		hit_reaction_remaining = maxf(hit_reaction_remaining - delta, 0.0)
	if block_reaction_remaining > 0.0:
		block_reaction_remaining = maxf(block_reaction_remaining - delta, 0.0)

	var hit_weight := 0.0
	if hit_reaction_duration > 0.0 and hit_reaction_remaining > 0.0:
		hit_weight = sin((hit_reaction_remaining / hit_reaction_duration) * PI)

	var block_weight := 0.0
	if block_reaction_duration > 0.0 and block_reaction_remaining > 0.0:
		block_weight = sin((block_reaction_remaining / block_reaction_duration) * PI)

	body_mesh_node.rotation_degrees.z = hit_reaction_side * hit_reaction_tilt_degrees * hit_weight
	body_mesh_node.scale.x = 1.0 + hit_weight * 0.08
	body_mesh_node.scale.y = 1.0 - hit_weight * 0.08
	body_mesh_node.scale.z = 1.0 + hit_weight * 0.08

	if block_weight > 0.0:
		sword_pivot.rotation_degrees.z += block_reaction_side * block_reaction_sword_degrees * block_weight
		body_mesh_node.rotation_degrees.y = -block_reaction_side * 6.0 * block_weight
	else:
		body_mesh_node.rotation_degrees.y = 0.0


func _apply_hitbox_damage() -> void:
	for hit: Dictionary in _intersect_sword_hitbox():
		var hurtbox := hit.get("collider") as Area3D
		if hurtbox == null:
			continue
		var target := hurtbox.get_parent()
		if target == self:
			continue
		if target == null or not target.has_method("take_damage"):
			continue
		if hit_targets.has(target):
			continue

		hit_targets.append(target)
		target.take_damage(attack_damage, global_position, self)


func _intersect_sword_hitbox() -> Array[Dictionary]:
	var hitbox_shape := sword_hitbox_shape_node.shape
	if hitbox_shape == null:
		return []

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hitbox_shape
	query.transform = sword_hitbox_shape_node.global_transform
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = [get_rid(), sword_hitbox.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query)


func _trigger_hit_feedback(source_position: Vector3) -> void:
	hit_reaction_remaining = hit_reaction_duration
	hit_reaction_side = _get_reaction_side(source_position)


func _get_reaction_side(source_position: Vector3) -> float:
	if source_position == Vector3.ZERO:
		return 1.0

	var to_source := source_position - global_position
	to_source.y = 0.0
	if to_source.length_squared() <= 0.0001:
		return 1.0

	to_source = to_source.normalized()
	var side_dot := global_basis.x.dot(to_source)
	if side_dot == 0.0:
		return 1.0
	return signf(side_dot)


func on_attack_blocked(blocker_position: Vector3 = Vector3.ZERO) -> void:
	is_attacking = false
	attack_phase_time_remaining = 0.0
	hit_targets.clear()
	_set_attack_hitbox_enabled(false)
	blocked_attack_recoil_remaining = blocked_attack_recoil_duration
	blocked_attack_recoil_from = sword_pivot.rotation_degrees
	blocked_attack_recoil_target = sword_rest_rotation.lerp(sword_windup_rotation, blocked_attack_recoil_blend)
	block_reaction_remaining = block_reaction_duration
	block_reaction_side = -_get_reaction_side(blocker_position)


func take_damage(amount: float, source_position: Vector3 = Vector3.ZERO, source: Node3D = null) -> void:
	if amount <= 0.0:
		return

	suspicion = 1.0
	search_time_remaining = search_duration
	if source != null and source.is_in_group("player"):
		last_known_player_position = source.global_position
		has_last_known_player_position = true
	elif source_position != Vector3.ZERO:
		last_known_player_position = source_position
		has_last_known_player_position = true
	_set_awareness_state(AwarenessState.ENGAGED)

	health = maxf(health - amount, 0.0)
	_update_health_bar()
	_trigger_hit_feedback(source_position)
	if source_position != Vector3.ZERO:
		var knockback_direction := global_position - source_position
		knockback_direction.y = 0.0
		if knockback_direction.length_squared() > 0.0001:
			knockback_direction = knockback_direction.normalized()
			velocity.x += knockback_direction.x * 1.4
			velocity.z += knockback_direction.z * 1.4

	if health <= 0.0:
		queue_free()


func get_awareness_state_name() -> String:
	match awareness_state:
		AwarenessState.SUSPICIOUS:
			return "Suspicious"
		AwarenessState.ALERTED:
			return "Alerted"
		AwarenessState.ENGAGED:
			return "Engaged"
		_:
			return "Idle"


func get_heartbeat_intensity() -> float:
	match awareness_state:
		AwarenessState.SUSPICIOUS:
			return maxf(suspicion, 0.28)
		AwarenessState.ALERTED:
			return maxf(suspicion, 0.62)
		AwarenessState.ENGAGED:
			return 1.0
		_:
			return 0.0


func get_heartbeat_label() -> String:
	match awareness_state:
		AwarenessState.SUSPICIOUS:
			return "Quickening"
		AwarenessState.ALERTED:
			return "Rapid"
		AwarenessState.ENGAGED:
			return "Racing"
		_:
			return "Resting"


func get_heartbeat_detail() -> String:
	match awareness_state:
		AwarenessState.SUSPICIOUS:
			return "A pulse stirs nearby. Someone suspects a shape in the dark."
		AwarenessState.ALERTED:
			return "The heart has climbed. The bandit is hunting your last position."
		AwarenessState.ENGAGED:
			return "The pulse is racing. The foe is committed to the kill."
		_:
			return "A resting heart is a vulnerability."


func is_player_hostile() -> bool:
	return awareness_state >= AwarenessState.ALERTED
