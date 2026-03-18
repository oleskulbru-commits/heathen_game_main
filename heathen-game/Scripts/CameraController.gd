extends Node3D

@export var target_path: NodePath = NodePath("..")
@export var focus_height := 1.6
@export var shoulder_offset := 0.85
@export var moving_shoulder_offset := 0.7
@export var vertical_offset := 0.35
@export var follow_distance := 4.4
@export var moving_follow_distance := 3.8
@export var focus_shoulder_offset := 0.65
@export var focus_moving_shoulder_offset := 0.55
@export var focus_follow_distance := 3.7
@export var focus_moving_follow_distance := 3.25
@export var mouse_sensitivity := 0.0025
@export var pitch_min_degrees := -45.0
@export var pitch_max_degrees := 30.0
@export var rig_follow_smoothing := 14.0
@export var orbit_smoothing := 16.0
@export var camera_smoothing := 18.0
@export var movement_recenter_speed := 4.0
@export var focus_movement_recenter_speed := 7.0
@export var action_recenter_speed := 9.0
@export var free_look_grace := 2.5
@export var combat_free_look_grace := 1.0
@export var turn_follow_delay := 2.5
@export var focus_turn_follow_delay := 0.2
@export var collision_margin := 0.2

@onready var yaw_pivot: Node3D = $YawPivot
@onready var pitch_pivot: Node3D = $YawPivot/PitchPivot
@onready var camera: Camera3D = $YawPivot/PitchPivot/Camera3D

var target: CharacterBody3D
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var time_since_orbit_input := 999.0
var focus_target_height := 0.0
var is_in_combat_mode := false
var base_free_look_grace := 0.0
var free_look_grace_target := 0.0
var horizontal_turn_hold_time := 0.0

func _ready() -> void:
	target = get_node_or_null(target_path) as CharacterBody3D
	if target == null:
		push_warning("CameraController could not find CharacterBody3D target.")
		return

	top_level = true
	global_position = _get_focus_position()
	yaw = target.rotation.y
	yaw_pivot.rotation.y = yaw
	pitch_pivot.rotation.x = pitch
	camera.position = Vector3(shoulder_offset, vertical_offset, follow_distance)
	focus_target_height = focus_height
	base_free_look_grace = free_look_grace
	free_look_grace_target = free_look_grace

func _unhandled_input(event: InputEvent) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		if _has_movement_input():
			time_since_orbit_input = 0.0
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clamp(
			pitch - event.relative.y * mouse_sensitivity,
			deg_to_rad(pitch_min_degrees),
			deg_to_rad(pitch_max_degrees)
		)

func _physics_process(delta: float) -> void:
	if target == null:
		return

	time_since_orbit_input += delta
	free_look_grace = lerpf(free_look_grace, free_look_grace_target, _smooth_weight(6.0, delta))
	focus_height = lerpf(focus_height, focus_target_height, _smooth_weight(rig_follow_smoothing, delta))
	global_position = global_position.lerp(_get_focus_position(), _smooth_weight(rig_follow_smoothing, delta))
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_horizontal_turning := absf(input_vector.x) > 0.1 and absf(input_vector.x) >= absf(input_vector.y)
	if is_horizontal_turning:
		horizontal_turn_hold_time += delta
	else:
		horizontal_turn_hold_time = 0.0

	var move_speed := Vector2(target.velocity.x, target.velocity.z).length()
	var target_speed := _get_target_reference_speed(input_vector)
	var move_ratio: float = clamp(move_speed / max(target_speed, 0.001), 0.0, 1.0)
	var active_turn_follow_delay := _get_active_turn_follow_delay()
	if move_ratio > 0.05 and time_since_orbit_input > free_look_grace and (not is_horizontal_turning or horizontal_turn_hold_time >= active_turn_follow_delay):
		yaw = lerp_angle(yaw, target.rotation.y, _smooth_weight(_get_active_movement_recenter_speed(), delta))

	yaw_pivot.rotation.y = lerp_angle(yaw_pivot.rotation.y, yaw, _smooth_weight(orbit_smoothing, delta))
	pitch_pivot.rotation.x = lerp_angle(pitch_pivot.rotation.x, pitch, _smooth_weight(orbit_smoothing, delta))

	var desired_local := Vector3(
		lerp(_get_active_shoulder_offset(), _get_active_moving_shoulder_offset(), move_ratio),
		vertical_offset,
		lerp(_get_active_follow_distance(), _get_active_moving_follow_distance(), move_ratio)
	)
	var safe_local := _get_safe_camera_local_position(desired_local)
	camera.position = camera.position.lerp(safe_local, _smooth_weight(camera_smoothing, delta))

func get_camera_planar_basis() -> Basis:
	return Basis(Vector3.UP, yaw_pivot.global_rotation.y)

func set_focus_height(new_focus_height: float) -> void:
	focus_target_height = new_focus_height


func set_combat_mode(next_mode: bool) -> void:
	is_in_combat_mode = next_mode
	if is_in_combat_mode:
		free_look_grace_target = combat_free_look_grace
	else:
		free_look_grace_target = base_free_look_grace
	horizontal_turn_hold_time = 0.0

func _has_movement_input() -> bool:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO

func _get_target_reference_speed(input_vector: Vector2) -> float:
	if is_in_combat_mode:
		return float(target.get("combat_move_speed"))
	if bool(target.get("is_crouching")):
		return float(target.get("crouch_speed"))
	if Input.is_action_pressed("sprint") and input_vector.y < 0.0:
		return float(target.get("sprint_speed"))
	return float(target.get("speed"))

func _get_active_shoulder_offset() -> float:
	return focus_shoulder_offset if is_in_combat_mode else shoulder_offset

func _get_active_moving_shoulder_offset() -> float:
	return focus_moving_shoulder_offset if is_in_combat_mode else moving_shoulder_offset

func _get_active_follow_distance() -> float:
	return focus_follow_distance if is_in_combat_mode else follow_distance

func _get_active_moving_follow_distance() -> float:
	return focus_moving_follow_distance if is_in_combat_mode else moving_follow_distance

func _get_active_movement_recenter_speed() -> float:
	return focus_movement_recenter_speed if is_in_combat_mode else movement_recenter_speed

func _get_active_turn_follow_delay() -> float:
	return focus_turn_follow_delay if is_in_combat_mode else turn_follow_delay

func _get_focus_position() -> Vector3:
	return target.global_position + Vector3.UP * focus_height

func _get_safe_camera_local_position(desired_local: Vector3) -> Vector3:
	var from := global_position
	var to := pitch_pivot.to_global(desired_local)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [target.get_rid()]
	query.collide_with_areas = false

	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return desired_local

	var hit_position: Vector3 = result.position
	var safe_distance: float = max(from.distance_to(hit_position) - collision_margin, 1.1)
	var safe_world: Vector3 = from + from.direction_to(to) * safe_distance
	return pitch_pivot.to_local(safe_world)

func _smooth_weight(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
