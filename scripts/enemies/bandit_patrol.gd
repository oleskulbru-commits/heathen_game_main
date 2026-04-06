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

const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")

const LINGER_LOOK_ANIMS: Array[String] = [
	"look_around_02",
	"look_around_03",
	"look_around_04",
	"looking_around",
]

## POSTED = standing idle at home post (no-torch default)
enum State { INACTIVE, WALKING, LINGERING, POSTED }

var _state: State = State.INACTIVE
var _has_torch_route: bool = false   # true when real torch waypoints were found
var _wander_timer: float = 0.0       # counts down; when 0 bandit does a short wander
var _wander_returning: bool = false  # true when walking back home after a wander
var _bandit: CharacterBody3D
var _perception: Node
var _torch_search: Node
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _skeleton: Skeleton3D
var _waypoints: Array[Vector3] = []
var _current_wp: int = 0
var _linger_anim_count: int = 0
var _linger_max_anims: int = 1
var _normal_speed: float


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	if not _bandit:
		return

	_perception = _bandit.get_node_or_null("BanditPerception")
	_torch_search = _bandit.get_node_or_null("BanditTorchSearch")

	var visual_root := _bandit.get_node_or_null("ybot_root") as Node3D
	if visual_root:
		_anim_player = visual_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
		_anim_tree = visual_root.get_node_or_null("AnimationTree") as AnimationTree
		_skeleton = visual_root.get_node_or_null("Armature/Skeleton3D") as Skeleton3D

	_normal_speed = _bandit.move_speed

	# Load searching library for linger animations
	if _anim_player:
		var lib := load(BanditShared.LIB_PATH) as AnimationLibrary
		if lib and not _anim_player.has_animation_library(BanditShared.LIB_NAME):
			_anim_player.add_animation_library(BanditShared.LIB_NAME, lib)

	# Wait one frame so all torches are in the tree
	await get_tree().process_frame
	_build_waypoints()

	if _has_torch_route:
		# Real patrol route — start walking immediately
		_find_nearest_waypoint()
		_change_state(State.WALKING)
	else:
		# No torches: stand at post, wander occasionally
		_reset_wander_timer()
		_change_state(State.POSTED)


func _physics_process(_delta: float) -> void:
	# Auto pause / resume based on alert and search state
	var should_pause := false
	if _perception and _perception.alert_level > 0:
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
			_process_walking()
		State.LINGERING:
			_process_lingering()
		State.POSTED:
			_process_posted(_delta)


func _process_walking() -> void:
	if _waypoints.is_empty():
		return
	var target := _waypoints[_current_wp]
	# Use XZ-only distance so elevated torch props don't prevent arrival
	var dist := Vector2(
			_bandit.global_position.x - target.x,
			_bandit.global_position.z - target.z).length()
	if dist < arrive_radius:
		if _has_torch_route:
			_change_state(State.LINGERING)
		else:
			# Wander trip complete — return home or stand at post
			if _wander_returning:
				_wander_returning = false
				_waypoints.clear()
				_reset_wander_timer()
				_change_state(State.POSTED)
			else:
				# Reached wander point, now head home
				_wander_returning = true
				_waypoints = [_bandit.home_position]
				_current_wp = 0
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
			_bandit.move_speed = patrol_speed
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
			_bandit.move_speed = _normal_speed
			_reactivate_tree()
		State.INACTIVE:
			pass


func _pause() -> void:
	if _state == State.LINGERING and _anim_tree:
		_reactivate_tree()
	_state = State.INACTIVE
	_bandit.move_speed = _normal_speed


func _resume() -> void:
	if _has_torch_route:
		_find_nearest_waypoint()
		_change_state(State.WALKING)
	else:
		_change_state(State.POSTED)


func _reset_wander_timer() -> void:
	_wander_timer = randf_range(wander_interval_min, wander_interval_max)


func _do_wander() -> void:
	## Pick a random navmesh-snapped point near home and walk there.
	var nav_agent := _bandit.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	var map_rid: RID
	if nav_agent:
		map_rid = nav_agent.get_navigation_map()
	var angle := randf() * TAU
	var dist := randf_range(wander_radius * 0.4, wander_radius)
	var candidate: Vector3 = _bandit.home_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	if map_rid.is_valid():
		candidate = NavigationServer3D.map_get_closest_point(map_rid, candidate)
	_waypoints = [candidate]
	_current_wp = 0
	_wander_returning = false
	_change_state(State.WALKING)


# ── Waypoints ────────────────────────────────────────────────────────────────

func _build_waypoints() -> void:
	var torches: Array[Node] = []
	torches.append_array(get_tree().get_nodes_in_group("torch"))
	if torches.is_empty():
		torches.append_array(get_tree().get_nodes_in_group("flame"))
	var home: Vector3 = _bandit.home_position
	var nav_agent := _bandit.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	var map_rid: RID
	if nav_agent:
		map_rid = nav_agent.get_navigation_map()
	for t in torches:
		if t is Node3D and t.global_position.distance_to(home) <= patrol_radius:
			var wp: Vector3 = t.global_position
			if map_rid.is_valid():
				wp = NavigationServer3D.map_get_closest_point(map_rid, wp)
			_waypoints.append(wp)
	_has_torch_route = not _waypoints.is_empty()
	# No nearby torches: stand at post and wander occasionally.


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
	var pick: String = LINGER_LOOK_ANIMS[randi() % LINGER_LOOK_ANIMS.size()]
	var anim_name := StringName(str(BanditShared.LIB_NAME) + "/" + pick)
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, 0.3)


func _reactivate_tree() -> void:
	if _anim_tree and not _anim_tree.active:
		_anim_tree.active = true


func _stop_movement() -> void:
	_bandit.velocity = Vector3.ZERO
	_bandit.nav_agent.target_position = _bandit.global_position
