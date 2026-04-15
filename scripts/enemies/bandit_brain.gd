extends Node
## Central decision/state coordinator for a bandit.
## Owns suspicion, alert level, last-known-position memory, group callouts,
## heightened-awareness timers, and search navigation. Perception feeds it
## stimuli; other modules consume its signals/state.

signal alert_level_changed(level: int)
signal suspicion_changed(value: float)
signal entered_combat()
signal player_lost_in_darkness(last_known_pos: Vector3)
signal heard_noise(source_pos: Vector3)
signal emotional_state_changed(new_state: int)
@warning_ignore("unused_signal")
signal call_for_help(caller: CharacterBody3D, caller_pos: Vector3)

const StealthGridScript := preload("res://scripts/enemies/stealth_nav_grid.gd")

enum Emotion { NORMAL, TERRIFIED, ENRAGED }

@export var threshold_curious: float = 0.3
@export var threshold_alert: float = 0.6
@export var threshold_combat: float = 0.75
@export var lkp_arrive_radius: float = 2.0
@export var alert_decay_time: float = 8.0
@export var pursuit_projection_dist: float = 8.0
@export var heightened_duration: float = 30.0
@export var heightened_sight_mult: float = 1.3
@export var heightened_fov_bonus: float = 20.0
@export var deescalate_time: float = 4.0
@export_group("Emotional State")
@export var terror_duration: float = 6.0
@export var enrage_duration: float = 30.0

var alert_level: int = 0
var suspicion: float = 0.0
var last_known_positions: Array[Vector3] = []
var emotion: Emotion = Emotion.NORMAL
var is_dead: bool = false

var _bandit: CharacterBody3D
var _torch_search: Node
var _player_visible_last_frame: bool = false
var _player_position: Vector3 = Vector3.INF
var _player_last_velocity: Vector3 = Vector3.ZERO
var _exposure: float = 0.0
var _decay_timer: float = 0.0
var _deescalate_timer: float = 0.0
var _heightened_timer: float = 0.0
var _stealth_grid = null
var _stealth_waypoints: PackedVector3Array = PackedVector3Array()
var _stealth_wp_index: int = 0
var _stealth_target: Vector3 = Vector3.INF
var _stealth_age: float = 0.0
var _emotion_timer: float = 0.0

const _STEALTH_WP_ARRIVE := 2.5
const _STEALTH_REBUILD_TIME := 10.0


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	if _bandit:
		_torch_search = _bandit.get_node_or_null("BanditTorchSearch")


func _physics_process(delta: float) -> void:
	if not _bandit:
		return

	if _heightened_timer > 0.0:
		_heightened_timer = maxf(_heightened_timer - delta, 0.0)

	if _emotion_timer > 0.0:
		_emotion_timer = maxf(_emotion_timer - delta, 0.0)
		if _emotion_timer <= 0.0:
			_set_emotion(Emotion.NORMAL)

	if _torch_search and _torch_search.has_method("is_searching") and _torch_search.is_searching():
		return
	if alert_level == 3 and _player_visible_last_frame:
		return
	if alert_level < 1 or last_known_positions.is_empty() or not _bandit.has_method("set_target"):
		return

	var target := last_known_positions[0]
	var dist := _bandit.global_position.distance_to(target)
	if dist < lkp_arrive_radius:
		last_known_positions.pop_front()
		_clear_stealth_path()
		if last_known_positions.is_empty() and suspicion <= 0.0:
			player_lost_in_darkness.emit(target)
		return

	if alert_level == 1:
		_navigate_stealth(target, delta)
	else:
		_bandit.set_target(target)


func update_player_state(position: Vector3, velocity: Vector3) -> void:
	_player_position = position
	_player_last_velocity = velocity


func set_visual_contact(visible: bool) -> void:
	_player_visible_last_frame = visible


func has_visual_contact() -> bool:
	return _player_visible_last_frame


func is_aggroed() -> bool:
	return alert_level >= 3


func get_player_position() -> Vector3:
	return _player_position


func get_player_distance() -> float:
	if not _bandit or _player_position == Vector3.INF:
		return INF
	return _bandit.global_position.distance_to(_player_position)


func remember_last_known_position(position: Vector3, replace_last: bool = false) -> void:
	if replace_last and not last_known_positions.is_empty():
		last_known_positions[-1] = position
		return
	if last_known_positions.is_empty() or last_known_positions[-1].distance_to(position) > 2.0:
		last_known_positions.append(position)


func emit_heard_noise(source_pos: Vector3) -> void:
	heard_noise.emit(source_pos)


func update_exposure(visible: bool, delta: float, buildup_rate: float, drain_rate: float) -> void:
	if visible:
		_exposure = minf(_exposure + buildup_rate * delta, 1.0)
	else:
		_exposure = maxf(_exposure - drain_rate * delta, 0.0)


func get_exposure() -> float:
	return _exposure


func get_heightened_sight_multiplier() -> float:
	return heightened_sight_mult if _heightened_timer > 0.0 else 1.0


func get_heightened_fov_bonus() -> float:
	return heightened_fov_bonus if _heightened_timer > 0.0 else 0.0


func apply_suspicion(next_suspicion: float, delta: float, has_stimulus: bool) -> void:
	suspicion = clampf(next_suspicion, 0.0, 1.0)
	suspicion_changed.emit(suspicion)
	if has_stimulus:
		_decay_timer = 0.0

	var new_level := 0
	if suspicion >= threshold_combat:
		new_level = 3
	elif suspicion >= threshold_alert:
		new_level = 2
	elif suspicion >= threshold_curious:
		new_level = 1

	if new_level > alert_level:
		alert_level = new_level
		_deescalate_timer = 0.0
		alert_level_changed.emit(alert_level)
		if alert_level == 3:
			entered_combat.emit()
			_call_nearby_bandits()
	elif new_level < alert_level:
		_deescalate_timer += delta
		if _deescalate_timer >= deescalate_time:
			_deescalate_timer = 0.0
			alert_level = maxi(alert_level - 1, new_level)
			alert_level_changed.emit(alert_level)
	else:
		_deescalate_timer = 0.0

	if suspicion <= 0.0 and alert_level > 0:
		_decay_timer += delta
		if _decay_timer >= alert_decay_time:
			var old_level := alert_level
			_decay_timer = 0.0
			alert_level = maxi(alert_level - 1, 0)
			alert_level_changed.emit(alert_level)

			if old_level == 3 and alert_level == 2:
				if not last_known_positions.is_empty() and _player_last_velocity.length() > 0.5:
					var projected := last_known_positions[-1] + _player_last_velocity.normalized() * pursuit_projection_dist
					last_known_positions.insert(0, projected)

			if alert_level == 0:
				if not last_known_positions.is_empty():
					player_lost_in_darkness.emit(last_known_positions[-1])
				last_known_positions.clear()
				_start_heightened_awareness()


func force_combat(player_pos: Vector3) -> void:
	suspicion = 1.0
	_decay_timer = 0.0
	_deescalate_timer = 0.0
	if last_known_positions.is_empty():
		last_known_positions.append(player_pos)
	else:
		last_known_positions[-1] = player_pos
	suspicion_changed.emit(suspicion)
	if alert_level >= 3:
		return
	alert_level = 3
	alert_level_changed.emit(3)
	entered_combat.emit()
	_call_nearby_bandits()


func report_body_found(body_pos: Vector3) -> void:
	remember_last_known_position(body_pos)
	force_combat(body_pos)


func receive_group_call(search_pos: Vector3, shared_lkps: Array[Vector3]) -> void:
	suspicion = 1.0
	_decay_timer = 0.0
	_deescalate_timer = 0.0
	last_known_positions.clear()
	if search_pos != Vector3.INF:
		last_known_positions.append(search_pos)
	if not shared_lkps.is_empty():
		last_known_positions.append_array(shared_lkps)
	suspicion_changed.emit(suspicion)
	if alert_level >= 3:
		return
	alert_level = 3
	alert_level_changed.emit(3)
	entered_combat.emit()


func reset_alert() -> void:
	alert_level = 0
	suspicion = 0.0
	last_known_positions.clear()
	_decay_timer = 0.0
	_deescalate_timer = 0.0
	_heightened_timer = 0.0
	_player_last_velocity = Vector3.ZERO
	_player_position = Vector3.INF
	_player_visible_last_frame = false
	_exposure = 0.0
	_clear_stealth_path()
	alert_level_changed.emit(0)
	suspicion_changed.emit(0.0)


# --- Emotional state ---

func apply_terror(duration_override: float = -1.0) -> void:
	var dur := duration_override if duration_override > 0.0 else terror_duration
	_set_emotion(Emotion.TERRIFIED)
	_emotion_timer = dur


func apply_enrage(duration_override: float = -1.0) -> void:
	var dur := duration_override if duration_override > 0.0 else enrage_duration
	_set_emotion(Emotion.ENRAGED)
	_emotion_timer = dur
	if alert_level < 3:
		force_combat(_player_position if _player_position != Vector3.INF else _bandit.global_position)


func clear_emotion() -> void:
	_set_emotion(Emotion.NORMAL)
	_emotion_timer = 0.0


func is_terrified() -> bool:
	return emotion == Emotion.TERRIFIED


func is_enraged() -> bool:
	return emotion == Emotion.ENRAGED


func _set_emotion(new_emotion: Emotion) -> void:
	if emotion == new_emotion:
		return
	emotion = new_emotion
	emotional_state_changed.emit(int(new_emotion))


func _start_heightened_awareness() -> void:
	_heightened_timer = heightened_duration


func _clear_stealth_path() -> void:
	_stealth_waypoints = PackedVector3Array()
	_stealth_wp_index = 0
	_stealth_target = Vector3.INF
	_stealth_grid = null
	_stealth_age = 0.0


func _navigate_stealth(target: Vector3, delta: float) -> void:
	_stealth_age += delta
	var needs_rebuild := _stealth_waypoints.is_empty() \
		or _stealth_target.distance_to(target) > 4.0 \
		or _stealth_age >= _STEALTH_REBUILD_TIME

	if needs_rebuild:
		_stealth_grid = StealthGridScript.new()
		var mid := (_bandit.global_position + target) * 0.5
		_stealth_grid.build(mid, _bandit.get_world_3d(), _bandit.get_tree())
		if _stealth_grid.is_valid():
			_stealth_waypoints = _stealth_grid.get_stealth_path(_bandit.global_position, target)
			_stealth_wp_index = 0
			_stealth_target = target
			_stealth_age = 0.0
		else:
			_stealth_waypoints = PackedVector3Array()

	if _stealth_waypoints.is_empty():
		_bandit.set_target(target)
		return

	if _stealth_wp_index >= _stealth_waypoints.size():
		_bandit.set_target(target)
		_stealth_waypoints = PackedVector3Array()
		return

	var wp := _stealth_waypoints[_stealth_wp_index]
	var wp_dist := _bandit.global_position.distance_to(wp)
	if wp_dist < _STEALTH_WP_ARRIVE:
		_stealth_wp_index += 1
		if _stealth_wp_index >= _stealth_waypoints.size():
			_bandit.set_target(target)
			_stealth_waypoints = PackedVector3Array()
			return
		wp = _stealth_waypoints[_stealth_wp_index]
	_bandit.set_target(wp)


func _call_nearby_bandits() -> void:
	if not _bandit:
		return
	var call_range := 40.0
	var nearby: Array[Node] = []
	for node in get_tree().get_nodes_in_group("bandit"):
		if node == _bandit:
			continue
		if node.global_position.distance_to(_bandit.global_position) <= call_range:
			nearby.append(node)

	var search_center := last_known_positions[-1] if not last_known_positions.is_empty() else _bandit.global_position
	var distributed := _distribute_search_positions(search_center, nearby.size())
	var shared_lkps: Array[Vector3] = []
	shared_lkps.append_array(last_known_positions)

	for i in nearby.size():
		var node := nearby[i]
		var brain := node.get_node_or_null("BanditBrain")
		if brain and brain.alert_level < 3:
			var search_pos := distributed[i] if i < distributed.size() else Vector3.INF
			brain.receive_group_call(search_pos, shared_lkps)


func _distribute_search_positions(center: Vector3, count: int) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if count <= 0:
		return positions
	var radius := 8.0
	for i in count:
		var angle_rad := TAU * float(i) / float(count)
		var offset := Vector3(cos(angle_rad) * radius, 0.0, sin(angle_rad) * radius)
		positions.append(center + offset)
	return positions