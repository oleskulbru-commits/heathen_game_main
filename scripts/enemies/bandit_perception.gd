extends Node
## Handles sight, light-awareness, and sound detection for a bandit.
## Attach as a child of the bandit CharacterBody3D.
##
## Continuous suspicion model: stimuli (sight & sound) feed a 0.0–1.0
## suspicion float that rises while the player is detected and drains
## when stimuli stop.  Alert level is derived from thresholds:
##
##   suspicion < curious   → 0  Unaware
##   suspicion < alert     → 1  Curious   (heard/glimpsed — investigate LKP)
##   suspicion < combat    → 2  Alert     (actively hunting LKP trail)
##   suspicion >= combat   → 3  Combat    (pursue aggressively, call friends)

signal alert_level_changed(level: int)
signal suspicion_changed(value: float)
signal entered_combat()
signal player_lost_in_darkness(last_known_pos: Vector3)
signal heard_noise(source_pos: Vector3)

# ── Sight ────────────────────────────────────────────────────────────────────
@export var sight_range: float = 25.0
@export var sight_fov_deg: float = 110.0
@export var inner_fov_deg: float = 40.0             ## Phase 1: central vision cone
@export var peripheral_rate_mult: float = 0.3        ## Phase 1: outer cone suspicion multiplier
@export var sneak_detect_range: float = 1.0
@export var crouch_range_mult: float = 0.5
@export var moving_range_mult: float = 1.3
@export var sprint_range_mult: float = 1.5
@export var sight_check_interval: float = 0.2
@export var height_advantage_mult: float = 0.4      ## Phase 2: penalty when player is above

# ── Hearing ──────────────────────────────────────────────────────────────────
@export var hearing_range_sprint: float = 20.0
@export var hearing_range_walk: float = 8.0
@export var hearing_range_crouch_walk: float = 3.0
@export var sound_occlusion_mult: float = 0.3        ## Phase 3: hearing through walls

# ── Suspicion ────────────────────────────────────────────────────────────────
@export var suspicion_rate_sight: float = 0.5      ## per-second at full intensity
@export var suspicion_rate_sound_sprint: float = 0.35
@export var suspicion_rate_sound_walk: float = 0.15
@export var suspicion_rate_sound_crouch: float = 0.05
@export var suspicion_drain_rate: float = 0.12     ## per-second when no stimuli

# ── Thresholds (0.0 – 1.0) ──────────────────────────────────────────────────
@export var threshold_curious: float = 0.3
@export var threshold_alert: float = 0.6
@export var threshold_combat: float = 0.9

# ── Alert behaviour ─────────────────────────────────────────────────────────
@export var lkp_arrive_radius: float = 2.0
@export var alert_decay_time: float = 8.0
@export var pursuit_projection_dist: float = 8.0    ## Phase 5: how far ahead to project LKP

# ── Post-search heightened awareness ─────────────────────────────────────────
@export var heightened_duration: float = 30.0        ## Phase 6
@export var heightened_sight_mult: float = 1.3       ## Phase 6
@export var heightened_fov_bonus: float = 20.0       ## Phase 6

# ── Exposure accumulator (Phase 1d) ─────────────────────────────────────────
@export var exposure_buildup_rate: float = 2.5   ## 0→1 in 0.4 s of unbroken LOS
@export var exposure_drain_rate: float = 0.8     ## 1→0 in 1.25 s out of LOS

# ── De-escalation (Phase 1c) ─────────────────────────────────────────────────
@export var deescalate_time: float = 4.0         ## seconds below threshold before stepping down

var alert_level: int = 0
var suspicion: float = 0.0
var last_known_positions: Array[Vector3] = []

var _sight_timer: float = 0.0
var _decay_timer: float = 0.0
var _suspicion_input: float = 0.0   # total rate this frame
var _sight_rate: float = 0.0        # persists between sight checks
var _player_ref: CharacterBody3D
var _light_probe: Node
var _bandit: CharacterBody3D
var _torch_search: Node
var _body_detector: Node

# ── Velocity pursuit projection (Phase 5) ────────────────────────────────────
var _player_last_velocity: Vector3 = Vector3.ZERO

# ── Exposure & de-escalation (Phase 1c / 1d) ─────────────────────────────────
var _exposure: float = 0.0                   # 0–1: how long bandit has clearly seen the player
var _player_visible_last_frame: bool = false # set true only on an unobstructed LOS check
var _deescalate_timer: float = 0.0           # counts up when new_level < alert_level

# ── Post-search heightened awareness (Phase 6) ──────────────────────────────
var _heightened_timer: float = 0.0

# ── Stealth-aware A* routing (alert_level 1–2) ──────────────────────────────
var _stealth_grid: StealthNavGrid
var _stealth_waypoints: PackedVector3Array = PackedVector3Array()
var _stealth_wp_index: int = 0
var _stealth_target: Vector3 = Vector3.INF
const _STEALTH_WP_ARRIVE := 2.5
const _STEALTH_REBUILD_TIME := 10.0
var _stealth_age: float = 0.0


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	await get_tree().process_frame
	_player_ref = _find_player()
	if _player_ref:
		_light_probe = _player_ref.get_node_or_null("LightProbe")
	_torch_search = _bandit.get_node_or_null("BanditTorchSearch")
	_body_detector = _bandit.get_node_or_null("BanditBodyDetector")


func _physics_process(delta: float) -> void:
	if not _player_ref or not _bandit:
		return

	# Phase 6: Tick heightened awareness timer
	if _heightened_timer > 0.0:
		_heightened_timer = maxf(_heightened_timer - delta, 0.0)

	_suspicion_input = _sight_rate   # carry sight rate between checks
	_sight_timer += delta

	if _sight_timer >= sight_check_interval:
		_sight_timer = 0.0
		_check_sight()
		_suspicion_input = _sight_rate   # update with fresh value

	# ── Phase 1d: Exposure accumulator ──────────────────────────────────
	if _player_visible_last_frame:
		_exposure = minf(_exposure + exposure_buildup_rate * delta, 1.0)
	else:
		_exposure = maxf(_exposure - exposure_drain_rate * delta, 0.0)

	_check_sound()

	# ── Suspicion rise / drain ──────────────────────────────────
	if _suspicion_input > 0.0:
		suspicion = minf(suspicion + _suspicion_input * delta, 1.0)
		_decay_timer = 0.0
	else:
		# Phase 1d: high exposure slows drain so recently-seen players can’t instantly hide
		var eff_drain := suspicion_drain_rate * (1.0 - _exposure * 0.7)
		suspicion = maxf(suspicion - eff_drain * delta, 0.0)

	suspicion_changed.emit(suspicion)

	# ── Derive alert level from thresholds (only goes UP via suspicion) ─
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
		# Phase 1c: de-escalate gradually so brief breaks don’t instantly calm the bandit
		_deescalate_timer += delta
		if _deescalate_timer >= deescalate_time:
			_deescalate_timer = 0.0
			alert_level = maxi(alert_level - 1, new_level)
			alert_level_changed.emit(alert_level)
	else:
		_deescalate_timer = 0.0

	# ── Alert decay — lose interest when suspicion drains to zero ───────
	if suspicion <= 0.0 and alert_level > 0:
		_decay_timer += delta
		if _decay_timer >= alert_decay_time:
			var old_level := alert_level
			_decay_timer = 0.0
			alert_level = maxi(alert_level - 1, 0)
			alert_level_changed.emit(alert_level)

			# Phase 5: When dropping from combat, project LKP along player’s last velocity
			if old_level == 3 and alert_level == 2:
				if not last_known_positions.is_empty() and _player_last_velocity.length() > 0.5:
					var projected := last_known_positions[-1] + _player_last_velocity.normalized() * pursuit_projection_dist
					last_known_positions.insert(0, projected)

			if alert_level == 0:
				if not last_known_positions.is_empty():
					player_lost_in_darkness.emit(last_known_positions[-1])
				last_known_positions.clear()
				# Phase 6: Start heightened awareness
				_heightened_timer = heightened_duration

	# ── Navigate toward last-known positions ────────────────────────────
	if _torch_search and _torch_search.is_searching():
		pass
	elif alert_level >= 1 and not last_known_positions.is_empty():
		var target := last_known_positions[0]
		var dist := _bandit.global_position.distance_to(target)
		if dist < lkp_arrive_radius:
			last_known_positions.pop_front()
			_stealth_waypoints = PackedVector3Array()
			_stealth_wp_index = 0
			_stealth_target = Vector3.INF
			if last_known_positions.is_empty() and _suspicion_input <= 0.0:
				player_lost_in_darkness.emit(target)
		elif alert_level == 1 and _bandit.has_method("set_target"):
			_navigate_stealth(target, delta)
		elif _bandit.has_method("set_target"):
			_bandit.set_target(target)


func _check_sight() -> void:
	_sight_rate = 0.0   # clear — will be set if player is visible
	_player_visible_last_frame = false  # Phase 1d: pessimistic default; only true on clear LOS
	var player_pos := _player_ref.global_position + Vector3(0.0, 1.0, 0.0)
	var bandit_pos := _bandit.global_position + Vector3(0.0, 1.5, 0.0)
	var to_player := player_pos - bandit_pos
	var dist := to_player.length()

	# ── Compute effective sight range from light visibility ─────────────
	var visibility := 1.0
	if _light_probe and _light_probe.has_method("get_visibility"):
		visibility = _light_probe.get_visibility()

	var effective_range := sneak_detect_range + (sight_range - sneak_detect_range) * sqrt(visibility)

	# Phase 6: Heightened post-search awareness boosts range
	if _heightened_timer > 0.0:
		effective_range *= heightened_sight_mult

	# Crouching halves the effective range
	var is_crouching := false
	if _player_ref.has_method("is_in_stealth"):
		is_crouching = _player_ref.is_in_stealth()
	if is_crouching:
		effective_range *= crouch_range_mult

	# Movement amplifies visual exposure
	var player_moving := false
	var player_sprinting := false
	if "is_moving" in _player_ref:
		player_moving = _player_ref.is_moving
	if "is_sprinting" in _player_ref:
		player_sprinting = _player_ref.is_sprinting

	if player_sprinting:
		effective_range *= sprint_range_mult
	elif player_moving:
		effective_range *= moving_range_mult

	# Phase 2: Player above bandit → harder to detect (looking up penalty)
	var vert_angle := asin(clampf(to_player.normalized().y, -1.0, 1.0))
	if vert_angle > 0.3:  # ~17 degrees above
		effective_range *= height_advantage_mult

	if dist > effective_range:
		return

	# ── FOV check ───────────────────────────────────────────────────────
	var bandit_forward := _bandit.global_transform.basis * Vector3(0, 0, 1)
	if _bandit.has_node("ybot_root"):
		bandit_forward = _bandit.get_node("ybot_root").global_transform.basis * Vector3(0, 0, 1)
	bandit_forward.y = 0.0
	bandit_forward = bandit_forward.normalized()
	var dir_to_player := to_player.normalized()
	dir_to_player.y = 0.0
	dir_to_player = dir_to_player.normalized()

	# Phase 6: Heightened awareness widens FOV
	var current_fov := sight_fov_deg
	if _heightened_timer > 0.0:
		current_fov += heightened_fov_bonus

	var angle := acos(clampf(bandit_forward.dot(dir_to_player), -1.0, 1.0))
	if angle > deg_to_rad(current_fov * 0.5):
		return

	# ── Phase 1a: Multi-point LOS — head, chest, feet ──────────────────
	var space := _bandit.get_world_3d().direct_space_state
	var player_base := _player_ref.global_position
	var los_targets := PackedVector3Array([
		player_base + Vector3(0.0, 1.7, 0.0),  # head
		player_base + Vector3(0.0, 1.0, 0.0),  # chest
		player_base + Vector3(0.0, 0.2, 0.0),  # feet
	])
	var clear_count := 0
	for los_target in los_targets:
		var q := PhysicsRayQueryParameters3D.create(bandit_pos, los_target)
		q.collision_mask = 1
		q.exclude = [_bandit.get_rid(), _player_ref.get_rid()]
		if not space.intersect_ray(q):
			clear_count += 1
	var vis_fraction := float(clear_count) / float(los_targets.size())
	if vis_fraction == 0.0:
		return

	# ── Phase 1: FOV zone multiplier (central vs peripheral) ───────────
	var fov_multiplier := 1.0
	if angle > deg_to_rad(inner_fov_deg * 0.5):
		fov_multiplier = peripheral_rate_mult

	# ── Compute suspicion intensity from proximity & visibility ─────────
	var proximity := 1.0 - clampf(dist / effective_range, 0.0, 1.0)
	var intensity := proximity * maxf(visibility, 0.15)
	# Phase 1a: partial LOS contributes proportionally
	_sight_rate = suspicion_rate_sight * intensity * fov_multiplier * vis_fraction
	_player_visible_last_frame = true
	_record_lkp(player_pos)


func _check_sound() -> void:
	var dist := _bandit.global_position.distance_to(_player_ref.global_position)

	# Phase 3: Sound occlusion — two raycasts (feet + chest) to check for walls
	var occlusion_factor := 1.0
	var space := _bandit.get_world_3d().direct_space_state
	var bandit_ear := _bandit.global_position + Vector3(0.0, 1.0, 0.0)
	var player_feet := _player_ref.global_position + Vector3(0.0, 0.2, 0.0)
	var player_chest := _player_ref.global_position + Vector3(0.0, 1.2, 0.0)

	var q_feet := PhysicsRayQueryParameters3D.create(bandit_ear, player_feet)
	q_feet.collision_mask = 1
	q_feet.exclude = [_bandit.get_rid(), _player_ref.get_rid()]
	var q_chest := PhysicsRayQueryParameters3D.create(bandit_ear, player_chest)
	q_chest.collision_mask = 1
	q_chest.exclude = [_bandit.get_rid(), _player_ref.get_rid()]

	var blocked_feet := space.intersect_ray(q_feet)
	var blocked_chest := space.intersect_ray(q_chest)
	if blocked_feet and blocked_chest:
		occlusion_factor = sound_occlusion_mult
	elif blocked_feet or blocked_chest:
		occlusion_factor = lerpf(sound_occlusion_mult, 1.0, 0.5)

	var player_sprinting := false
	var player_moving := false
	var player_crouching := false

	if "is_sprinting" in _player_ref:
		player_sprinting = _player_ref.is_sprinting
	if "is_moving" in _player_ref:
		player_moving = _player_ref.is_moving
	if _player_ref.has_method("is_in_stealth"):
		player_crouching = _player_ref.is_in_stealth()

	var eff_sprint := hearing_range_sprint * occlusion_factor
	var eff_walk := hearing_range_walk * occlusion_factor
	var eff_crouch := hearing_range_crouch_walk * occlusion_factor

	var heard := false
	var sound_pos := _player_ref.global_position

	if player_sprinting and dist <= eff_sprint:
		var proximity := 1.0 - clampf(dist / eff_sprint, 0.0, 1.0)
		_suspicion_input += suspicion_rate_sound_sprint * proximity
		_record_lkp(sound_pos)
		heard = true
	elif player_moving and player_crouching and dist <= eff_crouch:
		var proximity := 1.0 - clampf(dist / eff_crouch, 0.0, 1.0)
		_suspicion_input += suspicion_rate_sound_crouch * proximity
		_record_lkp(sound_pos)
		heard = true
	elif player_moving and not player_crouching and dist <= eff_walk:
		var proximity := 1.0 - clampf(dist / eff_walk, 0.0, 1.0)
		_suspicion_input += suspicion_rate_sound_walk * proximity
		_record_lkp(sound_pos)
		heard = true

	# Phase 1b / Phase 4: Emit approximate position — prevents pinpoint tracking via sound
	if heard and alert_level == 0:
		heard_noise.emit(_approximate_sound_pos(sound_pos))


func _approximate_sound_pos(exact_pos: Vector3) -> Vector3:
	## Phase 1b: Snaps to a 3 m grid then adds distance-proportional noise.
	## Bandits hear “roughly where” not “exactly where” the player made a sound.
	var snapped := Vector3(
		roundf(exact_pos.x / 3.0) * 3.0,
		exact_pos.y,
		roundf(exact_pos.z / 3.0) * 3.0,
	)
	var dist := _bandit.global_position.distance_to(exact_pos)
	var noise := clampf(dist / 20.0, 0.0, 1.0) * 1.5
	if noise > 0.01:
		snapped.x += randf_range(-noise, noise)
		snapped.z += randf_range(-noise, noise)
	return snapped


func _record_lkp(position: Vector3) -> void:
	# Phase 5: Capture player velocity for pursuit projection
	if _player_ref:
		_player_last_velocity = _player_ref.velocity
	if last_known_positions.is_empty() or last_known_positions[-1].distance_to(position) > 2.0:
		last_known_positions.append(position)


func _call_nearby_bandits() -> void:
	var call_range := 40.0
	var nearby: Array[Node] = []
	for node in get_tree().get_nodes_in_group("bandit"):
		if node == _bandit:
			continue
		if node.global_position.distance_to(_bandit.global_position) <= call_range:
			nearby.append(node)

	# Phase 7: Distribute unique search offsets so guards fan out
	var search_center := last_known_positions[-1] if not last_known_positions.is_empty() else _bandit.global_position
	var distributed := _distribute_search_positions(search_center, nearby.size())

	for i in nearby.size():
		var node := nearby[i]
		var perception := node.get_node_or_null("BanditPerception")
		if perception and perception.alert_level < 3:
			perception.suspicion = 1.0
			perception.alert_level = 3
			# Each guard gets a unique offset position first, then shared LKP trail
			var lkps: Array[Vector3] = []
			if i < distributed.size():
				lkps.append(distributed[i])
			if not last_known_positions.is_empty():
				lkps.append_array(last_known_positions)
			perception.last_known_positions = lkps
			perception.alert_level_changed.emit(3)
			perception.entered_combat.emit()


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


func reset_alert() -> void:
	alert_level = 0
	suspicion = 0.0
	last_known_positions.clear()
	_decay_timer = 0.0
	_heightened_timer = 0.0
	_player_last_velocity = Vector3.ZERO
	_exposure = 0.0
	_player_visible_last_frame = false
	_deescalate_timer = 0.0
	_stealth_waypoints = PackedVector3Array()
	_stealth_wp_index = 0
	_stealth_target = Vector3.INF
	_stealth_grid = null
	alert_level_changed.emit(0)
	suspicion_changed.emit(0.0)


func _navigate_stealth(target: Vector3, delta: float) -> void:
	_stealth_age += delta
	var needs_rebuild := _stealth_waypoints.is_empty() \
		or _stealth_target.distance_to(target) > 4.0 \
		or _stealth_age >= _STEALTH_REBUILD_TIME

	if needs_rebuild:
		_stealth_grid = StealthNavGrid.new()
		var mid := (_bandit.global_position + target) * 0.5
		_stealth_grid.build(mid, _bandit.get_world_3d(), _bandit.get_tree())
		if _stealth_grid.is_valid():
			_stealth_waypoints = _stealth_grid.get_stealth_path(
				_bandit.global_position, target)
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


func _find_player() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as CharacterBody3D
	var p := get_tree().root.find_child("Player", true, false)
	if p is CharacterBody3D:
		return p
	return null


# ── Terrain locomotion integration ───────────────────────────────────────────

func _get_terrain_noise_mult() -> float:
	if not _player_ref:
		return 1.0
	var loco := _player_ref.get_node_or_null("TerrainLocomotion")
	if loco and loco.has_method("get_noise_modifier"):
		return loco.get_noise_modifier()
	return 1.0


func _get_terrain_occlusion() -> float:
	if not _player_ref:
		return 0.0
	var loco := _player_ref.get_node_or_null("TerrainLocomotion")
	if loco and loco.has_method("get_occlusion"):
		return loco.get_occlusion()
	return 0.0
