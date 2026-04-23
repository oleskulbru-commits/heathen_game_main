class_name PlayerCamera
extends Node
## Handles orbit camera, handheld shake, focus-mode zoom, heartbeat audio,
## camera trauma, and auto-follow recentering.

signal focus_changed(active: bool)

@export var mouse_sensitivity: float = 0.0025
@export_group("Focus Mode")
@export var focus_zoom_fov: float = 35.0
@export var focus_zoom_speed: float = 3.0
@export var focus_arm_length: float = 2.0
@export var heartbeat_sound: AudioStream
@export_group("Handheld Shake")
@export var shake_intensity: float = 0.015
@export var shake_speed: float = 0.00125
@export_group("Camera Auto-Follow")
@export var follow_yaw_speed: float = 1.5
@export var follow_sprint_speed: float = 3.0
@export var follow_mouse_delay: float = 1.0
@export var follow_deadzone_deg: float = 10.0

var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0
var _shake_noise: FastNoiseLite
var _shake_time: float = 0.0
var _mouse_idle_time: float = 10.0
var _camera_trauma: float = 0.0
var _focus_active: bool = false
var _default_fov: float
var _default_arm_length: float
var _pivot: Node3D
var _spring_arm: SpringArm3D
var _camera: Camera3D
var _heartbeat_player: AudioStreamPlayer
var _heartbeat_tween: Tween


func _ready() -> void:
	var player := get_parent() as CharacterBody3D
	if not player:
		return
	_pivot = player.get_node_or_null("CameraPivot") as Node3D
	_spring_arm = player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	_camera = player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if _camera:
		_default_fov = _camera.fov
	if _spring_arm:
		_default_arm_length = _spring_arm.spring_length
	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.bus = &"Master"
	_heartbeat_player.volume_db = -80.0
	player.add_child(_heartbeat_player)
	_shake_noise = FastNoiseLite.new()
	_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_shake_noise.frequency = 0.8
	_shake_noise.seed = randi()


func handle_mouse_input(event: InputEventMouseMotion) -> void:
	_cam_yaw -= event.relative.x * mouse_sensitivity
	_cam_pitch -= event.relative.y * mouse_sensitivity
	_cam_pitch = clampf(_cam_pitch, deg_to_rad(-60.0), deg_to_rad(35.0))
	if _pivot:
		_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	_mouse_idle_time = 0.0


func update_shake(delta: float) -> void:
	_shake_time += delta * shake_speed
	var yaw_offset := _shake_noise.get_noise_2d(_shake_time * 80.0, 0.0) * shake_intensity
	var pitch_offset := _shake_noise.get_noise_2d(0.0, _shake_time * 80.0) * shake_intensity
	var roll_offset := _shake_noise.get_noise_2d(_shake_time * 60.0, _shake_time * 60.0) * shake_intensity * 0.5
	if _camera_trauma > 0.0:
		var trauma_sq := _camera_trauma * _camera_trauma
		yaw_offset += _shake_noise.get_noise_2d(_shake_time * 300.0, 100.0) * trauma_sq * 0.08
		pitch_offset += _shake_noise.get_noise_2d(100.0, _shake_time * 300.0) * trauma_sq * 0.08
		roll_offset += _shake_noise.get_noise_2d(_shake_time * 250.0, _shake_time * 250.0) * trauma_sq * 0.04
		_camera_trauma = maxf(_camera_trauma - delta * 2.0, 0.0)
	if _camera:
		_camera.rotation = Vector3(pitch_offset, yaw_offset, roll_offset)


func update_auto_follow(char_forward: Vector3, moving: bool, sprinting: bool, in_combat: bool, delta: float) -> void:
	_mouse_idle_time += delta
	if not moving or in_combat or _mouse_idle_time < follow_mouse_delay:
		return
	var fwd := char_forward
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		return
	var desired_yaw := atan2(-fwd.x, -fwd.z)
	var yaw_diff := angle_difference(_cam_yaw, desired_yaw)
	if abs(yaw_diff) < deg_to_rad(follow_deadzone_deg):
		return
	var speed := follow_sprint_speed if sprinting else follow_yaw_speed
	_cam_yaw += yaw_diff * clampf(speed * delta, 0.0, 1.0)
	if _pivot:
		_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)


func update_focus(delta: float, in_combat: bool, is_blocking: bool) -> void:
	var wants_focus := Input.is_action_pressed("focus")
	if in_combat or is_blocking:
		wants_focus = false
	if wants_focus != _focus_active:
		_focus_active = wants_focus
		focus_changed.emit(_focus_active)
		_update_heartbeat()
	var t := clampf(focus_zoom_speed * delta, 0.0, 1.0)
	var target_fov := focus_zoom_fov if _focus_active else _default_fov
	var target_arm := focus_arm_length if _focus_active else _default_arm_length
	if _camera:
		_camera.fov = lerpf(_camera.fov, target_fov, t)
	if _spring_arm:
		_spring_arm.spring_length = lerpf(_spring_arm.spring_length, target_arm, t)


func apply_trauma(amount: float) -> void:
	_camera_trauma = clampf(_camera_trauma + amount, 0.0, 1.0)


func is_focused() -> bool:
	return _focus_active


func get_cam_basis() -> Basis:
	return _pivot.global_transform.basis if _pivot else Basis.IDENTITY


func reset_for_death() -> void:
	_focus_active = false
	_update_heartbeat()


func _update_heartbeat() -> void:
	if _heartbeat_tween:
		_heartbeat_tween.kill()
	if _focus_active:
		if heartbeat_sound and not _heartbeat_player.playing:
			_heartbeat_player.stream = heartbeat_sound
			_heartbeat_player.play()
		_heartbeat_tween = _heartbeat_player.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		_heartbeat_tween.tween_property(_heartbeat_player, "volume_db", -6.0, 0.6)
	else:
		_heartbeat_tween = _heartbeat_player.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_heartbeat_tween.tween_property(_heartbeat_player, "volume_db", -80.0, 0.4)
		_heartbeat_tween.tween_callback(_heartbeat_player.stop)
