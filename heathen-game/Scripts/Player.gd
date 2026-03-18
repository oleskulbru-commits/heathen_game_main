extends CharacterBody3D

signal health_changed(current_health: float, maximum_health: float)
signal died
signal spell_wheel_toggled(is_visible)
signal spell_selection_changed(spell_names, spell_descriptions, selected_index)
signal spell_cast(spell_name, cast_text)
signal combat_mode_changed(is_in_combat)
signal stealth_feedback_changed(reading_label, reading_detail, pulse_strength)

@export var speed := 5.0
@export var sprint_speed := 8.5
@export var crouch_speed := 2.5
@export var acceleration := 16.0
@export var rotation_speed := 10.0
@export var jump_velocity := 5.5
@export var crouch_transition_speed := 12.0
@export var crouch_collision_height := 1.2
@export var crouch_visual_scale := 0.72
@export var crouch_visual_drop := 0.4
@export_range(0.2, 1.0, 0.05) var crouch_visibility_multiplier := 0.55
@export var standing_camera_focus_height := 1.6
@export var crouching_camera_focus_height := 1.05
@export var stand_check_margin := 0.05
@export var max_health := 100.0
@export var damage_invulnerability_time := 0.45
@export var blocked_damage_multiplier := 0.2
@export var block_move_speed_multiplier := 0.55
@export var combat_move_speed := 3.35
@export var combat_enter_range := 3.2
@export var combat_exit_range := 4.8
@export var dodge_speed := 6.25
@export var dodge_duration := 0.24
@export var dodge_cooldown := 0.8
@export var dodge_invulnerability_time := 0.28
@export var spell_wheel_hold_time := 0.24
@export var spell_cast_cooldown := 0.7
@export var spell_burst_damage := 10.0
@export var spell_burst_radius := 3.4
@export var spell_heal_amount := 18.0
@export var spell_gale_surge_speed := 10.5
@export var spell_stone_veil_duration := 0.9
@export var attack_damage := 18.0
@export var attack_cooldown := 0.55
@export var attack_windup := 0.14
@export var attack_active_time := 0.14
@export var attack_recovery := 0.24
@export var sword_rest_rotation := Vector3(-8.0, -18.0, -38.0)
@export var sword_windup_rotation := Vector3(-6.0, -78.0, -96.0)
@export var sword_follow_through_rotation := Vector3(-6.0, 78.0, 96.0)
@export var sword_block_rotation := Vector3(-72.0, -16.0, 8.0)
@export var hit_reaction_duration := 0.2
@export var block_reaction_duration := 0.16
@export var hit_reaction_tilt_degrees := 14.0
@export var block_reaction_sword_degrees := 18.0
@export var blocked_attack_recoil_duration := 0.14
@export var blocked_attack_recoil_blend := 0.7

const SPELL_LOADOUT := [
	{"name": "Ember Burst", "description": "Burn nearby foes."},
	{"name": "Warden Pulse", "description": "Restore a sliver of health."},
	{"name": "Gale Surge", "description": "Lunge in your facing direction."},
	{"name": "Stone Veil", "description": "Gain a brief ward."}
]

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var is_crouching := false
var is_dead := false
var is_blocking := false
var is_attacking := false
var is_dodging := false
var is_in_combat_mode := false
var health := 100.0
var damage_invulnerability_remaining := 0.0
var dodge_cooldown_remaining := 0.0
var dodge_time_remaining := 0.0
var spell_input_held := false
var spell_hold_time := 0.0
var spell_wheel_open := false
var spell_cast_cooldown_remaining := 0.0
var selected_spell_index := 0
var attack_cooldown_remaining := 0.0
var attack_phase_time_remaining := 0.0
var attack_hitbox_active := false
var hit_targets: Array[Node] = []
var dodge_direction := Vector3.ZERO
var blocked_attack_recoil_remaining := 0.0
var blocked_attack_recoil_from := Vector3.ZERO
var blocked_attack_recoil_target := Vector3.ZERO
var hit_reaction_remaining := 0.0
var block_reaction_remaining := 0.0
var hit_reaction_side := 1.0
var block_reaction_side := 1.0
var standing_collision_height := 0.0
var standing_collision_position := Vector3.ZERO
var standing_collision_position_y := 0.0
var standing_mesh_position_y := 0.0
var standing_marker_position_y := 0.0
var combat_target: Node3D
var stealth_feedback_label := "Stillness"
var stealth_feedback_detail := "No hostile pulse nearby."
var stealth_feedback_strength := 0.0

@onready var camera_rig: Node = $CameraRig
@onready var collision_shape_node: CollisionShape3D = $CollisionShape3D
@onready var body_mesh_node: MeshInstance3D = $MeshInstance3D
@onready var forward_marker_node: MeshInstance3D = $ForwardMarker
@onready var sword_pivot: Node3D = $SwordPivot
@onready var sword_hitbox: Area3D = $SwordPivot/SwordHitbox
@onready var sword_hitbox_shape_node: CollisionShape3D = $SwordPivot/SwordHitbox/CollisionShape3D


func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	health = max_health
	var collision_shape := collision_shape_node.shape as CapsuleShape3D
	if collision_shape != null:
		standing_collision_height = collision_shape.height
	standing_collision_position = collision_shape_node.position
	standing_collision_position_y = collision_shape_node.position.y
	standing_mesh_position_y = body_mesh_node.position.y
	standing_marker_position_y = forward_marker_node.position.y
	sword_hitbox.monitoring = false
	sword_pivot.rotation_degrees = sword_rest_rotation
	health_changed.emit(health, max_health)
	stealth_feedback_changed.emit(stealth_feedback_label, stealth_feedback_detail, stealth_feedback_strength)
	if camera_rig != null and camera_rig.has_method("set_combat_mode"):
		camera_rig.set_combat_mode(false)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("spell"):
		_on_spell_pressed()
		return
	if event.is_action_released("spell"):
		_on_spell_released()
		return
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if damage_invulnerability_remaining > 0.0:
		damage_invulnerability_remaining = maxf(damage_invulnerability_remaining - delta, 0.0)
	if dodge_cooldown_remaining > 0.0:
		dodge_cooldown_remaining = maxf(dodge_cooldown_remaining - delta, 0.0)
	if spell_cast_cooldown_remaining > 0.0:
		spell_cast_cooldown_remaining = maxf(spell_cast_cooldown_remaining - delta, 0.0)
	if spell_input_held:
		spell_hold_time += delta
		if not spell_wheel_open and spell_hold_time >= spell_wheel_hold_time:
			_set_spell_wheel_open(true)
	if is_dodging:
		dodge_time_remaining = maxf(dodge_time_remaining - delta, 0.0)
		if dodge_time_remaining <= 0.0:
			is_dodging = false
			dodge_direction = Vector3.ZERO
	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	_update_combat_state(delta)
	_update_feedback_state(delta)

	if is_dead:
		velocity = Vector3.ZERO
		return

	_update_combat_mode()

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_update_crouch_state(delta)
	_update_stealth_feedback()
	var move_direction := _get_move_direction(input_vector)
	if spell_wheel_open:
		_update_spell_selection(input_vector)

	if not spell_wheel_open and Input.is_action_just_pressed("dodge"):
		_start_dodge(move_direction)

	if not spell_wheel_open and not is_dodging and Input.is_action_just_pressed("attack") and not is_crouching:
		_start_attack()

	is_blocking = Input.is_action_pressed("block") and not is_attacking and not is_crouching and not is_dodging and not spell_wheel_open

	var target_velocity := move_direction * _get_move_speed(input_vector)
	if is_dodging:
		target_velocity = dodge_direction * dodge_speed
	elif spell_wheel_open:
		target_velocity = Vector3.ZERO
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not is_crouching and not is_dodging and not spell_wheel_open:
			velocity.y = jump_velocity
		elif velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	var facing_direction := move_direction
	if is_dodging:
		facing_direction = dodge_direction

	if not spell_wheel_open and is_in_combat_mode:
		_rotate_toward_combat_target(delta)
	elif not spell_wheel_open and facing_direction != Vector3.ZERO:
		var target_yaw := Vector3.FORWARD.signed_angle_to(facing_direction, Vector3.UP)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rotation_speed * delta))

func _get_move_speed(input_vector: Vector2) -> float:
	if is_in_combat_mode:
		var target_speed := combat_move_speed
		if is_blocking:
			return target_speed * block_move_speed_multiplier
		return target_speed
	if is_crouching:
		return crouch_speed
	if is_blocking:
		return speed * block_move_speed_multiplier
	if Input.is_action_pressed("sprint") and input_vector.y < 0.0:
		return sprint_speed
	return speed

func _update_crouch_state(delta: float) -> void:
	var wants_to_crouch := Input.is_action_pressed("crouch") and not is_dodging and not spell_wheel_open
	if wants_to_crouch:
		is_crouching = true
	elif is_crouching:
		is_crouching = not _can_stand_up()
	else:
		is_crouching = false

	var collision_shape := collision_shape_node.shape as CapsuleShape3D
	if collision_shape != null:
		var target_collision_height := standing_collision_height
		var target_collision_position_y := standing_collision_position_y
		if is_crouching:
			target_collision_height = crouch_collision_height
			target_collision_position_y = standing_collision_position_y - (standing_collision_height - crouch_collision_height) * 0.25
		collision_shape.height = move_toward(collision_shape.height, target_collision_height, crouch_transition_speed * delta)
		collision_shape_node.position.y = move_toward(collision_shape_node.position.y, target_collision_position_y, crouch_transition_speed * delta)

	var target_mesh_scale_y := 1.0
	var target_mesh_position_y := standing_mesh_position_y
	var target_marker_position_y := standing_marker_position_y
	if is_crouching:
		target_mesh_scale_y = crouch_visual_scale
		target_mesh_position_y = standing_mesh_position_y - crouch_visual_drop * 0.5
		target_marker_position_y = standing_marker_position_y - crouch_visual_drop

	body_mesh_node.scale.y = move_toward(body_mesh_node.scale.y, target_mesh_scale_y, crouch_transition_speed * delta)
	body_mesh_node.position.y = move_toward(body_mesh_node.position.y, target_mesh_position_y, crouch_transition_speed * delta)
	forward_marker_node.position.y = move_toward(forward_marker_node.position.y, target_marker_position_y, crouch_transition_speed * delta)

	if camera_rig.has_method("set_focus_height"):
		var target_focus_height := standing_camera_focus_height
		if is_crouching:
			target_focus_height = crouching_camera_focus_height
		camera_rig.set_focus_height(target_focus_height)

func _can_stand_up() -> bool:
	var collision_shape := collision_shape_node.shape as CapsuleShape3D
	if collision_shape == null:
		return true

	var current_top := _get_capsule_top(collision_shape_node.position.y, collision_shape.height, collision_shape.radius)
	var standing_top := _get_capsule_top(standing_collision_position.y, standing_collision_height, collision_shape.radius)
	var from := global_position + Vector3.UP * (current_top + stand_check_margin)
	var to := global_position + Vector3.UP * (standing_top + stand_check_margin)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = false

	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return result.is_empty()

func _get_capsule_top(center_y: float, capsule_height: float, capsule_radius: float) -> float:
	return center_y + capsule_height * 0.5 + capsule_radius


func _update_combat_mode() -> void:
	var lock_distance := combat_enter_range
	if is_in_combat_mode:
		lock_distance = maxf(combat_exit_range, combat_enter_range)

	var next_target := _find_closest_enemy(lock_distance)
	if next_target == null:
		_set_combat_mode(false, null)
		return

	_set_combat_mode(true, next_target)


func _set_combat_mode(next_mode: bool, next_target: Node3D) -> void:
	var target_changed := combat_target != next_target
	if not target_changed and is_in_combat_mode == next_mode:
		return

	is_in_combat_mode = next_mode
	combat_target = next_target
	if not is_in_combat_mode:
		combat_target = null

	if camera_rig != null and camera_rig.has_method("set_combat_mode"):
		camera_rig.set_combat_mode(is_in_combat_mode)

	combat_mode_changed.emit(is_in_combat_mode)


func _find_closest_enemy(max_distance: float) -> Node3D:
	var closest_enemy: Node3D
	var closest_distance := max_distance
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_node := enemy as Node3D
		if enemy_node == null:
			continue
		var planar_offset := enemy_node.global_position - global_position
		planar_offset.y = 0.0
		var enemy_distance := planar_offset.length()
		if enemy.has_method("is_player_hostile") and not enemy.is_player_hostile():
			continue
		if enemy_distance > closest_distance:
			continue
		closest_distance = enemy_distance
		closest_enemy = enemy_node

	return closest_enemy


func _get_move_direction(input_vector: Vector2) -> Vector3:
	if input_vector == Vector2.ZERO:
		return Vector3.ZERO

	if is_in_combat_mode and combat_target != null and is_instance_valid(combat_target):
		var to_target := combat_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			var combat_forward := to_target.normalized()
			var combat_right := Vector3.UP.cross(combat_forward).normalized()
			return (-combat_right * input_vector.x - combat_forward * input_vector.y).normalized()

	if camera_rig != null and camera_rig.has_method("get_camera_planar_basis"):
		var camera_basis: Basis = camera_rig.get_camera_planar_basis()
		return (camera_basis.x * input_vector.x + camera_basis.z * input_vector.y).normalized()

	return Vector3.ZERO


func _rotate_toward_combat_target(delta: float) -> void:
	if combat_target == null or not is_instance_valid(combat_target):
		return

	var to_target := combat_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return

	var target_yaw := Vector3.FORWARD.signed_angle_to(to_target.normalized(), Vector3.UP)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rotation_speed * delta))


func get_spell_names() -> Array[String]:
	var spell_names: Array[String] = []
	for spell_data: Dictionary in SPELL_LOADOUT:
		spell_names.append(spell_data.get("name", "Spell"))
	return spell_names


func get_spell_descriptions() -> Array[String]:
	var spell_descriptions: Array[String] = []
	for spell_data: Dictionary in SPELL_LOADOUT:
		spell_descriptions.append(spell_data.get("description", ""))
	return spell_descriptions


func get_selected_spell_index() -> int:
	return selected_spell_index


func get_stealth_feedback_label() -> String:
	return stealth_feedback_label


func get_stealth_feedback_detail() -> String:
	return stealth_feedback_detail


func get_stealth_feedback_strength() -> float:
	return stealth_feedback_strength


func get_stealth_visibility_multiplier() -> float:
	if is_crouching:
		return crouch_visibility_multiplier
	return 1.0


func get_detection_focus_position() -> Vector3:
	var focus_height := standing_camera_focus_height
	if is_crouching:
		focus_height = crouching_camera_focus_height
	return global_position + Vector3.UP * focus_height


func _update_stealth_feedback() -> void:
	var next_label := "Stillness"
	var next_detail := "No hostile pulse nearby."
	var next_strength := 0.0
	var closest_distance := INF

	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("get_heartbeat_intensity"):
			continue

		var enemy_node := enemy as Node3D
		if enemy_node == null:
			continue

		var intensity := float(enemy.get_heartbeat_intensity())
		if intensity <= 0.0:
			continue

		var distance_to_enemy := enemy_node.global_position.distance_to(global_position)
		if intensity > next_strength or (is_equal_approx(intensity, next_strength) and distance_to_enemy < closest_distance):
			next_strength = intensity
			closest_distance = distance_to_enemy
			if enemy.has_method("get_heartbeat_label"):
				next_label = enemy.get_heartbeat_label()
			if enemy.has_method("get_heartbeat_detail"):
				next_detail = enemy.get_heartbeat_detail()

	if next_strength <= 0.0:
		if is_crouching:
			next_detail = "Your breath stays low. A crouched silhouette carries less easily."
		else:
			next_detail = "No hostile pulse nearby. Standing in the open carries further."

	if stealth_feedback_label == next_label and stealth_feedback_detail == next_detail and is_equal_approx(stealth_feedback_strength, next_strength):
		return

	stealth_feedback_label = next_label
	stealth_feedback_detail = next_detail
	stealth_feedback_strength = next_strength
	stealth_feedback_changed.emit(stealth_feedback_label, stealth_feedback_detail, stealth_feedback_strength)


func _on_spell_pressed() -> void:
	if is_dead or is_attacking or is_dodging:
		return
	spell_input_held = true
	spell_hold_time = 0.0


func _on_spell_released() -> void:
	if not spell_input_held:
		return

	spell_input_held = false
	if spell_wheel_open:
		_set_spell_wheel_open(false)
	else:
		_cast_selected_spell()
	spell_hold_time = 0.0


func _set_spell_wheel_open(is_open: bool) -> void:
	if spell_wheel_open == is_open:
		return

	spell_wheel_open = is_open
	if spell_wheel_open:
		is_blocking = false
		velocity.x = 0.0
		velocity.z = 0.0
		_emit_spell_selection_changed()
	spell_wheel_toggled.emit(spell_wheel_open)


func _update_spell_selection(input_vector: Vector2) -> void:
	if input_vector.length_squared() <= 0.25:
		return

	var next_spell_index := selected_spell_index
	if absf(input_vector.x) > absf(input_vector.y):
		next_spell_index = 1 if input_vector.x > 0.0 else 3
	else:
		next_spell_index = 0 if input_vector.y < 0.0 else 2

	if next_spell_index == selected_spell_index:
		return

	selected_spell_index = next_spell_index
	_emit_spell_selection_changed()


func _emit_spell_selection_changed() -> void:
	spell_selection_changed.emit(get_spell_names(), get_spell_descriptions(), selected_spell_index)


func _cast_selected_spell() -> void:
	if not _can_cast_spell():
		return

	spell_cast_cooldown_remaining = spell_cast_cooldown
	var cast_text := ""
	match selected_spell_index:
		0:
			cast_text = _cast_ember_burst()
		1:
			cast_text = _cast_warden_pulse()
		2:
			cast_text = _cast_gale_surge()
		3:
			cast_text = _cast_stone_veil()
		_:
			cast_text = "Nothing happens."

	spell_cast.emit(SPELL_LOADOUT[selected_spell_index].get("name", "Spell"), cast_text)


func _can_cast_spell() -> bool:
	if is_dead or is_attacking or is_dodging or is_crouching or is_blocking:
		return false
	if spell_wheel_open or spell_cast_cooldown_remaining > 0.0:
		return false
	return true


func _cast_ember_burst() -> String:
	var hit_count := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("take_damage"):
			continue
		var enemy_body := enemy as Node3D
		if enemy_body == null:
			continue
		if enemy_body.global_position.distance_to(global_position) > spell_burst_radius:
			continue
		enemy.take_damage(spell_burst_damage, global_position, self)
		hit_count += 1

	if hit_count == 0:
		return "Ember Burst crackles, but catches nothing."
	return "Ember Burst scorches %d foe%s." % [hit_count, "s" if hit_count != 1 else ""]


func _cast_warden_pulse() -> String:
	var previous_health := health
	health = minf(health + spell_heal_amount, max_health)
	if health != previous_health:
		health_changed.emit(health, max_health)
	return "Warden Pulse restores %d health." % int(round(health - previous_health))


func _cast_gale_surge() -> String:
	var surge_direction := _get_spell_direction()
	velocity.x = surge_direction.x * spell_gale_surge_speed
	velocity.z = surge_direction.z * spell_gale_surge_speed
	damage_invulnerability_remaining = maxf(damage_invulnerability_remaining, 0.15)
	return "Gale Surge hurls you into position."


func _cast_stone_veil() -> String:
	damage_invulnerability_remaining = maxf(damage_invulnerability_remaining, spell_stone_veil_duration)
	return "Stone Veil hardens around you for a moment."


func _get_spell_direction() -> Vector3:
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_vector != Vector2.ZERO and camera_rig.has_method("get_camera_planar_basis"):
		var camera_basis: Basis = camera_rig.get_camera_planar_basis()
		var move_direction := camera_basis.x * input_vector.x + camera_basis.z * input_vector.y
		move_direction.y = 0.0
		if move_direction.length_squared() > 0.0001:
			return move_direction.normalized()

	var facing_direction := -global_basis.z
	facing_direction.y = 0.0
	if facing_direction.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return facing_direction.normalized()


func _start_attack() -> void:
	if is_dead or is_attacking or is_blocking or is_dodging or spell_wheel_open or attack_cooldown_remaining > 0.0:
		return

	is_attacking = true
	is_blocking = false
	attack_phase_time_remaining = 0.0
	attack_cooldown_remaining = attack_cooldown
	hit_targets.clear()
	_set_attack_hitbox_enabled(false)
	sword_pivot.rotation_degrees = sword_rest_rotation


func _start_dodge(move_direction: Vector3) -> void:
	if is_dead or is_dodging or is_crouching or is_attacking or spell_wheel_open or blocked_attack_recoil_remaining > 0.0:
		return
	if dodge_cooldown_remaining > 0.0 or not is_on_floor():
		return

	is_dodging = true
	is_blocking = false
	attack_phase_time_remaining = 0.0
	hit_targets.clear()
	_set_attack_hitbox_enabled(false)
	sword_pivot.rotation_degrees = sword_rest_rotation
	dodge_time_remaining = dodge_duration
	dodge_cooldown_remaining = dodge_cooldown
	damage_invulnerability_remaining = maxf(damage_invulnerability_remaining, dodge_invulnerability_time)

	if move_direction == Vector3.ZERO:
		dodge_direction = -global_basis.z
		dodge_direction.y = 0.0
		if dodge_direction.length_squared() <= 0.0001:
			dodge_direction = Vector3.BACK
	else:
		dodge_direction = move_direction

	dodge_direction = dodge_direction.normalized()
	velocity.x = dodge_direction.x * dodge_speed
	velocity.z = dodge_direction.z * dodge_speed


func _update_combat_state(delta: float) -> void:
	if is_dead:
		is_attacking = false
		is_blocking = false
		is_dodging = false
		_set_combat_mode(false, null)
		blocked_attack_recoil_remaining = 0.0
		_set_attack_hitbox_enabled(false)
		sword_pivot.rotation_degrees = sword_rest_rotation
		return

	if is_dodging:
		is_attacking = false
		is_blocking = false
		_set_attack_hitbox_enabled(false)
		sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(sword_rest_rotation, 1.0 - exp(-20.0 * delta))
		return

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

	if is_attacking:
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
			_apply_attack_hitbox_damage()
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
		return

	if is_blocking:
		sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(sword_block_rotation, 1.0 - exp(-18.0 * delta))
		_set_attack_hitbox_enabled(false)
	else:
		sword_pivot.rotation_degrees = sword_pivot.rotation_degrees.lerp(sword_rest_rotation, 1.0 - exp(-16.0 * delta))
		_set_attack_hitbox_enabled(false)


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

	var current_scale_y := body_mesh_node.scale.y
	body_mesh_node.rotation_degrees.z = hit_reaction_side * hit_reaction_tilt_degrees * hit_weight
	body_mesh_node.scale.x = 1.0 + hit_weight * 0.08
	body_mesh_node.scale.y = current_scale_y * (1.0 - hit_weight * 0.08)
	body_mesh_node.scale.z = 1.0 + hit_weight * 0.08

	if block_weight > 0.0:
		sword_pivot.rotation_degrees.z += block_reaction_side * block_reaction_sword_degrees * block_weight
		body_mesh_node.rotation_degrees.y = -block_reaction_side * 6.0 * block_weight
	else:
		body_mesh_node.rotation_degrees.y = 0.0


func _apply_attack_hitbox_damage() -> void:
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


func _is_blocking_source(source_position: Vector3) -> bool:
	if not is_blocking or source_position == Vector3.ZERO:
		return false

	var planar_to_source := source_position - global_position
	planar_to_source.y = 0.0
	if planar_to_source.length_squared() <= 0.0001:
		return true

	planar_to_source = planar_to_source.normalized()
	var facing := -global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	return facing.dot(planar_to_source) >= 0.2


func _trigger_hit_feedback(source_position: Vector3) -> void:
	hit_reaction_remaining = hit_reaction_duration
	hit_reaction_side = _get_reaction_side(source_position)


func _trigger_block_feedback(source_position: Vector3) -> void:
	block_reaction_remaining = block_reaction_duration
	block_reaction_side = _get_reaction_side(source_position)


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
	if is_dead or damage_invulnerability_remaining > 0.0 or amount <= 0.0:
		return
	if _is_blocking_source(source_position):
		_trigger_block_feedback(source_position)
		if source != null and source.has_method("on_attack_blocked"):
			source.on_attack_blocked(global_position)
		amount *= blocked_damage_multiplier
		if amount <= 0.0:
			return

	damage_invulnerability_remaining = damage_invulnerability_time
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	_trigger_hit_feedback(source_position)

	if source_position != Vector3.ZERO:
		var knockback_direction := global_position - source_position
		knockback_direction.y = 0.0
		if knockback_direction.length_squared() > 0.0001:
			knockback_direction = knockback_direction.normalized()
			velocity.x += knockback_direction.x * 2.2
			velocity.z += knockback_direction.z * 2.2

	if health <= 0.0:
		_die()

func _die() -> void:
	if is_dead:
		return

	is_dead = true
	_set_combat_mode(false, null)
	is_attacking = false
	is_blocking = false
	is_dodging = false
	blocked_attack_recoil_remaining = 0.0
	damage_invulnerability_remaining = 0.0
	dodge_cooldown_remaining = 0.0
	dodge_time_remaining = 0.0
	hit_reaction_remaining = 0.0
	block_reaction_remaining = 0.0
	_set_attack_hitbox_enabled(false)
	sword_pivot.rotation_degrees = sword_rest_rotation
	velocity = Vector3.ZERO
	died.emit()
