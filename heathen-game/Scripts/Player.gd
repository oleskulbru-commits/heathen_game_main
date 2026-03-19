extends CharacterBody3D

signal health_changed(current_health: float, maximum_health: float)
signal died
signal spell_wheel_toggled(is_visible)
signal spell_selection_changed(spell_names, spell_descriptions, spell_charges, selected_index)
signal spell_cast(spell_name, cast_text)
signal belt_status_changed(total_charges, total_capacity, can_prime)
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
@export var combat_lock_distance := 10.0
@export var combat_enter_range := 3.2
@export var combat_exit_range := 4.8
@export var focus_mode_steel_linger := 0.95
@export var focus_mode_rite_linger := 1.2
@export var dodge_speed := 6.25
@export var dodge_duration := 0.24
@export var dodge_cooldown := 0.8
@export var dodge_invulnerability_time := 0.28
@export var spell_wheel_hold_time := 0.24
@export var spell_cast_cooldown := 0.7
@export var hrafn_dash_speed := 12.5
@export var hrafn_phase_duration := 0.18
@export var hrafn_target_range := 10.0
@export var hrafn_reform_distance := 1.2
@export var hugr_pulse_duration := 6.5
@export var hugr_scan_range := 28.0
@export var gandr_range := 10.5
@export var gandr_bind_duration := 2.6
@export var attack_damage := 18.0
@export var attack_cooldown := 0.55
@export var attack_windup := 0.14
@export var attack_active_time := 0.14
@export var attack_recovery := 0.24
@export_range(1, 8, 1) var attack_hitbox_sweep_samples := 4
@export var attack_hitbox_query_margin := 0.08
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
	{"name": "Hrafn", "description": "Phase through the gap and reform into the hunt.", "charges": 2},
	{"name": "Hugr", "description": "Listen past sight and draw hostile pulses closer.", "charges": 2},
	{"name": "Gandr", "description": "Nail a shadow in place and buy yourself room.", "charges": 1}
]

const SPELL_WHEEL_DIRECTIONS := [
	Vector2(0.0, -1.0),
	Vector2(0.8660254, 0.5),
	Vector2(-0.8660254, 0.5)
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
var focus_mode_remaining := 0.0
var spell_input_held := false
var spell_hold_time := 0.0
var spell_wheel_open := false
var spell_cast_cooldown_remaining := 0.0
var selected_spell_index := 0
var belt_slot_charges: Array[int] = []
var attack_cooldown_remaining := 0.0
var attack_phase_time_remaining := 0.0
var attack_hitbox_active := false
var hit_targets: Array[Node] = []
var dodge_direction := Vector3.ZERO
var hrafn_phase_remaining := 0.0
var hrafn_reform_snap_pending := false
var hrafn_reform_position := Vector3.ZERO
var hrafn_reform_yaw := NAN
var hugr_pulse_remaining := 0.0
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
var previous_attack_hitbox_transform := Transform3D.IDENTITY
var combat_target: Node3D
var stealth_feedback_label := "Stillness"
var stealth_feedback_detail := "No hostile pulse nearby."
var stealth_feedback_strength := 0.0
var near_quiet_spot: Node

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
	belt_slot_charges = _get_max_belt_charges()
	var collision_shape := collision_shape_node.shape as CapsuleShape3D
	if collision_shape != null:
		standing_collision_height = collision_shape.height
	standing_collision_position = collision_shape_node.position
	standing_collision_position_y = collision_shape_node.position.y
	standing_mesh_position_y = body_mesh_node.position.y
	standing_marker_position_y = forward_marker_node.position.y
	sword_hitbox.monitoring = false
	sword_pivot.rotation_degrees = sword_rest_rotation
	previous_attack_hitbox_transform = sword_hitbox_shape_node.global_transform
	health_changed.emit(health, max_health)
	stealth_feedback_changed.emit(stealth_feedback_label, stealth_feedback_detail, stealth_feedback_strength)
	_emit_spell_selection_changed()
	_emit_belt_status_changed()
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
	if event.is_action_pressed("interact"):
		_attempt_belt_prime()
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
	if focus_mode_remaining > 0.0:
		focus_mode_remaining = maxf(focus_mode_remaining - delta, 0.0)
	if spell_cast_cooldown_remaining > 0.0:
		spell_cast_cooldown_remaining = maxf(spell_cast_cooldown_remaining - delta, 0.0)
	if hrafn_phase_remaining > 0.0:
		hrafn_phase_remaining = maxf(hrafn_phase_remaining - delta, 0.0)
	if hugr_pulse_remaining > 0.0:
		hugr_pulse_remaining = maxf(hugr_pulse_remaining - delta, 0.0)
	if spell_input_held:
		spell_hold_time += delta
		if not spell_wheel_open and spell_hold_time >= spell_wheel_hold_time:
			_set_spell_wheel_open(true)
	if is_dodging:
		dodge_time_remaining = maxf(dodge_time_remaining - delta, 0.0)
		if dodge_time_remaining <= 0.0:
			is_dodging = false
			dodge_direction = Vector3.ZERO
			if hrafn_reform_snap_pending:
				_apply_hrafn_reform_snap()
	if attack_cooldown_remaining > 0.0:
		attack_cooldown_remaining = maxf(attack_cooldown_remaining - delta, 0.0)
	_update_combat_state(delta)
	_update_feedback_state(delta)

	if is_dead:
		velocity = Vector3.ZERO
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_update_crouch_state(delta)
	_update_stealth_feedback()
	if spell_wheel_open:
		_update_spell_selection(input_vector)

	var move_direction := _get_move_direction(input_vector)

	if not spell_wheel_open and Input.is_action_just_pressed("dodge"):
		_start_dodge(move_direction)

	if not spell_wheel_open and not is_dodging and Input.is_action_just_pressed("attack") and not is_crouching:
		_start_attack()

	is_blocking = Input.is_action_pressed("block") and not is_attacking and not is_crouching and not is_dodging and not spell_wheel_open

	_update_combat_mode()
	move_direction = _get_move_direction(input_vector)

	var target_velocity := move_direction * _get_move_speed(input_vector)
	if is_dodging:
		var active_dodge_speed := dodge_speed
		if hrafn_phase_remaining > 0.0:
			active_dodge_speed = hrafn_dash_speed
		target_velocity = dodge_direction * active_dodge_speed
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
		_rotate_toward_combat_target()
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
	var next_target := _find_closest_combat_target(combat_lock_distance)
	_set_combat_mode(next_target != null, next_target)


func _set_combat_mode(next_mode: bool, next_target: Node3D) -> void:
	var target_changed := combat_target != next_target
	if not target_changed and is_in_combat_mode == next_mode:
		return

	var was_in_combat_mode := is_in_combat_mode
	is_in_combat_mode = next_mode
	combat_target = next_target
	if not is_in_combat_mode:
		combat_target = null
	elif not was_in_combat_mode:
		_snap_to_combat_target()

	if camera_rig != null and camera_rig.has_method("set_combat_mode"):
		camera_rig.set_combat_mode(is_in_combat_mode)

	combat_mode_changed.emit(is_in_combat_mode)


func _refresh_focus_mode(duration: float) -> void:
	if duration <= 0.0:
		return
	focus_mode_remaining = maxf(focus_mode_remaining, duration)


func _find_closest_combat_target(max_distance: float) -> Node3D:
	var closest_enemy: Node3D
	var closest_distance := max_distance
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_node := enemy as Node3D
		if enemy_node == null:
			continue
		if enemy.has_method("is_player_hostile") and not enemy.is_player_hostile():
			continue
		if enemy.has_method("is_attacking_player") and not enemy.is_attacking_player():
			continue

		var planar_offset := enemy_node.global_position - global_position
		planar_offset.y = 0.0
		var enemy_distance := planar_offset.length()
		if enemy_distance > closest_distance:
			continue
		closest_distance = enemy_distance
		closest_enemy = enemy_node

	return closest_enemy


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

	if is_in_combat_mode:
		return (global_basis.x * input_vector.x + global_basis.z * input_vector.y).normalized()

	if camera_rig != null and camera_rig.has_method("get_camera_planar_basis"):
		var camera_basis: Basis = camera_rig.get_camera_planar_basis()
		return (camera_basis.x * input_vector.x + camera_basis.z * input_vector.y).normalized()

	return Vector3.ZERO


func _rotate_toward_combat_target() -> void:
	var target_yaw := _get_combat_target_yaw()
	if is_nan(target_yaw):
		return
	rotation.y = target_yaw


func _snap_to_combat_target() -> void:
	_rotate_toward_combat_target()


func _get_combat_target_yaw() -> float:
	if combat_target == null or not is_instance_valid(combat_target):
		return NAN
	var target_offset := combat_target.global_position - global_position
	target_offset.y = 0.0
	if target_offset.length_squared() <= 0.0001:
		return NAN
	return Vector3.FORWARD.signed_angle_to(target_offset.normalized(), Vector3.UP)


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


func get_spell_charges() -> Array[int]:
	var spell_charges: Array[int] = []
	for slot_charge in belt_slot_charges:
		spell_charges.append(int(slot_charge))
	return spell_charges


func get_selected_spell_index() -> int:
	return selected_spell_index


func get_belt_total_charges() -> int:
	var total := 0
	for slot_charge in belt_slot_charges:
		total += int(slot_charge)
	return total


func get_belt_total_capacity() -> int:
	return _get_total_belt_capacity()


func can_reprime_belt() -> bool:
	return near_quiet_spot != null and is_instance_valid(near_quiet_spot)


func set_near_quiet_spot(next_quiet_spot: Node) -> void:
	if near_quiet_spot == next_quiet_spot:
		return

	near_quiet_spot = next_quiet_spot
	if near_quiet_spot != null and not is_instance_valid(near_quiet_spot):
		near_quiet_spot = null
	_emit_belt_status_changed()


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
	var hugr_is_active := hugr_pulse_remaining > 0.0

	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("get_heartbeat_intensity"):
			continue

		var enemy_node := enemy as Node3D
		if enemy_node == null:
			continue

		var distance_to_enemy := enemy_node.global_position.distance_to(global_position)
		var intensity := float(enemy.get_heartbeat_intensity())
		if intensity <= 0.0:
			if not hugr_is_active:
				continue
			if distance_to_enemy > hugr_scan_range:
				continue
			intensity = clampf(1.0 - distance_to_enemy / maxf(hugr_scan_range, 0.001), 0.08, 0.22)

		if intensity <= 0.0:
			continue

		if intensity > next_strength or (is_equal_approx(intensity, next_strength) and distance_to_enemy < closest_distance):
			next_strength = intensity
			closest_distance = distance_to_enemy
			if enemy.has_method("get_heartbeat_label"):
				next_label = enemy.get_heartbeat_label()
			if enemy.has_method("get_heartbeat_detail"):
				next_detail = enemy.get_heartbeat_detail()

	if next_strength <= 0.0:
		if hugr_is_active:
			next_label = "Listening"
			next_detail = "Hugr listens into the fog, but no pulse answers."
		elif is_crouching:
			next_detail = "Your breath stays low. A crouched silhouette carries less easily."
		else:
			next_detail = "No hostile pulse nearby. Standing in the open carries further."
	elif hugr_is_active:
		next_detail = "%s Hugr carries it through the fog." % next_detail

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

	var next_spell_index := _get_spell_wheel_index(input_vector)

	if next_spell_index == selected_spell_index:
		return

	selected_spell_index = next_spell_index
	_emit_spell_selection_changed()


func _emit_spell_selection_changed() -> void:
	spell_selection_changed.emit(get_spell_names(), get_spell_descriptions(), get_spell_charges(), selected_spell_index)


func _emit_belt_status_changed() -> void:
	belt_status_changed.emit(get_belt_total_charges(), _get_total_belt_capacity(), can_reprime_belt())


func _get_spell_wheel_index(input_vector: Vector2) -> int:
	if SPELL_LOADOUT.size() == SPELL_WHEEL_DIRECTIONS.size():
		var best_index := selected_spell_index
		var best_dot := -INF
		var normalized_input := input_vector.normalized()
		for direction_index: int in range(SPELL_WHEEL_DIRECTIONS.size()):
			var dot_value := normalized_input.dot(SPELL_WHEEL_DIRECTIONS[direction_index])
			if dot_value > best_dot:
				best_dot = dot_value
				best_index = direction_index
		return best_index

	if absf(input_vector.x) > absf(input_vector.y):
		return 1 if input_vector.x > 0.0 else max(SPELL_LOADOUT.size() - 1, 0)
	return 0 if input_vector.y < 0.0 else min(2, SPELL_LOADOUT.size() - 1)


func _get_max_belt_charges() -> Array[int]:
	var max_charges: Array[int] = []
	for spell_data: Dictionary in SPELL_LOADOUT:
		max_charges.append(int(spell_data.get("charges", 1)))
	return max_charges


func _get_total_belt_capacity() -> int:
	var total_capacity := 0
	for spell_data: Dictionary in SPELL_LOADOUT:
		total_capacity += int(spell_data.get("charges", 1))
	return total_capacity


func _is_belt_full() -> bool:
	for slot_index: int in range(belt_slot_charges.size()):
		if belt_slot_charges[slot_index] < int(SPELL_LOADOUT[slot_index].get("charges", 1)):
			return false
	return true


func _has_spell_charge(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < belt_slot_charges.size() and belt_slot_charges[slot_index] > 0


func _consume_spell_charge(slot_index: int) -> void:
	if not _has_spell_charge(slot_index):
		return
	belt_slot_charges[slot_index] = maxi(belt_slot_charges[slot_index] - 1, 0)


func _attempt_belt_prime() -> void:
	if not can_reprime_belt():
		return

	if _is_belt_full():
		spell_cast.emit("Hodd", "The belt is already primed.")
		_emit_belt_status_changed()
		return

	belt_slot_charges = _get_max_belt_charges()
	_emit_spell_selection_changed()
	_emit_belt_status_changed()
	var prompt_name := "The Quiet Spot"
	if near_quiet_spot != null and near_quiet_spot.has_method("get_prompt_name"):
		prompt_name = near_quiet_spot.get_prompt_name()
	spell_cast.emit("Hodd", "%s steadies your hands. The belt is re-primed." % prompt_name)


func _cast_selected_spell() -> void:
	if not _can_cast_spell():
		return

	var spell_name := String(SPELL_LOADOUT[selected_spell_index].get("name", "Spell"))
	if not _has_spell_charge(selected_spell_index):
		spell_cast.emit(spell_name, "That slot lies empty. Reach a Quiet Spot to re-prime the Hodd.")
		_emit_belt_status_changed()
		return

	var cast_result := {"success": false, "text": "Nothing happens."}
	match selected_spell_index:
		0:
			cast_result = _cast_hrafn()
		1:
			cast_result = _cast_hugr()
		2:
			cast_result = _cast_gandr()
		_:
			cast_result = {"success": false, "text": "Nothing happens."}

	spell_cast.emit(spell_name, String(cast_result.get("text", "Nothing happens.")))
	if not bool(cast_result.get("success", false)):
		return

	_refresh_focus_mode(focus_mode_rite_linger)
	spell_cast_cooldown_remaining = spell_cast_cooldown
	_consume_spell_charge(selected_spell_index)
	_emit_spell_selection_changed()
	_emit_belt_status_changed()


func _can_cast_spell() -> bool:
	if is_dead or is_attacking or is_dodging or is_crouching or is_blocking:
		return false
	if spell_wheel_open or spell_cast_cooldown_remaining > 0.0:
		return false
	return true


func _cast_hrafn() -> Dictionary:
	var hrafn_target := _find_hrafn_target()
	if hrafn_target == null:
		return {"success": false, "text": "Hrafn finds no hostile body close enough to pass through."}

	var reform_position := _get_hrafn_reform_position(hrafn_target)
	var reform_offset := reform_position - global_position
	reform_offset.y = 0.0
	var surge_direction := reform_offset.normalized()
	if reform_offset.length_squared() <= 0.0001:
		surge_direction = _get_node_forward(hrafn_target)
	is_dodging = true
	is_blocking = false
	attack_phase_time_remaining = 0.0
	hit_targets.clear()
	_set_attack_hitbox_enabled(false)
	sword_pivot.rotation_degrees = sword_rest_rotation
	previous_attack_hitbox_transform = sword_hitbox_shape_node.global_transform
	hrafn_reform_position = reform_position
	hrafn_reform_yaw = _get_yaw_for_forward(_get_node_forward(hrafn_target))
	dodge_direction = surge_direction
	dodge_time_remaining = hrafn_phase_duration
	hrafn_phase_remaining = hrafn_phase_duration
	hrafn_reform_snap_pending = true
	damage_invulnerability_remaining = maxf(damage_invulnerability_remaining, hrafn_phase_duration + 0.12)
	velocity.x = dodge_direction.x * hrafn_dash_speed
	velocity.z = dodge_direction.z * hrafn_dash_speed
	return {"success": true, "text": "Hrafn passes you through the foe and leaves you on their blind side."}


func _cast_hugr() -> Dictionary:
	hugr_pulse_remaining = maxf(hugr_pulse_remaining, hugr_pulse_duration)
	var heard_count := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_body := enemy as Node3D
		if enemy_body == null:
			continue
		if enemy_body.global_position.distance_to(global_position) <= hugr_scan_range:
			heard_count += 1

	if heard_count <= 0:
		return {"success": true, "text": "Hugr listens into the fog, but no pulse answers."}
	return {"success": true, "text": "Hugr counts %d hostile pulse%s in the dark." % [heard_count, "s" if heard_count != 1 else ""]}


func _cast_gandr() -> Dictionary:
	var target_enemy := _find_closest_enemy_in_range(gandr_range)
	if target_enemy == null:
		return {"success": false, "text": "Gandr finds no shadow close enough to nail."}
	if not target_enemy.has_method("apply_gandr_bind"):
		return {"success": false, "text": "That foe slips free of Gandr."}

	target_enemy.apply_gandr_bind(gandr_bind_duration)
	return {"success": true, "text": "Gandr nails %s in place." % target_enemy.name}


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


func _apply_hrafn_reform_snap() -> void:
	hrafn_reform_snap_pending = false
	global_position = hrafn_reform_position
	if not is_nan(hrafn_reform_yaw):
		rotation.y = hrafn_reform_yaw
	hrafn_reform_position = global_position
	hrafn_reform_yaw = NAN


func _find_hrafn_target() -> Node3D:
	if combat_target != null and is_instance_valid(combat_target):
		var target_offset := combat_target.global_position - global_position
		target_offset.y = 0.0
		if target_offset.length() <= hrafn_target_range:
			return combat_target
	return _find_closest_enemy_in_range(hrafn_target_range)


func _get_hrafn_reform_position(target_enemy: Node3D) -> Vector3:
	var enemy_forward := _get_node_forward(target_enemy)
	var reform_position := target_enemy.global_position - enemy_forward * hrafn_reform_distance
	reform_position.y = global_position.y
	return reform_position


func _get_node_forward(target_node: Node3D) -> Vector3:
	var forward := -target_node.global_basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _get_yaw_for_forward(forward: Vector3) -> float:
	if forward.length_squared() <= 0.0001:
		return rotation.y
	return Vector3.FORWARD.signed_angle_to(forward.normalized(), Vector3.UP)


func _find_closest_enemy_in_range(max_distance: float) -> Node3D:
	var closest_enemy: Node3D
	var closest_distance := max_distance
	for enemy: Node in get_tree().get_nodes_in_group("enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		var enemy_node := enemy as Node3D
		if enemy_node == null:
			continue
		if enemy.has_method("is_player_hostile") and not enemy.is_player_hostile():
			continue
		var planar_offset := enemy_node.global_position - global_position
		planar_offset.y = 0.0
		var enemy_distance := planar_offset.length()
		if enemy_distance > closest_distance:
			continue
		closest_distance = enemy_distance
		closest_enemy = enemy_node

	return closest_enemy


func _start_attack() -> void:
	if is_dead or is_attacking or is_blocking or is_dodging or spell_wheel_open or attack_cooldown_remaining > 0.0:
		return

	is_attacking = true
	_refresh_focus_mode(focus_mode_steel_linger)
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
	hrafn_phase_remaining = 0.0
	hrafn_reform_snap_pending = false
	hrafn_reform_yaw = NAN

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
		hrafn_reform_yaw = NAN
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
		if not is_enabled:
			previous_attack_hitbox_transform = sword_hitbox_shape_node.global_transform
		return

	attack_hitbox_active = is_enabled
	sword_hitbox.monitoring = is_enabled
	if not is_enabled:
		previous_attack_hitbox_transform = sword_hitbox_shape_node.global_transform


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

	var current_transform := sword_hitbox_shape_node.global_transform
	var hit_results: Array[Dictionary] = []
	var sample_count := maxi(attack_hitbox_sweep_samples, 1)
	for sample_index: int in range(sample_count + 1):
		var alpha := float(sample_index) / float(sample_count)
		var sampled_transform := previous_attack_hitbox_transform.interpolate_with(current_transform, alpha)
		hit_results.append_array(_intersect_sword_hitbox_at_transform(hitbox_shape, sampled_transform))

	previous_attack_hitbox_transform = current_transform
	return hit_results


func _intersect_sword_hitbox_at_transform(hitbox_shape: Shape3D, hitbox_transform: Transform3D) -> Array[Dictionary]:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hitbox_shape
	query.transform = hitbox_transform
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.margin = attack_hitbox_query_margin
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
	focus_mode_remaining = 0.0
	hrafn_phase_remaining = 0.0
	hrafn_reform_snap_pending = false
	hrafn_reform_yaw = NAN
	hugr_pulse_remaining = 0.0
	hit_reaction_remaining = 0.0
	block_reaction_remaining = 0.0
	_set_attack_hitbox_enabled(false)
	sword_pivot.rotation_degrees = sword_rest_rotation
	velocity = Vector3.ZERO
	died.emit()
