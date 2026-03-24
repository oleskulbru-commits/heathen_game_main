extends CharacterBody3D

signal awareness_changed(state: String, message: String)

@export var patrol_speed: float = 2.2
@export var chase_speed: float = 4.1
@export var detection_range: float = 13.0
@export var attack_range: float = 1.55
@export var attack_cooldown: float = 1.15
@export var suspicion_duration: float = 2.5
@export var suspicion_pause_duration: float = 0.45
@export var search_duration: float = 2.8
@export var leash_radius: float = 8.0
@export var fall_reset_depth: float = 5.0
@export var max_health: float = 2.0

@onready var visuals: Node3D = $Visuals
@onready var body_mesh: MeshInstance3D = $Visuals/Body
@onready var head_mesh: MeshInstance3D = $Visuals/Head
@onready var patrol_root: Node3D = $PatrolPoints

var _player: Node3D = null
var _patrol_points: Array[Node3D] = []
var _patrol_index: int = 0
var _state: String = ""
var _attack_cooldown_timer: float = 0.0
var _lost_sight_timer: float = 0.0
var _reveal_timer: float = 0.0
var _state_timer: float = 0.0
var _health: float = 0.0
var _home_position: Vector3 = Vector3.ZERO
var _last_known_player_position: Vector3 = Vector3.ZERO
var _body_material: StandardMaterial3D
var _head_material: StandardMaterial3D
var _indicator_material: StandardMaterial3D
var _indicator_mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("hostile")
	add_to_group("omen_revealable")
	for child in patrol_root.get_children():
		if child is Node3D:
			_patrol_points.append(child)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	_lost_sight_timer = suspicion_duration
	_health = max_health
	_home_position = global_position
	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 1.0
	_body_material.emission_enabled = true
	_body_material.emission = Color(0.18, 0.08, 0.04)
	_body_material.emission_energy_multiplier = 0.45
	_head_material = StandardMaterial3D.new()
	_head_material.roughness = 1.0
	_head_material.emission_enabled = true
	_head_material.emission = Color(0.18, 0.08, 0.04)
	_head_material.emission_energy_multiplier = 0.25
	body_mesh.material_override = _body_material
	head_mesh.material_override = _head_material
	_create_awareness_indicator()
	_set_state("patrol")

func _physics_process(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
	if _state_timer > 0.0:
		_state_timer -= delta
	if _reveal_timer > 0.0:
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			_apply_state_visuals()

	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	if global_position.y < _home_position.y - fall_reset_depth:
		_reset_to_home()
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	match _state:
		"patrol":
			_process_patrol(delta)
			if _can_detect_player():
				_enter_suspicion(_player.global_position, true)
		"suspicious":
			_process_suspicious(delta)
		"chase":
			_process_chase(delta)
		"search":
			_process_search(delta)

	move_and_slide()
	_update_facing()

func _process_patrol(delta: float) -> void:
	if _patrol_points.is_empty():
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		return
	var target := _clamp_to_leash(_patrol_points[_patrol_index].global_position)
	_move_toward(target, patrol_speed, delta)
	if global_position.distance_to(target) < 0.6:
		_patrol_index = (_patrol_index + 1) % _patrol_points.size()

func _process_suspicious(delta: float) -> void:
	if _can_detect_player() and _state_timer <= 0.0:
		_set_state("chase", "The enforcer sees you and surges forward.")
		_lost_sight_timer = suspicion_duration
		return
	if _state_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
		_face_toward(_last_known_player_position)
		return
	_move_toward(_clamp_to_leash(_last_known_player_position), patrol_speed * 1.2, delta)
	_lost_sight_timer -= delta
	if _lost_sight_timer <= 0.0 or global_position.distance_to(_last_known_player_position) < 0.75:
		_enter_search(_last_known_player_position)

func _process_chase(delta: float) -> void:
	if _player == null:
		_set_state("patrol")
		return
	var player_position := _player.global_position
	var distance := global_position.distance_to(player_position)
	_last_known_player_position = player_position
	if _is_outside_leash(player_position):
		_enter_search(_home_position)
		return
	if distance > detection_range * 1.5:
		_enter_search(player_position)
		return
	if not _has_line_of_sight(player_position + Vector3.UP):
		_lost_sight_timer -= delta
		if _lost_sight_timer <= 0.0:
			_enter_search(player_position)
	else:
		_lost_sight_timer = suspicion_duration
	_move_toward(_clamp_to_leash(player_position), chase_speed, delta)
	if distance <= attack_range:
		_try_attack_player()

func _process_search(delta: float) -> void:
	if _can_detect_player():
		_set_state("chase", "You are exposed. The enforcer commits to the chase.")
		_lost_sight_timer = suspicion_duration
		return
	_move_toward(_clamp_to_leash(_last_known_player_position), patrol_speed * 1.05, delta)
	_face_toward(_last_known_player_position)
	if _state_timer <= 0.0:
		_set_state("patrol", "The enforcer loses your trail and settles back into patrol.")

func _move_toward(target: Vector3, speed: float, delta: float) -> void:
	var direction := target - global_position
	direction.y = 0.0
	if direction.length() > 0.05:
		direction = direction.normalized()
		velocity.x = move_toward(velocity.x, direction.x * speed, 10.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, 10.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

func _can_detect_player() -> bool:
	if _player == null:
		return false
	var offset := _player.global_position - global_position
	var flat_offset := Vector3(offset.x, 0.0, offset.z)
	var distance := flat_offset.length()
	if distance > detection_range or distance <= 0.05:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	if forward.dot(flat_offset.normalized()) < -0.25 and distance > 3.0:
		return false
	return _has_line_of_sight(_player.global_position + Vector3.UP)

func _try_attack_player() -> void:
	if _attack_cooldown_timer > 0.0:
		return
	_attack_cooldown_timer = attack_cooldown
	if _player != null and _player.has_method("take_damage"):
		_player.take_damage(25.0, global_position)

func _enter_suspicion(target_position: Vector3, from_patrol: bool = false) -> void:
	_set_state("suspicious", "The enforcer pauses and listens toward the trail.")
	_last_known_player_position = _clamp_to_leash(target_position)
	_lost_sight_timer = suspicion_duration
	_state_timer = suspicion_pause_duration if from_patrol else 0.0

func _enter_search(target_position: Vector3) -> void:
	_set_state("search", "The enforcer searches where he last saw movement.")
	_last_known_player_position = _clamp_to_leash(target_position)
	_state_timer = search_duration

func _clamp_to_leash(target_position: Vector3) -> Vector3:
	var offset := target_position - _home_position
	offset.y = 0.0
	if offset.length() <= leash_radius:
		return Vector3(target_position.x, _home_position.y, target_position.z)
	offset = offset.normalized() * leash_radius
	return Vector3(_home_position.x + offset.x, _home_position.y, _home_position.z + offset.z)

func _is_outside_leash(target_position: Vector3) -> bool:
	var offset := target_position - _home_position
	offset.y = 0.0
	return offset.length() > leash_radius

func _reset_to_home() -> void:
	global_position = _home_position
	velocity = Vector3.ZERO
	_set_state("patrol")
	_lost_sight_timer = suspicion_duration
	_state_timer = 0.0

func _has_line_of_sight(target_position: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target_position)
	query.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == _player

func reveal_from_omen(duration: float = 3.0) -> void:
	_reveal_timer = maxf(_reveal_timer, duration)
	_apply_tint(Color(0.73, 0.25, 0.14))

func take_damage(amount: float) -> void:
	_health -= amount
	reveal_from_omen(0.5)
	if _health <= 0.0:
		queue_free()

func _apply_tint(color: Color) -> void:
	_body_material.albedo_color = color
	_head_material.albedo_color = color.lightened(0.2)

func _apply_state_visuals() -> void:
	match _state:
		"patrol":
			_apply_tint(Color(0.5, 0.41, 0.3))
			_set_indicator(Color(0.0, 0.0, 0.0, 0.0), false)
		"suspicious":
			_apply_tint(Color(0.72, 0.56, 0.26))
			_set_indicator(Color(0.94, 0.72, 0.24), true)
		"search":
			_apply_tint(Color(0.66, 0.48, 0.22))
			_set_indicator(Color(0.95, 0.58, 0.2), true)
		"chase":
			_apply_tint(Color(0.76, 0.24, 0.18))
			_set_indicator(Color(0.95, 0.2, 0.14), true)

func _set_state(new_state: String, message: String = "") -> void:
	if _state == new_state:
		return
	_state = new_state
	if _reveal_timer <= 0.0:
		_apply_state_visuals()
	if message != "":
		awareness_changed.emit(new_state, message)

func _create_awareness_indicator() -> void:
	_indicator_material = StandardMaterial3D.new()
	_indicator_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_indicator_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_indicator_material.emission_enabled = true
	_indicator_material.emission_energy_multiplier = 1.8
	_indicator_mesh = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.12
	marker_mesh.height = 0.24
	_indicator_mesh.mesh = marker_mesh
	_indicator_mesh.material_override = _indicator_material
	_indicator_mesh.position = Vector3(0.0, 2.05, 0.0)
	_indicator_mesh.visible = false
	visuals.add_child(_indicator_mesh)

func _set_indicator(color: Color, visible: bool) -> void:
	if _indicator_mesh == null or _indicator_material == null:
		return
	_indicator_mesh.visible = visible
	_indicator_material.albedo_color = color
	_indicator_material.emission = color

func _face_toward(target_position: Vector3) -> void:
	var offset := target_position - global_position
	offset.y = 0.0
	if offset.length() > 0.05:
		visuals.look_at(global_position + offset, Vector3.UP, true)

func _update_facing() -> void:
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length() > 0.1:
		visuals.look_at(global_position + flat_velocity, Vector3.UP, true)