extends Node
## Torch-search behaviour for bandits.  When the player disappears into
## darkness and a wall torch is nearby, the bandit grabs it, searches the
## last-known position, wanders with the torch, then returns it and goes home.
##
## Attach as a child of the bandit CharacterBody3D alongside BanditPerception.

# ── Tuning ───────────────────────────────────────────────────────────────────
@export var torch_search_radius: float = 10.0
@export var grab_reach: float = 0.8
@export var search_walk_speed: float = 1.5
@export var search_wander_radius: float = 6.0
@export var search_duration: float = 20.0
@export var wander_interval: float = 4.0

const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")

# ── Animation names inside the Searching library ────────────────────────────
const ANIM_GRAB := "unarmed_grab_torch_from_wall"
const ANIM_TORCH_IDLE_CARRY := "standing_torch_idle_02"
const ANIM_TORCH_SEARCH: Array[String] = [
	"standing_torch_idle_02",
	"standing_torch_idle_03",
	"standing_torch_idle_04",
]
const ANIM_TORCH_INSPECT: Array[String] = [
	"standing_torch_inspect_downward",
	"standing_torch_inspect_forward",
]
const ANIM_LOOK_AROUND: Array[String] = [
	"look_around_02",
	"look_around_03",
	"look_around_04",
	"looking_around",
]

# frame 33 of 77 at 30 fps
const GRAB_TORCH_APPEAR_TIME := 33.0 / 30.0

enum State {
	INACTIVE,
	WALKING_TO_TORCH,
	GRABBING_TORCH,
	WALKING_TO_LKP,
	SEARCHING,
	RETURNING_TORCH,
	PLACING_TORCH,
	RETURNING_HOME,
}

var _state: State = State.INACTIVE
var _bandit: CharacterBody3D
var _perception: Node
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _skeleton: Skeleton3D
var _torch_source: Node3D
var _torch_instance: Node3D
var _left_hand_attach: BoneAttachment3D
var _search_center: Vector3
var _home_position: Vector3
var _search_timer: float = 0.0
var _wander_timer: float = 0.0
var _normal_speed: float
var _torch_appeared: bool = false
var _waiting_anim: bool = false
var _at_wander_point: bool = false
var _patrol: Node

# ── Stealth-aware routing ────────────────────────────────────────────────────
var _stealth_grid: StealthNavGrid
var _stealth_waypoints: PackedVector3Array = PackedVector3Array()
var _stealth_wp_index: int = 0
const _STEALTH_WP_ARRIVE := 2.5


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	if not _bandit:
		return
	_perception = _bandit.get_node_or_null("BanditPerception")
	var visual_root: Node3D = _bandit.get_node_or_null("ybot_root")
	if visual_root:
		_anim_player = visual_root.get_node_or_null("AnimationPlayer") as AnimationPlayer
		_anim_tree = visual_root.get_node_or_null("AnimationTree") as AnimationTree
		_skeleton = visual_root.get_node_or_null("Armature/Skeleton3D") as Skeleton3D

	_home_position = _bandit.global_position
	_normal_speed = _bandit.move_speed

	# Load searching animation library
	if _anim_player:
		var lib := load(BanditShared.LIB_PATH) as AnimationLibrary
		if lib and not _anim_player.has_animation_library(BanditShared.LIB_NAME):
			_anim_player.add_animation_library(BanditShared.LIB_NAME, lib)

	_patrol = _bandit.get_node_or_null("BanditPatrol")

	if _perception:
		_perception.player_lost_in_darkness.connect(_on_player_lost)


func _physics_process(delta: float) -> void:
	if _state == State.INACTIVE:
		return
	if _perception and _perception.alert_level >= 2:
		_abort()
		return
	match _state:
		State.WALKING_TO_TORCH:
			_process_walking_to_torch()
		State.GRABBING_TORCH:
			_process_grabbing_torch()
		State.WALKING_TO_LKP:
			_process_walking_to_lkp()
		State.SEARCHING:
			_process_searching(delta)
		State.RETURNING_TORCH:
			_process_returning_torch()
		State.PLACING_TORCH:
			_process_placing_torch()
		State.RETURNING_HOME:
			_process_returning_home()


# ── Trigger ──────────────────────────────────────────────────────────────────

func _on_player_lost(last_known_pos: Vector3) -> void:
	if _state != State.INACTIVE:
		return
	_search_center = last_known_pos
	if _patrol and _patrol.has_torch():
		_change_state(State.WALKING_TO_LKP)
		return
	var torch := _find_nearest_torch()
	if torch:
		_torch_source = torch
		_change_state(State.WALKING_TO_TORCH)
	else:
		_change_state(State.SEARCHING)


# ── State processors ────────────────────────────────────────────────────────

func _process_walking_to_torch() -> void:
	if not is_instance_valid(_torch_source):
		_abort()
		return
	var dist := _bandit.global_position.distance_to(_torch_source.global_position)
	if dist < grab_reach:
		_change_state(State.GRABBING_TORCH)
	else:
		_bandit.set_target(_torch_source.global_position)


func _process_grabbing_torch() -> void:
	if _waiting_anim:
		var cur_anim := StringName(str(BanditShared.LIB_NAME) + "/" + ANIM_GRAB)
		if not _torch_appeared and _anim_player.current_animation_position >= GRAB_TORCH_APPEAR_TIME:
			_attach_torch_to_hand()
			_torch_appeared = true
		if not _anim_player.is_playing() or _anim_player.current_animation != cur_anim:
			_waiting_anim = false
			_hide_world_torch()
			_change_state(State.WALKING_TO_LKP)


func _process_walking_to_lkp() -> void:
	var dist := _bandit.global_position.distance_to(_search_center)
	if dist < 2.0:
		_stealth_waypoints = PackedVector3Array()
		_stealth_wp_index = 0
		_change_state(State.SEARCHING)
		return

	# Build stealth path on first call or if waypoints exhausted
	if _stealth_waypoints.is_empty():
		_stealth_grid = StealthNavGrid.new()
		var mid := (_bandit.global_position + _search_center) * 0.5
		_stealth_grid.build(mid, _bandit.get_world_3d(), _bandit.get_tree())
		if _stealth_grid.is_valid():
			_stealth_waypoints = _stealth_grid.get_stealth_path(
				_bandit.global_position, _search_center)
			_stealth_wp_index = 0

	if _stealth_waypoints.is_empty() or _stealth_wp_index >= _stealth_waypoints.size():
		_bandit.set_target(_search_center)
		return

	var wp := _stealth_waypoints[_stealth_wp_index]
	if _bandit.global_position.distance_to(wp) < _STEALTH_WP_ARRIVE:
		_stealth_wp_index += 1
		if _stealth_wp_index >= _stealth_waypoints.size():
			_bandit.set_target(_search_center)
			return
		wp = _stealth_waypoints[_stealth_wp_index]
	_bandit.set_target(wp)


func _process_searching(delta: float) -> void:
	_search_timer += delta

	if _search_timer >= search_duration:
		if _torch_instance:
			_change_state(State.RETURNING_TORCH)
		else:
			_change_state(State.RETURNING_HOME)
		return

	# Sub-state: playing a look-around animation at a wander point
	if _at_wander_point:
		if not _anim_player.is_playing():
			_at_wander_point = false
			_reactivate_tree()
			_pick_wander_target()
		return

	# Sub-state: walking to wander point, wait until nav finished
	if _bandit.nav_agent.is_navigation_finished():
		_wander_timer += delta
		if _wander_timer >= wander_interval:
			_wander_timer = 0.0
			_at_wander_point = true
			if _anim_tree:
				_anim_tree.active = false
			_play_random_search_anim()


func _process_returning_torch() -> void:
	if not is_instance_valid(_torch_source):
		_detach_torch()
		_abort()
		return
	var dist := _bandit.global_position.distance_to(_torch_source.global_position)
	if dist < grab_reach:
		_change_state(State.PLACING_TORCH)
	else:
		_bandit.set_target(_torch_source.global_position)


func _process_placing_torch() -> void:
	if _waiting_anim:
		var cur_anim := StringName(str(BanditShared.LIB_NAME) + "/" + ANIM_GRAB)
		if not _torch_appeared and _anim_player.current_animation_position >= GRAB_TORCH_APPEAR_TIME:
			_detach_torch()
			_show_world_torch()
			_torch_appeared = true
		if not _anim_player.is_playing() or _anim_player.current_animation != cur_anim:
			_waiting_anim = false
			_change_state(State.RETURNING_HOME)


func _process_returning_home() -> void:
	var dist := _bandit.global_position.distance_to(_home_position)
	if dist < 1.5:
		_abort()
	else:
		_bandit.set_target(_home_position)


# ── State transitions ───────────────────────────────────────────────────────

func _change_state(new_state: State) -> void:
	_state = new_state
	match new_state:
		State.WALKING_TO_TORCH:
			_bandit.move_speed = _normal_speed
			_reactivate_tree()
		State.GRABBING_TORCH:
			_stop_movement()
			_face_torch()
			_play_grab_anim()
		State.WALKING_TO_LKP:
			_bandit.move_speed = search_walk_speed
			_reactivate_tree()
		State.SEARCHING:
			_search_timer = 0.0
			_wander_timer = 0.0
			_at_wander_point = true
			_bandit.move_speed = search_walk_speed
			if _anim_tree:
				_anim_tree.active = false
			_play_random_search_anim()
		State.RETURNING_TORCH:
			_bandit.move_speed = _normal_speed
			_reactivate_tree()
		State.PLACING_TORCH:
			_stop_movement()
			_face_torch()
			_torch_appeared = false
			_play_grab_anim()
		State.RETURNING_HOME:
			_bandit.move_speed = _normal_speed
			_reactivate_tree()
		State.INACTIVE:
			_bandit.move_speed = _normal_speed
			_reactivate_tree()


func _abort() -> void:
	if _torch_instance:
		_detach_torch()
		_show_world_torch()
	_at_wander_point = false
	_state = State.INACTIVE
	_bandit.move_speed = _normal_speed
	_stealth_waypoints = PackedVector3Array()
	_stealth_wp_index = 0
	_stealth_grid = null
	_reactivate_tree()


func _stop_movement() -> void:
	_bandit.velocity = Vector3.ZERO
	_bandit.nav_agent.target_position = _bandit.global_position


# ── Torch finding ────────────────────────────────────────────────────────────

func _find_nearest_torch() -> Node3D:
	var best: Node3D = null
	var best_dist := torch_search_radius
	# Check both groups — "torch" is canonical, "flame" is the legacy fallback
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("torch"))
	if candidates.is_empty():
		candidates.append_array(get_tree().get_nodes_in_group("flame"))
	for node in candidates:
		if node is Node3D:
			var d := _bandit.global_position.distance_to(node.global_position)
			if d < best_dist:
				best_dist = d
				best = node as Node3D
	return best


# ── Torch attach / detach ───────────────────────────────────────────────────

func _attach_torch_to_hand() -> void:
	if not _skeleton or not is_instance_valid(_torch_source):
		return
	_left_hand_attach = BoneAttachment3D.new()
	_left_hand_attach.bone_name = "hand.L"
	_skeleton.add_child(_left_hand_attach)

	_torch_instance = Node3D.new()
	_torch_instance.name = "HeldTorch"
	for child in _torch_source.get_children():
		if child.name == "Pole":
			continue
		var clone := child.duplicate()
		_torch_instance.add_child(clone)
	_torch_instance.position = Vector3(0, 0.1, 0)
	_left_hand_attach.add_child(_torch_instance)


func _detach_torch() -> void:
	if _torch_instance and is_instance_valid(_torch_instance):
		_torch_instance.queue_free()
		_torch_instance = null
	if _left_hand_attach and is_instance_valid(_left_hand_attach):
		_left_hand_attach.queue_free()
		_left_hand_attach = null


func _hide_world_torch() -> void:
	if is_instance_valid(_torch_source):
		_torch_source.visible = false
		var light := _torch_source.get_node_or_null("FireLight") as OmniLight3D
		if light:
			light.visible = false
		var particles := _torch_source.get_node_or_null("FireParticles") as GPUParticles3D
		if particles:
			particles.emitting = false


func _show_world_torch() -> void:
	if is_instance_valid(_torch_source):
		_torch_source.visible = true
		var light := _torch_source.get_node_or_null("FireLight") as OmniLight3D
		if light:
			light.visible = true
		var particles := _torch_source.get_node_or_null("FireParticles") as GPUParticles3D
		if particles:
			particles.emitting = true


# ── Animation helpers ────────────────────────────────────────────────────────

func _play_grab_anim() -> void:
	_torch_appeared = false
	_waiting_anim = true
	if _anim_tree:
		_anim_tree.active = false
	if _anim_player:
		var anim_name := StringName(str(BanditShared.LIB_NAME) + "/" + ANIM_GRAB)
		if _anim_player.has_animation(anim_name):
			_anim_player.play(anim_name)


func _play_random_search_anim() -> void:
	if not _anim_player:
		return
	var holding_torch: bool = _torch_instance != null or (_patrol != null and _patrol.has_torch())
	var choices: Array[String] = []
	if holding_torch:
		choices.append_array(ANIM_TORCH_SEARCH)
		choices.append_array(ANIM_TORCH_INSPECT)
	else:
		choices.append_array(ANIM_LOOK_AROUND)
	var pick: String = choices[randi() % choices.size()]
	var anim_name := StringName(str(BanditShared.LIB_NAME) + "/" + pick)
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name, 0.3)


func _pick_wander_target() -> void:
	# Sample several random candidates and pick the darkest one
	var best_pos := Vector3.ZERO
	var best_light := INF
	var space := _bandit.get_world_3d().direct_space_state
	var grid := StealthNavGrid.new()
	var lights := grid._find_omni_lights(_bandit.get_tree().root)

	for i in 5:
		var angle := randf() * TAU
		var radius := randf_range(1.5, search_wander_radius)
		var candidate := _search_center + Vector3(cos(angle), 0, sin(angle)) * radius
		var total_light := 0.0
		for light in lights:
			if is_instance_valid(light):
				total_light += grid._sample_omni(light, candidate, space)
		if total_light < best_light:
			best_light = total_light
			best_pos = candidate

	if best_pos != Vector3.ZERO:
		_bandit.set_target(best_pos)
	else:
		var angle := randf() * TAU
		var radius := randf_range(1.5, search_wander_radius)
		_bandit.set_target(_search_center + Vector3(cos(angle), 0, sin(angle)) * radius)


func _reactivate_tree() -> void:
	if _anim_tree and not _anim_tree.active:
		_anim_tree.active = true


func _face_torch() -> void:
	if not is_instance_valid(_torch_source):
		return
	var dir := _torch_source.global_position - _bandit.global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
		var visual_root := _bandit.get_node_or_null("ybot_root") as Node3D
		if visual_root:
			visual_root.rotation.y = atan2(dir.x, dir.z)


func is_searching() -> bool:
	return _state != State.INACTIVE
