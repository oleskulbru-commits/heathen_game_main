extends SpellBase
class_name SpellDash
## Hrafn — The Raven's Dash
## The witch shatters into 5 spectral ravens that fly the dash distance,
## curving around any enemies in the path.  Walls and static geometry block
## the dash entirely (raycast).  Enemies are avoided — each raven takes a
## unique curved bezier route around obstacles.
##
## Raven assignments:
##   0 = Left-High     1 = Left-Low
##   2 = Right-High    3 = Right-Low
##   4 = Random side, Mid altitude

enum DashPhase { NONE, TARGETING, DIVE_INTRO, SCATTER, FLYING, CONVERGE, LANDING, RECOVERY, SUSTAINED, SUSTAINED_CONVERGE }

const RAVEN_COUNT := 5
const RAVEN_SCENE_PATH := "res://scenes/player/raven.tscn"
const DIVE_ROLL_ANIM := &"player_combat/standing_dive_forward"
const LANDING_ANIM := &"npc_axe/standing_jump"
const LANDING_SEEK_TIME := 1.0  ## Start the landing anim from this timestamp

@export var dash_distance: float = 7.0
@export var combat_behind_offset: float = 1.3  ## How far behind the enemy to land
@export var dive_intro_duration: float = 0.3  ## Dive roll visible before morphing
@export var scatter_duration: float = 0.15  ## Ravens burst outward from player
@export var flight_duration: float = 0.35   ## Main flight along bezier curves
@export var converge_duration: float = 0.12 ## Ravens collapse into destination
@export var recovery_duration: float = 0.40 ## Player stumble after reforming
@export var obstacle_detect_radius: float = 1.8  ## How wide to scan for enemies
@export var avoidance_lateral: float = 2.0  ## How far ravens curve sideways around obstacles
@export var avoidance_vertical_hi: float = 1.6
@export var avoidance_vertical_lo: float = 0.3
@export var base_spread: float = 0.7  ## Minimum lateral spread even with no obstacles
@export_group("Targeted Blink")
@export var targeted_ray_distance: float = 30.0
@export_range(0.0, 89.0) var targeted_max_slope_deg: float = 55.0
@export var targeted_marker_radius: float = 0.65
@export_flags_3d_physics var targeted_collision_mask: int = 3
@export_group("Sustained Travel")
@export var sustained_speed: float = 10.5
@export var sustained_stamina_cost_per_second: float = 20.0
@export var sustained_obstacle_buffer: float = 0.45
@export var sustained_heading_response: float = 8.0

var _phase: DashPhase = DashPhase.NONE
var _elapsed: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _dash_right: Vector3 = Vector3.ZERO
var _dash_origin: Vector3 = Vector3.ZERO
var _dash_target: Vector3 = Vector3.ZERO
var _original_collision_layer: int = 0
var _original_collision_mask: int = 0
var _mesh_root: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree

## Raven instances and their paths
var _ravens: Array[Node3D] = []
var _raven_scene: PackedScene
## Per-raven bezier: Array of [P0, P1, P2, P3]
var _raven_paths: Array[Array] = []

## Feather burst VFX at origin and destination
var _burst_origin: GPUParticles3D
var _burst_landing: GPUParticles3D

## Combat-mode backstab: the target we're dashing behind
var _combat_target: CharacterBody3D
## Direction the player should face after landing (toward the enemy's back)
var _landing_face_dir: Vector3 = Vector3.ZERO
var _combat_dash_baffled_sent: bool = false

## Arc parameters for combat camera orbit
var _arc_center: Vector3 = Vector3.ZERO     ## Enemy position (XZ pivot)
var _arc_start_angle: float = 0.0           ## Angle from enemy to player start
var _arc_end_angle: float = 0.0             ## Angle from enemy to landing
var _arc_radius_start: float = 0.0          ## Distance: enemy → origin
var _arc_radius_end: float = 0.0            ## Distance: enemy → landing
var _landing_anim_duration: float = 0.4     ## Computed from anim length - seek
var _sustained_heading: Vector3 = Vector3.FORWARD
var _sustained_orbit_time: float = 0.0
var _sustained_raven_offsets: Array[Vector3] = []
var _sustained_mode: bool = false
var _sustained_exit_requested: bool = false
var _sustained_converge_starts: Array[Vector3] = []
var _target_preview_root: Node3D
var _target_preview_mesh: MeshInstance3D
var _target_preview_material: StandardMaterial3D
var _target_preview_valid: bool = false
var _target_preview_point: Vector3 = Vector3.ZERO
var _target_preview_normal: Vector3 = Vector3.UP


func _init() -> void:
	spell_name = "Hrafn"
	verb_name = "Dash"
	description = "Raven's Dash — scatter into ravens"
	slot_type = 0
	cooldown = 1.2
	hugr_cost = 0.15
	catalyst_name = "Crow Feathers + Bone Ash"


func is_active() -> bool:
	return _phase != DashPhase.NONE


func can_start_sustained(player: CharacterBody3D) -> bool:
	if _phase != DashPhase.NONE or not is_ready() or not player:
		return false
	if player.has_method("is_in_combat_mode") and bool(player.is_in_combat_mode()):
		return false
	if player.has_method("is_dead") and bool(player.is_dead()):
		return false
	if player.has_method("get_stamina") and float(player.get_stamina()) <= 0.0:
		return false
	return true


func can_start_targeted(player: CharacterBody3D) -> bool:
	if _phase != DashPhase.NONE or not is_ready() or not player:
		return false
	if player.has_method("is_in_combat_mode") and bool(player.is_in_combat_mode()):
		return false
	if player.has_method("is_dead") and bool(player.is_dead()):
		return false
	return true


func start_targeted(player: CharacterBody3D) -> bool:
	if not can_start_targeted(player):
		return false
	_cache_player_refs(player)
	_dash_origin = player.global_position
	_combat_target = null
	_landing_face_dir = Vector3.ZERO
	_target_preview_valid = false
	_target_preview_point = _dash_origin
	_target_preview_normal = Vector3.UP
	_ensure_target_preview(player)
	_update_target_preview(player)
	if player.has_method("set_action_locked"):
		player.set_action_locked(true)
	player.velocity = Vector3.ZERO
	_phase = DashPhase.TARGETING
	_elapsed = 0.0
	return true


func confirm_targeted(player: CharacterBody3D) -> bool:
	if _phase != DashPhase.TARGETING:
		return false
	if not _target_preview_valid:
		cancel(player)
		return false
	if not super.cast(player):
		cancel(player)
		return false
	if not _ensure_raven_scene():
		cancel(player)
		return false

	_dash_origin = player.global_position
	_dash_target = _target_preview_point
	_dash_direction = _dash_target - _dash_origin
	_dash_direction.y = 0.0
	if _dash_direction.length_squared() <= 0.001:
		cancel(player)
		return false
	_dash_direction = _dash_direction.normalized()
	_dash_right = _dash_direction.cross(Vector3.UP).normalized()
	_landing_face_dir = _dash_direction
	_cleanup_target_preview()
	_store_player_collision(player)

	var xbot := player.get_node_or_null("xbot_root") as Node3D
	if xbot and xbot.has_method("play_action") and _anim_player and _anim_player.has_animation(DIVE_ROLL_ANIM):
		xbot.play_action(DIVE_ROLL_ANIM, 0.2, 0.2)
	if _mesh_root and _dash_direction.length_squared() > 0.001:
		_mesh_root.rotation.y = atan2(_dash_direction.x, _dash_direction.z)

	_phase = DashPhase.DIVE_INTRO
	_elapsed = 0.0
	return true


func start_sustained(player: CharacterBody3D) -> bool:
	if not can_start_sustained(player):
		return false
	if not _ensure_raven_scene():
		return false
	if not super.cast(player):
		return false

	_dash_origin = player.global_position
	_dash_target = _dash_origin
	_combat_target = null
	_landing_face_dir = Vector3.ZERO
	_cache_player_refs(player)
	_store_player_collision(player)
	_sustained_heading = _get_sustained_move_direction(player)
	if _sustained_heading.length_squared() <= 0.0001:
		_sustained_heading = -player.global_transform.basis.z
		_sustained_heading.y = 0.0
		if _sustained_heading.length_squared() > 0.0001:
			_sustained_heading = _sustained_heading.normalized()
	_sustained_orbit_time = 0.0
	_sustained_mode = true
	_sustained_exit_requested = false
	_sustained_converge_starts.clear()

	if player.has_method("set_action_locked"):
		player.set_action_locked(true)

	var xbot := player.get_node_or_null("xbot_root") as Node3D
	if xbot and xbot.has_method("play_action") and _anim_player and _anim_player.has_animation(DIVE_ROLL_ANIM):
		xbot.play_action(DIVE_ROLL_ANIM, 0.2, 0.2)
	if _mesh_root and _sustained_heading.length_squared() > 0.001:
		_mesh_root.rotation.y = atan2(_sustained_heading.x, _sustained_heading.z)

	_phase = DashPhase.DIVE_INTRO
	_elapsed = 0.0
	return true


func cast(player: CharacterBody3D) -> bool:
	if _phase != DashPhase.NONE:
		return false
	if not super.cast(player):
		return false

	if not _ensure_raven_scene():
		push_error("[Hrafn] Cannot load raven scene: " + RAVEN_SCENE_PATH)
		return false

	_dash_origin = player.global_position
	_combat_target = null
	_landing_face_dir = Vector3.ZERO

	# ── Check combat mode — if fighting, dash behind the target ─────────
	var in_combat := player.has_method("is_in_combat_mode") and bool(player.is_in_combat_mode())
	var target: CharacterBody3D = null
	if in_combat and player.has_method("get_combat_target"):
		target = player.get_combat_target() as CharacterBody3D
		if target and not is_instance_valid(target):
			target = null

	if target:
		_cast_combat(player, target)
	else:
		_cast_exploration(player)

	# ── Common setup ────────────────────────────────────────────────────
	_cache_player_refs(player)
	_store_player_collision(player)

	if player.has_method("set_action_locked"):
		player.set_action_locked(true)

	# ── Play dive roll intro (mesh stays visible) ──────────────────────
	var xbot := player.get_node_or_null("xbot_root") as Node3D
	if xbot and xbot.has_method("play_action") and _anim_player and _anim_player.has_animation(DIVE_ROLL_ANIM):
		xbot.play_action(DIVE_ROLL_ANIM, 0.2, 0.2)

	# Face the dash direction
	if _mesh_root and _dash_direction.length_squared() > 0.001:
		_mesh_root.rotation.y = atan2(_dash_direction.x, _dash_direction.z)

	_phase = DashPhase.DIVE_INTRO
	_elapsed = 0.0
	return true


## ── Combat mode: dash behind the locked-on enemy ───────────────────────────

func _cast_combat(player: CharacterBody3D, target: CharacterBody3D) -> void:
	_combat_target = target
	_combat_dash_baffled_sent = false

	# Land strictly on the enemy's back-facing side, not merely the far side from the player.
	var visual_root := target.get_node_or_null("ybot_root") as Node3D
	if not visual_root:
		visual_root = target.get_node_or_null("xbot_root") as Node3D
	var target_forward := visual_root.global_transform.basis.z if visual_root else target.global_transform.basis.z
	target_forward.y = 0.0
	if target_forward.length_squared() > 0.001:
		target_forward = target_forward.normalized()
	else:
		target_forward = (target.global_position - player.global_position)
		target_forward.y = 0.0
		target_forward = target_forward.normalized()
	var back_dir := -target_forward

	# Landing point: directly behind the enemy along their facing direction.
	var landing := target.global_position + back_dir * combat_behind_offset

	# Validate landing against walls
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		target.global_position + Vector3(0.0, 0.8, 0.0),
		landing + Vector3(0.0, 0.8, 0.0)
	)
	query.collision_mask = 1
	query.exclude = [player.get_rid(), target.get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
		# Wall blocks — land as close as we can while staying behind the target.
		landing = Vector3(hit.position.x, target.global_position.y, hit.position.z) - back_dir * 0.3

	_dash_target = Vector3(landing.x, _dash_origin.y, landing.z)

	# Dash direction: from origin toward the landing point
	_dash_direction = (_dash_target - _dash_origin)
	_dash_direction.y = 0.0
	if _dash_direction.length_squared() > 0.001:
		_dash_direction = _dash_direction.normalized()
	else:
		_dash_direction = back_dir
	_dash_right = _dash_direction.cross(Vector3.UP).normalized()

	# After landing, face toward the enemy (for the backstab)
	_landing_face_dir = (target.global_position - _dash_target)
	_landing_face_dir.y = 0.0
	if _landing_face_dir.length_squared() > 0.001:
		_landing_face_dir = _landing_face_dir.normalized()

	# Pre-compute arc orbit data for the camera
	_arc_center = Vector3(target.global_position.x, _dash_origin.y, target.global_position.z)
	var to_start := Vector2(_dash_origin.x - _arc_center.x, _dash_origin.z - _arc_center.z)
	var to_end := Vector2(_dash_target.x - _arc_center.x, _dash_target.z - _arc_center.z)
	_arc_start_angle = to_start.angle()
	_arc_end_angle = to_end.angle()
	_arc_radius_start = to_start.length()
	_arc_radius_end = to_end.length()
	# Pick the shorter arc direction
	var diff := angle_difference(_arc_start_angle, _arc_end_angle)
	_arc_end_angle = _arc_start_angle + diff
	_notify_combat_target_dash_behind(_dash_target)


## ── Exploration mode: dash in camera-facing direction ──────────────────────

func _cast_exploration(player: CharacterBody3D) -> void:
	# Direction: camera-facing, flattened to XZ plane
	var cam_pivot := player.get_node_or_null("CameraPivot") as Node3D
	if cam_pivot:
		_dash_direction = -cam_pivot.global_transform.basis.z
	else:
		var visual := player.get_node_or_null("xbot_root") as Node3D
		_dash_direction = visual.global_transform.basis.z if visual else -player.global_transform.basis.z
	_dash_direction.y = 0.0
	_dash_direction = _dash_direction.normalized()
	_dash_right = _dash_direction.cross(Vector3.UP).normalized()

	# Destination: forward along camera direction, blocked by walls
	var ray_start := _dash_origin + Vector3(0.0, 0.8, 0.0)
	var ray_end := ray_start + _dash_direction * dash_distance

	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = 1  # Static world / terrain only
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
		ray_end = hit.position - _dash_direction * 0.4

	_dash_target = Vector3(ray_end.x, _dash_origin.y, ray_end.z)
	_landing_face_dir = _dash_direction


# ── Physics tick ─────────────────────────────────────────────────────────────

func physics_update(player: CharacterBody3D, delta: float) -> void:
	if _phase == DashPhase.NONE:
		return
	_elapsed += delta

	match _phase:
		DashPhase.TARGETING:
			_tick_targeting(player)
		DashPhase.DIVE_INTRO:
			_tick_dive_intro(player)
		DashPhase.SCATTER:
			_tick_scatter(player)
		DashPhase.FLYING:
			_tick_flying(player)
		DashPhase.CONVERGE:
			_tick_converge(player)
		DashPhase.LANDING:
			_tick_landing(player)
		DashPhase.RECOVERY:
			_tick_recovery(player)
		DashPhase.SUSTAINED:
			_tick_sustained(player, delta)
		DashPhase.SUSTAINED_CONVERGE:
			_tick_sustained_converge(player)


func _tick_targeting(player: CharacterBody3D) -> void:
	if player.has_method("is_dead") and bool(player.is_dead()):
		cancel(player)
		return
	if player.has_method("is_in_combat_mode") and bool(player.is_in_combat_mode()):
		cancel(player)
		return
	player.velocity = Vector3.ZERO
	_update_target_preview(player)


func _tick_sustained(player: CharacterBody3D, delta: float) -> void:
	if player.has_method("is_dead") and bool(player.is_dead()):
		_begin_sustained_exit(player)
		return
	if player.has_method("is_in_combat_mode") and bool(player.is_in_combat_mode()):
		_begin_sustained_exit(player)
		return
	if not Input.is_action_pressed("curse_pulse") or not Input.is_action_pressed("sprint"):
		_begin_sustained_exit(player)
		return

	if player.has_method("drain_stamina"):
		player.drain_stamina(sustained_stamina_cost_per_second * delta)
	if player.has_method("get_stamina") and float(player.get_stamina()) <= 0.0:
		_begin_sustained_exit(player)
		return

	var move_dir := _get_sustained_move_direction(player)
	if move_dir.length_squared() > 0.0001:
		if _sustained_heading.length_squared() <= 0.0001:
			_sustained_heading = move_dir
		else:
			var turn_t := clampf(sustained_heading_response * delta, 0.0, 1.0)
			_sustained_heading = _sustained_heading.lerp(move_dir, turn_t).normalized()
	if _sustained_heading.length_squared() <= 0.0001:
		_sustained_heading = -player.global_transform.basis.z
		if _sustained_heading.length_squared() > 0.0001:
			_sustained_heading = _sustained_heading.normalized()

	var active_heading := _sustained_heading if move_dir.length_squared() > 0.0001 else Vector3.ZERO
	var travel_step := active_heading * sustained_speed * delta
	var next_pos := player.global_position + travel_step
	if active_heading.length_squared() > 0.0001:
		var ray_start := player.global_position + Vector3(0.0, 0.8, 0.0)
		var ray_end := next_pos + Vector3(0.0, 0.8, 0.0)
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collision_mask = 1
		query.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			var safe_pos: Vector3 = hit.position - active_heading * sustained_obstacle_buffer
			player.global_position = safe_pos
			player.velocity = Vector3.ZERO
			_begin_sustained_exit(player)
			return

	if active_heading.length_squared() > 0.0001:
		player.global_position = next_pos
	player.velocity = Vector3.ZERO
	_update_sustained_ravens(player, delta)


func _tick_sustained_converge(player: CharacterBody3D) -> void:
	var t := clampf(_elapsed / converge_duration, 0.0, 1.0)
	var target := player.global_position + Vector3(0.0, 1.0, 0.0)
	for i in _ravens.size():
		if not is_instance_valid(_ravens[i]):
			continue
		var start_pos := _sustained_converge_starts[i] if i < _sustained_converge_starts.size() else _ravens[i].global_position
		_ravens[i].global_position = start_pos.lerp(target, _ease_in(t))
	player.velocity = Vector3.ZERO
	if t >= 1.0:
		_start_reform_landing(player)


func _tick_dive_intro(player: CharacterBody3D) -> void:
	var t := clampf(_elapsed / dive_intro_duration, 0.0, 1.0)
	if t >= 1.0:
		# Hide mesh, disable collision, transition to raven flight
		if _mesh_root:
			_mesh_root.visible = false
		# Abort the OneShot dive-roll, then deactivate the tree to prevent
		# root-motion conflicts while ravens are flying.
		var xbot := player.get_node_or_null("xbot_root") as Node3D
		if xbot and xbot.has_method("abort_action"):
			xbot.abort_action()
		if _anim_tree:
			_anim_tree.active = false

		player.collision_layer = 0
		player.collision_mask = 0
		player.velocity = Vector3.ZERO

		if _sustained_mode:
			_spawn_sustained_ravens(player)
			_burst_origin = _create_feather_burst(40)
			player.get_tree().root.add_child(_burst_origin)
			_burst_origin.global_position = _dash_origin + Vector3(0.0, 1.0, 0.0)
			_burst_origin.emitting = true
			_phase = DashPhase.SUSTAINED
			_elapsed = 0.0
			if _sustained_exit_requested:
				_begin_sustained_exit(player)
			return

		# ── Detect enemies in the flight corridor ───────────────────
		var space := player.get_world_3d().direct_space_state
		var obstacles := _find_corridor_obstacles(player, space)

		# ── Build bezier paths for each raven ───────────────────────
		_build_raven_paths(obstacles)

		# ── Spawn ravens ────────────────────────────────────────────
		_spawn_ravens(player)

		# ── Origin burst VFX ────────────────────────────────────────
		_burst_origin = _create_feather_burst(40)
		player.get_tree().root.add_child(_burst_origin)
		_burst_origin.global_position = _dash_origin + Vector3(0.0, 1.0, 0.0)
		_burst_origin.emitting = true

		_phase = DashPhase.SCATTER
		_elapsed = 0.0


func _tick_scatter(player: CharacterBody3D) -> void:
	var t := clampf(_elapsed / scatter_duration, 0.0, 1.0)
	# Ravens expand from origin point outward to their P0
	for i in _ravens.size():
		if not is_instance_valid(_ravens[i]):
			continue
		var p0: Vector3 = _raven_paths[i][0]
		var center := _dash_origin + Vector3(0.0, 1.0, 0.0)
		_ravens[i].global_position = center.lerp(p0, _ease_out(t))
		# Face flight direction
		var dir := p0 - center
		if dir.length_squared() > 0.001:
			_ravens[i].look_at(_ravens[i].global_position + dir.normalized(), Vector3.UP)
	# Move player along dash path so the camera follows the flock
	player.global_position = _get_dash_position(t * 0.1)
	player.velocity = Vector3.ZERO
	if t >= 1.0:
		_phase = DashPhase.FLYING
		_elapsed = 0.0


func _tick_flying(player: CharacterBody3D) -> void:
	var t := clampf(_elapsed / flight_duration, 0.0, 1.0)
	for i in _ravens.size():
		if not is_instance_valid(_ravens[i]):
			continue
		if _ravens[i].has_method("advance"):
			_ravens[i].advance(t)
		else:
			# Fallback manual bezier
			_ravens[i].global_position = _eval_bezier(i, t)
	# Move player along dash path so the camera follows the flock
	# 0.1..0.9 range — scatter already covered the first 10%, converge handles the last
	player.global_position = _get_dash_position(0.1 + t * 0.8)
	player.velocity = Vector3.ZERO
	if t >= 1.0:
		_phase = DashPhase.CONVERGE
		_elapsed = 0.0


func _tick_converge(player: CharacterBody3D) -> void:
	var t := clampf(_elapsed / converge_duration, 0.0, 1.0)
	var target := _dash_target + Vector3(0.0, 1.0, 0.0)
	for i in _ravens.size():
		if not is_instance_valid(_ravens[i]):
			continue
		var end_pos: Vector3 = _raven_paths[i][3]
		_ravens[i].global_position = end_pos.lerp(target, _ease_in(t))
	# Slide player the last 10% to the destination
	player.global_position = _get_dash_position(0.9 + t * 0.1)
	player.velocity = Vector3.ZERO
	if t >= 1.0:
		# Place player at destination, show mesh, clean up ravens
		player.global_position = _dash_target
		player.velocity = Vector3.ZERO
		_notify_combat_target_dash_behind(player.global_position)
		# Restore collision
		player.collision_layer = _original_collision_layer
		player.collision_mask = _original_collision_mask
		# Show player
		if _mesh_root:
			_mesh_root.visible = true
		# Face landing direction (toward enemy in combat, forward in exploration)
		var visual := player.get_node_or_null("xbot_root") as Node3D
		if visual and _landing_face_dir.length_squared() > 0.001:
			visual.rotation.y = atan2(_landing_face_dir.x, _landing_face_dir.z)
		# Landing burst
		_burst_landing = _create_feather_burst(32)
		player.get_tree().root.add_child(_burst_landing)
		_burst_landing.global_position = _dash_target + Vector3(0.0, 1.0, 0.0)
		_burst_landing.emitting = true
		# Despawn ravens
		_despawn_ravens()

		# ── Play landing animation from 1s in ──────────────────────
		if _anim_player and _anim_player.has_animation(LANDING_ANIM):
			_anim_player.play(LANDING_ANIM, 0.15)
			_anim_player.seek(LANDING_SEEK_TIME, true)
			var anim_res := _anim_player.get_animation(LANDING_ANIM)
			var remaining := (anim_res.length - LANDING_SEEK_TIME) if anim_res else recovery_duration
			_phase = DashPhase.LANDING
			_elapsed = 0.0
			# Store remaining duration for the landing phase
			_landing_anim_duration = maxf(remaining, 0.1)
		else:
			_phase = DashPhase.RECOVERY
			_elapsed = 0.0


func _tick_landing(player: CharacterBody3D) -> void:
	var t := clampf(_elapsed / _landing_anim_duration, 0.0, 1.0)
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	if t >= 1.0:
		# Crossfade into idle on the AnimationPlayer so the pose blends out
		# smoothly before the tree takes back over.
		var idle_anim := &"PlayerMovement/idle"
		if player.has_method("is_in_combat_mode") and player.is_in_combat_mode():
			idle_anim = &"npc_axe/standing_idle"
		if _anim_player and _anim_player.has_animation(idle_anim):
			_anim_player.play(idle_anim, 0.25)
		_phase = DashPhase.RECOVERY
		_elapsed = 0.0


func _tick_recovery(player: CharacterBody3D) -> void:
	var t := clampf(_elapsed / recovery_duration, 0.0, 1.0)
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	if t >= 1.0:
		_finish(player)


func _finish(player: CharacterBody3D) -> void:
	var final_heading := _sustained_heading
	_phase = DashPhase.NONE
	_elapsed = 0.0
	_combat_target = null
	_combat_dash_baffled_sent = false
	_landing_face_dir = Vector3.ZERO
	_sustained_heading = Vector3.FORWARD
	_sustained_orbit_time = 0.0
	_sustained_raven_offsets.clear()
	_sustained_mode = false
	_sustained_exit_requested = false
	_sustained_converge_starts.clear()
	player.velocity = Vector3.ZERO
	player.collision_layer = _original_collision_layer
	player.collision_mask = _original_collision_mask
	if _mesh_root:
		_mesh_root.visible = true
	_despawn_ravens()
	# Reactivate the tree — the AnimationPlayer was playing idle during RECOVERY
	# so the pose is settled and the hand-off is seamless.
	if _anim_tree:
		var target_state := &"Idle"
		if player.has_method("is_in_combat_mode") and player.is_in_combat_mode():
			target_state = &"Combat"
		var playback: AnimationNodeStateMachinePlayback = _anim_tree["parameters/StateMachine/playback"]
		playback.start(target_state, true)
		_anim_tree.active = true
	if _mesh_root and final_heading.length_squared() > 0.0001:
		_mesh_root.rotation.y = atan2(final_heading.x, final_heading.z)
	if _anim_player:
		_anim_player.stop()
	if player.has_method("set_action_locked"):
		player.set_action_locked(false)
	_cleanup_bursts()
	_cleanup_target_preview()


func cancel(player: CharacterBody3D) -> void:
	if _phase == DashPhase.NONE:
		return
	if _phase == DashPhase.TARGETING:
		if player.has_method("set_action_locked"):
			player.set_action_locked(false)
		player.velocity = Vector3.ZERO
		_cleanup_target_preview()
		_combat_target = null
		_combat_dash_baffled_sent = false
		_landing_face_dir = Vector3.ZERO
		_phase = DashPhase.NONE
		_elapsed = 0.0
		return
	if _sustained_mode:
		if _phase == DashPhase.DIVE_INTRO:
			_sustained_exit_requested = true
			return
		if _phase == DashPhase.SUSTAINED:
			_begin_sustained_exit(player)
			return
		if _phase == DashPhase.SUSTAINED_CONVERGE:
			return
		if _phase in [DashPhase.LANDING, DashPhase.RECOVERY]:
			return
	if _phase == DashPhase.SUSTAINED:
		_finish(player)
		return
	player.collision_layer = _original_collision_layer
	player.collision_mask = _original_collision_mask
	if _mesh_root:
		_mesh_root.visible = true
	var xbot := player.get_node_or_null("xbot_root") as Node3D
	if xbot and xbot.has_method("abort_action"):
		xbot.abort_action()
	if _anim_player:
		_anim_player.stop()
	if _anim_tree:
		_anim_tree.active = true
	if player.has_method("set_action_locked"):
		player.set_action_locked(false)
	_despawn_ravens()
	_cleanup_bursts()
	_combat_target = null
	_combat_dash_baffled_sent = false
	_landing_face_dir = Vector3.ZERO
	_phase = DashPhase.NONE
	_elapsed = 0.0
	_sustained_heading = Vector3.FORWARD
	_sustained_orbit_time = 0.0
	_sustained_raven_offsets.clear()
	_sustained_mode = false
	_sustained_exit_requested = false


func _notify_combat_target_dash_behind(landing_pos: Vector3) -> void:
	if _combat_dash_baffled_sent or not _combat_target or not is_instance_valid(_combat_target):
		return
	var bandit_fsm := _combat_target.get_node_or_null("BanditFSM")
	if not bandit_fsm or not bandit_fsm.has_method("on_hrafn_dash_behind"):
		return
	bandit_fsm.on_hrafn_dash_behind(landing_pos)
	_combat_dash_baffled_sent = true
	_sustained_converge_starts.clear()
	_cleanup_target_preview()


# ── Obstacle detection ───────────────────────────────────────────────────────

func _find_corridor_obstacles(player: CharacterBody3D, _space: PhysicsDirectSpaceState3D) -> Array[Dictionary]:
	## Returns [{position, radius}] for each enemy body in the dash corridor.
	var obstacles: Array[Dictionary] = []
	var half_dist := _dash_origin.distance_to(_dash_target) * 0.5
	var _corridor_center := _dash_origin + _dash_direction * half_dist + Vector3(0.0, 1.0, 0.0)

	for body in player.get_tree().get_nodes_in_group("bandit"):
		if not is_instance_valid(body) or not body is Node3D:
			continue
		var bpos: Vector3 = body.global_position
		# Project onto dash line
		var to_body := bpos - _dash_origin
		var along := to_body.dot(_dash_direction)
		if along < -0.5 or along > _dash_origin.distance_to(_dash_target) + 0.5:
			continue  # Behind us or past destination
		var closest_on_line := _dash_origin + _dash_direction * along
		var lateral_dist := Vector3(bpos.x - closest_on_line.x, 0.0, bpos.z - closest_on_line.z).length()
		if lateral_dist < obstacle_detect_radius:
			var r := 0.5  # Default enemy radius
			if body is CharacterBody3D:
				var shape := body.get_node_or_null("CollisionShape3D")
				if shape and shape is CollisionShape3D and shape.shape is CapsuleShape3D:
					r = shape.shape.radius
			obstacles.append({"position": bpos, "radius": r, "along": along})
	# Sort by distance along dash direction
	obstacles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.along < b.along)
	return obstacles


# ── Bezier path construction ─────────────────────────────────────────────────

func _build_raven_paths(obstacles: Array[Dictionary]) -> void:
	_raven_paths.clear()
	var flight_height := 1.0  # Base height above ground

	## Raven layout:
	##   0 = Left-High    1 = Left-Low
	##   2 = Right-High   3 = Right-Low
	##   4 = Random-Mid
	var raven_sides: Array[float] = [-1.0, -1.0, 1.0, 1.0, [-1.0, 1.0].pick_random()]
	var raven_heights: Array[float] = [
		flight_height + avoidance_vertical_hi,   # Left-High
		flight_height + avoidance_vertical_lo,   # Left-Low
		flight_height + avoidance_vertical_hi,   # Right-High
		flight_height + avoidance_vertical_lo,   # Right-Low
		flight_height + (avoidance_vertical_hi + avoidance_vertical_lo) * 0.5,  # Mid
	]

	var total_dist := _dash_origin.distance_to(_dash_target)
	if total_dist < 0.1:
		total_dist = 0.1

	for i in RAVEN_COUNT:
		var side: float = raven_sides[i]
		var h: float = raven_heights[i]

		# Start and end points — slightly spread at origin, converge at target
		var start_spread := _dash_right * side * base_spread * 0.5
		var p0 := _dash_origin + Vector3(0.0, h, 0.0) + start_spread + _dash_direction * 0.3
		var p3 := _dash_target + Vector3(0.0, flight_height, 0.0)

		# Control points — default straight-ish
		var p1 := _dash_origin + _dash_direction * (total_dist * 0.33) + Vector3(0.0, h, 0.0) + _dash_right * side * base_spread
		var p2 := _dash_origin + _dash_direction * (total_dist * 0.66) + Vector3(0.0, h, 0.0) + _dash_right * side * base_spread * 0.3

		# Curve around obstacles
		for obs in obstacles:
			var _obs_pos: Vector3 = obs.position
			var obs_r: float = obs.radius
			var obs_along: float = obs.along
			var frac := obs_along / total_dist

			# Push control points laterally away from the obstacle
			var push := side * (avoidance_lateral + obs_r)
			var push_vec := _dash_right * push

			# Blend influence — strongest near the obstacle's along-fraction
			if frac < 0.5:
				# Obstacle in first half — push P1
				p1 += push_vec * (1.0 - frac)
				p2 += push_vec * 0.3
			else:
				# Obstacle in second half — push P2
				p1 += push_vec * 0.3
				p2 += push_vec * (frac)

			# Also push vertically for variety
			p1.y += (h - flight_height) * 0.2
			p2.y += (h - flight_height) * 0.1

		_raven_paths.append([p0, p1, p2, p3])


# ── Raven spawning ───────────────────────────────────────────────────────────

func _spawn_ravens(player: CharacterBody3D) -> void:
	_ravens.clear()
	var root := player.get_tree().root
	for i in RAVEN_COUNT:
		var raven := _raven_scene.instantiate() as Node3D
		root.add_child(raven)
		raven.global_position = _dash_origin + Vector3(0.0, 1.0, 0.0)
		# Set bezier path on the raven script
		if raven.has_method("set_flight_path"):
			var pts: Array = _raven_paths[i]
			raven.set_flight_path(pts[0], pts[1], pts[2], pts[3])
		_ravens.append(raven)


func _despawn_ravens() -> void:
	for raven in _ravens:
		if is_instance_valid(raven):
			if raven.has_method("finish"):
				raven.finish()
			raven.queue_free()
	_ravens.clear()


# ── Bezier evaluation (fallback) ─────────────────────────────────────────────

func _eval_bezier(raven_idx: int, t: float) -> Vector3:
	if raven_idx >= _raven_paths.size():
		return _dash_target
	var pts: Array = _raven_paths[raven_idx]
	var p0: Vector3 = pts[0]
	var p1: Vector3 = pts[1]
	var p2: Vector3 = pts[2]
	var p3: Vector3 = pts[3]
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3


# ── Easing helpers ───────────────────────────────────────────────────────────

func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 2.5)

func _ease_in(t: float) -> float:
	return pow(t, 2.0)


# ── Dash position (arc or linear) ───────────────────────────────────────────

func _get_dash_position(frac: float) -> Vector3:
	## Returns the player position at fraction `frac` (0..1) of the dash.
	## In combat: arcs around the enemy.  Otherwise: straight lerp.
	if _combat_target and is_instance_valid(_combat_target):
		var a := lerpf(_arc_start_angle, _arc_end_angle, frac)
		var r := lerpf(_arc_radius_start, _arc_radius_end, frac)
		return Vector3(
			_arc_center.x + cos(a) * r,
			_dash_origin.y,
			_arc_center.z + sin(a) * r,
		)
	return _dash_origin.lerp(_dash_target, frac)


# ── VFX ──────────────────────────────────────────────────────────────────────

func _create_feather_burst(count: int = 32) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = 0.9
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.randomness = 0.3

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.0, 0.5, 0.0)
	mat.spread = 180.0
	mat.initial_velocity_min = 2.5
	mat.initial_velocity_max = 5.5
	mat.gravity = Vector3(0.0, -2.0, 0.0)
	mat.damping_min = 2.0
	mat.damping_max = 4.0
	mat.scale_min = 0.04
	mat.scale_max = 0.12
	mat.color = Color(0.3, 0.1, 0.5, 0.9)

	var color_ramp := Gradient.new()
	color_ramp.set_offset(0, 0.0)
	color_ramp.set_color(0, Color(0.4, 0.15, 0.6, 1.0))
	color_ramp.add_point(0.5, Color(0.2, 0.05, 0.3, 0.8))
	color_ramp.set_offset(2, 1.0)
	color_ramp.set_color(2, Color(0.05, 0.02, 0.08, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	mat.color_ramp = color_tex
	particles.process_material = mat

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.08, 0.04)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.25, 0.08, 0.4, 0.9)
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh

	return particles


func _cleanup_bursts() -> void:
	for burst in [_burst_origin, _burst_landing]:
		if burst and is_instance_valid(burst):
			burst.emitting = false
			burst.get_tree().create_timer(1.5).timeout.connect(burst.queue_free)
	_burst_origin = null
	_burst_landing = null


func _begin_sustained_exit(player: CharacterBody3D) -> void:
	if not _sustained_mode:
		_finish(player)
		return
	if _phase == DashPhase.DIVE_INTRO:
		_sustained_exit_requested = true
		return
	if _phase != DashPhase.SUSTAINED:
		return
	_sustained_exit_requested = true
	if _sustained_heading.length_squared() <= 0.0001:
		_sustained_heading = -player.global_transform.basis.z
		_sustained_heading.y = 0.0
		if _sustained_heading.length_squared() > 0.0001:
			_sustained_heading = _sustained_heading.normalized()
	_landing_face_dir = _sustained_heading
	_sustained_converge_starts.clear()
	for raven in _ravens:
		_sustained_converge_starts.append(raven.global_position if is_instance_valid(raven) else player.global_position + Vector3(0.0, 1.0, 0.0))
	_phase = DashPhase.SUSTAINED_CONVERGE
	_elapsed = 0.0


func _start_reform_landing(player: CharacterBody3D) -> void:
	player.velocity = Vector3.ZERO
	player.collision_layer = _original_collision_layer
	player.collision_mask = _original_collision_mask
	if _mesh_root:
		_mesh_root.visible = true
	var visual := player.get_node_or_null("xbot_root") as Node3D
	if visual and _landing_face_dir.length_squared() > 0.001:
		visual.rotation.y = atan2(_landing_face_dir.x, _landing_face_dir.z)
	_burst_landing = _create_feather_burst(32)
	player.get_tree().root.add_child(_burst_landing)
	_burst_landing.global_position = player.global_position + Vector3(0.0, 1.0, 0.0)
	_burst_landing.emitting = true
	_despawn_ravens()
	if _anim_player and _anim_player.has_animation(LANDING_ANIM):
		_anim_player.play(LANDING_ANIM, 0.15)
		_anim_player.seek(LANDING_SEEK_TIME, true)
		var anim_res := _anim_player.get_animation(LANDING_ANIM)
		var remaining := (anim_res.length - LANDING_SEEK_TIME) if anim_res else recovery_duration
		_phase = DashPhase.LANDING
		_elapsed = 0.0
		_landing_anim_duration = maxf(remaining, 0.1)
	else:
		_phase = DashPhase.RECOVERY
		_elapsed = 0.0


func _ensure_raven_scene() -> bool:
	if not _raven_scene:
		_raven_scene = load(RAVEN_SCENE_PATH) as PackedScene
	return _raven_scene != null


func _update_target_preview(player: CharacterBody3D) -> void:
	if not _target_preview_root:
		return
	var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if not camera:
		_target_preview_root.visible = false
		_target_preview_valid = false
		return
	var view_center := player.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(view_center)
	var ray_dir := camera.project_ray_normal(view_center)
	var ray_end := ray_origin + ray_dir * targeted_ray_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = targeted_collision_mask
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_target_preview_root.visible = false
		_target_preview_valid = false
		return
	var landing_point := Vector3(hit.position.x, hit.position.y, hit.position.z)
	var landing_normal: Vector3 = hit["normal"] if hit.has("normal") else Vector3.UP
	var grounded_origin := Vector3(landing_point.x, landing_point.y + _get_player_ground_origin_offset(player), landing_point.z)
	var slope_limit_cos := cos(deg_to_rad(targeted_max_slope_deg))
	var distance_ok := _dash_origin.distance_to(grounded_origin) <= targeted_ray_distance
	var slope_ok: bool = landing_normal.normalized().dot(Vector3.UP) >= slope_limit_cos
	var space_ok := _can_fit_at_target(player, grounded_origin)
	_target_preview_point = grounded_origin
	_target_preview_normal = landing_normal
	_target_preview_valid = distance_ok and slope_ok and space_ok
	_target_preview_root.visible = true
	_target_preview_root.global_position = landing_point + landing_normal.normalized() * 0.04
	_target_preview_root.basis = _basis_from_up(landing_normal)
	_target_preview_material.albedo_color = Color(0.24, 0.82, 1.0, 0.45) if _target_preview_valid else Color(1.0, 0.28, 0.22, 0.45)


func _ensure_target_preview(player: CharacterBody3D) -> void:
	if _target_preview_root:
		return
	_target_preview_root = Node3D.new()
	_target_preview_root.name = "DashTargetPreview"
	_target_preview_mesh = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = targeted_marker_radius
	mesh.bottom_radius = targeted_marker_radius
	mesh.height = 0.05
	mesh.radial_segments = 32
	_target_preview_mesh.mesh = mesh
	_target_preview_material = StandardMaterial3D.new()
	_target_preview_material.albedo_color = Color(0.24, 0.82, 1.0, 0.45)
	_target_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_target_preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_target_preview_material.no_depth_test = true
	_target_preview_mesh.material_override = _target_preview_material
	_target_preview_root.add_child(_target_preview_mesh)
	player.get_tree().root.add_child(_target_preview_root)
	_target_preview_root.visible = false


func _cleanup_target_preview() -> void:
	if _target_preview_root and is_instance_valid(_target_preview_root):
		_target_preview_root.queue_free()
	_target_preview_root = null
	_target_preview_mesh = null
	_target_preview_material = null
	_target_preview_valid = false
	_target_preview_point = Vector3.ZERO
	_target_preview_normal = Vector3.UP


func _can_fit_at_target(player: CharacterBody3D, target_origin: Vector3) -> bool:
	var shape_node := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not shape_node or not shape_node.shape:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape_node.shape
	query.transform = Transform3D(player.global_transform.basis, target_origin) * shape_node.transform
	query.collision_mask = targeted_collision_mask
	query.exclude = [player.get_rid()]
	var hits := player.get_world_3d().direct_space_state.intersect_shape(query, 1)
	return hits.is_empty()


func _basis_from_up(up: Vector3) -> Basis:
	var y_axis := up.normalized()
	if y_axis.length_squared() <= 0.0001:
		return Basis.IDENTITY
	var tangent := Vector3.FORWARD
	if absf(y_axis.dot(tangent)) > 0.95:
		tangent = Vector3.RIGHT
	var x_axis := tangent.cross(y_axis).normalized()
	var z_axis := y_axis.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _cache_player_refs(player: CharacterBody3D) -> void:
	_mesh_root = player.get_node_or_null("xbot_root") as Node3D
	_anim_player = player.get_node_or_null("xbot_root/AnimationPlayer") as AnimationPlayer
	_anim_tree = player.get_node_or_null("xbot_root/AnimationTree") as AnimationTree


func _store_player_collision(player: CharacterBody3D) -> void:
	_original_collision_layer = player.collision_layer
	_original_collision_mask = player.collision_mask


func _get_sustained_move_direction(player: CharacterBody3D) -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length_squared() <= 0.0001:
		return Vector3.ZERO
	var cam_pivot := player.get_node_or_null("CameraPivot") as Node3D
	var cam_basis := cam_pivot.global_transform.basis if cam_pivot else player.global_transform.basis
	var flat_forward := -cam_basis.z
	flat_forward.y = 0.0
	if flat_forward.length_squared() <= 0.0001:
		flat_forward = -player.global_transform.basis.z
		flat_forward.y = 0.0
	flat_forward = flat_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0.0
	if cam_right.length_squared() <= 0.0001:
		cam_right = player.global_transform.basis.x
	cam_right = cam_right.normalized()
	var move_dir := cam_right * input.x + flat_forward * -input.y
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()
	return move_dir.normalized()


func _get_sustained_grounded_origin_y(player: CharacterBody3D, sample_position: Vector3) -> float:
	var standing_offset := _get_player_ground_origin_offset(player)
	var query := PhysicsRayQueryParameters3D.create(
		sample_position + Vector3(0.0, 6.0, 0.0),
		sample_position - Vector3(0.0, 24.0, 0.0)
	)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		return hit.position.y + standing_offset
	return sample_position.y


func _get_player_ground_origin_offset(player: CharacterBody3D) -> float:
	var shape_node := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not shape_node or not shape_node.shape:
		return 0.0
	var bottom_local_y := shape_node.transform.origin.y
	if shape_node.shape is CapsuleShape3D:
		var capsule := shape_node.shape as CapsuleShape3D
		bottom_local_y -= capsule.height * 0.5 + capsule.radius
	elif shape_node.shape is SphereShape3D:
		var sphere := shape_node.shape as SphereShape3D
		bottom_local_y -= sphere.radius
	elif shape_node.shape is BoxShape3D:
		var box := shape_node.shape as BoxShape3D
		bottom_local_y -= box.size.y * 0.5
	return -bottom_local_y


func _spawn_sustained_ravens(player: CharacterBody3D) -> void:
	_despawn_ravens()
	_sustained_raven_offsets.clear()
	var root := player.get_tree().root
	for i in RAVEN_COUNT:
		var raven := _raven_scene.instantiate() as Node3D
		root.add_child(raven)
		var angle := TAU * float(i) / float(RAVEN_COUNT)
		var radius := 0.85 + 0.12 * float(i % 2)
		var offset := Vector3(cos(angle) * radius, 1.0 + 0.12 * float(i % 3), sin(angle) * radius)
		_sustained_raven_offsets.append(offset)
		var origin := player.global_position + offset
		raven.global_position = origin
		if raven.has_method("set_flight_path"):
			raven.set_flight_path(origin, origin, origin, origin)
		_ravens.append(raven)


func _update_sustained_ravens(player: CharacterBody3D, delta: float) -> void:
	_sustained_orbit_time += delta * 4.0
	var heading_angle := atan2(_sustained_heading.x, _sustained_heading.z)
	var heading_basis := Basis(Vector3.UP, heading_angle)
	for i in _ravens.size():
		var raven := _ravens[i]
		if not is_instance_valid(raven):
			continue
		var base_offset := _sustained_raven_offsets[i] if i < _sustained_raven_offsets.size() else Vector3.ZERO
		var orbit_angle := _sustained_orbit_time + TAU * float(i) / float(RAVEN_COUNT)
		var orbit_offset := Vector3(cos(orbit_angle) * 0.2, sin(orbit_angle * 1.7) * 0.08, sin(orbit_angle) * 0.2)
		var world_offset := heading_basis * (base_offset + orbit_offset)
		raven.global_position = player.global_position + world_offset - _sustained_heading * 0.35
		raven.look_at(raven.global_position + _sustained_heading, Vector3.UP)
