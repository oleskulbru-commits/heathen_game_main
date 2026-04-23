extends Node
## Ambient patrol for bandits.
## If torch waypoints are placed in the scene, the bandit walks a guard route
## between them, lingering at each.
## If no torches are present, the bandit stands idle at his post and only
## wanders briefly at random intervals — like a real camp guard at rest.
## Pauses when alert_level > 0 or BanditTorchSearch is active.

@export var patrol_speed: float = 2.5
@export var arrive_radius: float = 2.0
@export var min_linger_anims: int = 1
@export var max_linger_anims: int = 2

## Range for random idle time between wanders (seconds). Only used when no torches exist.
@export var wander_interval_min: float = 40.0
@export var wander_interval_max: float = 90.0
## How far from home the bandit wanders when he decides to move.
@export var wander_radius: float = 6.0
## Only torches within this distance of the bandit's spawn are added to his patrol route.
## Prevents a guard posted at the longhouse from walking to the dock torch.
@export var patrol_radius: float = 30.0
## Reject snapped floor anchors that land too far from the torch they came from.
@export var waypoint_snap_tolerance: float = 4.0
## Merge nearby torch anchors so a cluster of decorative flames does not become a zero-length route.
@export var waypoint_merge_radius: float = 2.5
## If distance to the current waypoint is not improving for this long, skip or abandon it.
@export var walk_stuck_timeout: float = 2.5
## Minimum horizontal progress that resets the stuck timer while walking.
@export var walk_progress_epsilon: float = 0.15

const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")
const DEFAULT_BANDIT_MOVE_SPEED := 3.5



## POSTED = standing idle at home post (no-torch default)
enum State { INACTIVE, WALKING, LINGERING, POSTED }

var _state: State = State.INACTIVE
var _has_torch_route: bool = false   # true when real torch waypoints were found
var _wander_timer: float = 0.0       # counts down; when 0 bandit does a short wander
var _wander_returning: bool = false  # true when walking back home after a wander
var _bandit: CharacterBody3D
var _nav_agent: NavigationAgent3D
var _brain: Node
var _torch_search: Node
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _skeleton: Skeleton3D
var _waypoints: Array[Vector3] = []
var _current_wp: int = 0
var _linger_anim_count: int = 0
var _linger_max_anims: int = 1
var _normal_speed: float
var _last_walk_dist: float = INF
var _walk_stuck_time: float = 0.0
var _pending_waypoint_build: bool = false


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	if not _bandit:
		return

	_nav_agent = _bandit.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	_brain = _bandit.get_node_or_null("BanditBrain")
	_torch_search = _bandit.get_node_or_null("BanditTorchSearch")

	var nodes := BanditShared.resolve_visual_nodes(_bandit)
	_anim_player = nodes["anim_player"]
	_anim_tree = nodes["anim_tree"]
	_skeleton = nodes["skeleton"]

	_normal_speed = _get_bandit_move_speed()

	BanditShared.load_searching_library(_anim_player)

	# Wait one frame so all torches are in the tree.
	await get_tree().process_frame
	_pending_waypoint_build = true
	_try_finish_waypoint_build()

	if _has_torch_route:
		# Real patrol route — start walking immediately
		_find_nearest_waypoint()
		_change_state(State.WALKING)
	else:
		# No torches: stand at post, wander occasionally
		_reset_wander_timer()
		_change_state(State.POSTED)


func _physics_process(_delta: float) -> void:
	if _pending_waypoint_build:
		_try_finish_waypoint_build()

	# Auto pause / resume based on alert and search state
	var should_pause := false
	if _brain and _brain.alert_level > 0:
		should_pause = true
	if _torch_search and _torch_search.is_searching():
		should_pause = true

	if should_pause:
		if _state != State.INACTIVE:
			_pause()
		return

	if _state == State.INACTIVE:
		_resume()
		return

	match _state:
		State.WALKING:
			_process_walking(_delta)
		State.LINGERING:
			_process_lingering()
		State.POSTED:
			_process_posted(_delta)


func _process_walking(delta: float) -> void:
	if _waypoints.is_empty():
		return
	var target := _waypoints[_current_wp]
	var dist := _horizontal_distance(_bandit.global_position, target)
	_track_walk_progress(dist, delta)
	var nav_finished: bool = _nav_agent.is_navigation_finished() if _nav_agent else true
	if _has_torch_route and nav_finished and dist < arrive_radius:
		_change_state(State.LINGERING)
		return
	if _has_torch_route and _walk_stuck_time >= walk_stuck_timeout:
		if dist < arrive_radius * 1.5:
			_change_state(State.LINGERING)
		else:
			_skip_blocked_waypoint()
		return
	if dist < arrive_radius:
		if not _has_torch_route:
			# Wander trip complete — return home or stand at post
			if _wander_returning:
				_wander_returning = false
				_waypoints.clear()
				_reset_wander_timer()
				_change_state(State.POSTED)
			else:
				# Reached wander point, now head home
				_wander_returning = true
				_waypoints = [_get_bandit_home_position()]
				_current_wp = 0
		return
	else:
		_bandit.set_target(target)


func _process_posted(delta: float) -> void:
	# Stand at post. Count down wander timer.
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_do_wander()


func _process_lingering() -> void:
	if _anim_player and not _anim_player.is_playing():
		_linger_anim_count += 1
		if _linger_anim_count > _linger_max_anims:
			if _waypoints.size() > 1:
				_current_wp = (_current_wp + 1) % _waypoints.size()
				_change_state(State.WALKING)
			else:
				# Single-torch post — loop linger indefinitely
				_linger_anim_count = 0
				_linger_max_anims = randi_range(min_linger_anims, max_linger_anims)
				_play_linger_anim()
		else:
			_play_linger_anim()


# ── State transitions ────────────────────────────────────────────────────────

func _change_state(new_state: State) -> void:
	_state = new_state
	match new_state:
		State.WALKING:
			_set_bandit_move_speed(patrol_speed)
			_reset_walk_tracking()
			_reactivate_tree()
		State.LINGERING:
			_linger_anim_count = 0
			_linger_max_anims = randi_range(min_linger_anims, max_linger_anims)
			_stop_movement()
			if _anim_tree:
				_anim_tree.active = false
			_play_linger_anim()
		State.POSTED:
			# Stand still at home post
			_stop_movement()
			_set_bandit_move_speed(_normal_speed)
			if _bandit.has_method("refresh_idle_animation"):
				_bandit.call("refresh_idle_animation")
			else:
				_reactivate_tree()
		State.INACTIVE:
			pass


func _pause() -> void:
	if _state == State.LINGERING and _anim_tree:
		_reactivate_tree()
	_state = State.INACTIVE
	_set_bandit_move_speed(_normal_speed)


func _resume() -> void:
	if _has_torch_route:
		_find_nearest_waypoint()
		_change_state(State.WALKING)
	else:
		_change_state(State.POSTED)


func pause_patrol() -> void:
	_pause()


func resume_patrol() -> void:
	_resume()


func _reset_wander_timer() -> void:
	_wander_timer = randf_range(wander_interval_min, wander_interval_max)


func _do_wander() -> void:
	## Pick a random navmesh-snapped point near home and walk there.
	if not _is_navigation_map_ready():
		# NavigationServer may not have completed its first sync yet.
		_wander_timer = 0.25
		return
	var angle := randf() * TAU
	var dist := randf_range(wander_radius * 0.4, wander_radius)
	var candidate: Vector3 = _get_bandit_home_position() + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	candidate = _snap_to_navigation(candidate)
	_waypoints = [candidate]
	_current_wp = 0
	_wander_returning = false
	_change_state(State.WALKING)


# ── Waypoints ────────────────────────────────────────────────────────────────

func _build_waypoints() -> void:
	var torches: Array[Node] = BanditShared.get_all_torches(get_tree())
	var home: Vector3 = _get_bandit_home_position()
	var valid_points: Array[Vector3] = []
	for t in torches:
		if t is Node3D and t.global_position.distance_to(home) <= patrol_radius:
			var source: Vector3 = t.global_position
			var wp: Vector3 = _snap_to_navigation(source)
			if _has_navigation_map() and _horizontal_distance(source, wp) > waypoint_snap_tolerance:
				continue
			var is_duplicate := false
			for existing in valid_points:
				if _horizontal_distance(existing, wp) <= waypoint_merge_radius:
					is_duplicate = true
					break
			if not is_duplicate:
				valid_points.append(wp)
	valid_points.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var angle_a := wrapf(atan2(a.z - home.z, a.x - home.x), 0.0, TAU)
		var angle_b := wrapf(atan2(b.z - home.z, b.x - home.x), 0.0, TAU)
		return angle_a < angle_b
	)
	_waypoints = valid_points
	_has_torch_route = not _waypoints.is_empty()
	# No nearby torches: stand at post and wander occasionally.


func _try_finish_waypoint_build() -> void:
	if not _can_build_nav_snapped_points():
		return
	_build_waypoints()
	_pending_waypoint_build = false
	if _has_torch_route and (_state == State.POSTED or _state == State.INACTIVE):
		_find_nearest_waypoint()
		_change_state(State.WALKING)


func _find_nearest_waypoint() -> void:
	if _waypoints.is_empty():
		return
	var best_idx := 0
	var best_dist := INF
	for i in _waypoints.size():
		var d := _bandit.global_position.distance_to(_waypoints[i])
		if d < best_dist:
			best_dist = d
			best_idx = i
	_current_wp = best_idx


func is_patrolling() -> bool:
	return _state != State.INACTIVE


# ── Animation helpers ────────────────────────────────────────────────────────

func _play_linger_anim() -> void:
	if not _anim_player:
		return
	var pick: String = BanditShared.LOOK_AROUND_ANIMS[randi() % BanditShared.LOOK_AROUND_ANIMS.size()]
	var anim_name := StringName(str(BanditShared.LIB_NAME) + "/" + pick)
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, 0.3)


func _reactivate_tree() -> void:
	BanditShared.reactivate_tree(_anim_tree)


func _reset_walk_tracking() -> void:
	_last_walk_dist = INF
	_walk_stuck_time = 0.0


func _track_walk_progress(dist: float, delta: float) -> void:
	if _last_walk_dist == INF or dist < _last_walk_dist - walk_progress_epsilon:
		_walk_stuck_time = 0.0
	else:
		_walk_stuck_time += delta
	_last_walk_dist = dist


func _skip_blocked_waypoint() -> void:
	if _waypoints.size() > 1:
		_current_wp = (_current_wp + 1) % _waypoints.size()
		_reset_walk_tracking()
		return
	_has_torch_route = false
	_waypoints.clear()
	_reset_wander_timer()
	_change_state(State.POSTED)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _stop_movement() -> void:
	_reset_walk_tracking()
	_bandit.velocity = Vector3.ZERO


func _get_bandit_home_position() -> Vector3:
	var home_value: Variant = _bandit.get("home_position")
	if home_value is Vector3:
		return home_value
	return _bandit.global_position


func _get_navigation_map_rid() -> RID:
	if _nav_agent:
		return _nav_agent.get_navigation_map()
	return RID()


func _has_navigation_map() -> bool:
	return _get_navigation_map_rid().is_valid()


func _is_navigation_map_ready() -> bool:
	if not _nav_agent:
		return true
	var map_rid := _get_navigation_map_rid()
	if not map_rid.is_valid():
		return false
	return NavigationServer3D.map_get_iteration_id(map_rid) > 0


func _can_build_nav_snapped_points() -> bool:
	return not _has_navigation_map() or _is_navigation_map_ready()


func _snap_to_navigation(point: Vector3) -> Vector3:
	var map_rid := _get_navigation_map_rid()
	if not map_rid.is_valid():
		return point
	if NavigationServer3D.map_get_iteration_id(map_rid) <= 0:
		return point
	return NavigationServer3D.map_get_closest_point(map_rid, point)


func _get_bandit_move_speed() -> float:
	if _bandit.has_method("get_desired_move_speed"):
		var desired_speed_value: Variant = _bandit.call("get_desired_move_speed")
		if desired_speed_value is float:
			return desired_speed_value
		if desired_speed_value is int:
			return float(desired_speed_value)
	var speed_value: Variant = _bandit.get("move_speed")
	if speed_value is float:
		return speed_value
	if speed_value is int:
		return float(speed_value)
	return DEFAULT_BANDIT_MOVE_SPEED


func _set_bandit_move_speed(value: float) -> void:
	if _bandit.has_method("set_desired_move_speed"):
		_bandit.call("set_desired_move_speed", value)
	elif _bandit.get("move_speed") != null:
		_bandit.set("move_speed", value)
	if _nav_agent:
		_nav_agent.target_position = _bandit.global_position
