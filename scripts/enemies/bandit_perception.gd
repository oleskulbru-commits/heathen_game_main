extends Node
## Sensing-only component for bandits.
## Computes sight and sound stimuli, then reports them to BanditBrain.

const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")
const PlayerFinder := preload("res://scripts/common/player_finder.gd")

@export var sight_range: float = 25.0
@export var sight_fov_deg: float = 110.0
@export var inner_fov_deg: float = 40.0
@export var peripheral_rate_mult: float = 0.5
@export var sneak_detect_range: float = 1.0
@export var darkness_stand_detect_range: float = 4.5
@export var crouch_range_mult: float = 0.5
@export var moving_range_mult: float = 1.3
@export var sprint_range_mult: float = 1.5
@export var sight_check_interval: float = 0.05
@export var height_advantage_mult: float = 0.4
@export var instant_visual_combat: bool = false

@export var hearing_range_sprint: float = 20.0
@export var hearing_range_walk: float = 8.0
@export var hearing_range_crouch_walk: float = 3.0
@export var sound_occlusion_mult: float = 0.3

@export var suspicion_rate_sight: float = 1.8
@export var suspicion_rate_sound_sprint: float = 0.35
@export var suspicion_rate_sound_walk: float = 0.15
@export var suspicion_rate_sound_crouch: float = 0.05
@export var suspicion_drain_rate: float = 0.12
@export var exposure_buildup_rate: float = 2.5
@export var exposure_drain_rate: float = 0.8

var _sight_timer: float = 0.0
var _suspicion_input: float = 0.0
var _sight_rate: float = 0.0
var _player_ref: CharacterBody3D
var _light_probe: Node
var _bandit: CharacterBody3D
var _brain: Node


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	await get_tree().process_frame
	_player_ref = PlayerFinder.find(get_tree())
	if _player_ref:
		_light_probe = _player_ref.get_node_or_null("LightProbe")
	if _bandit:
		_brain = _bandit.get_node_or_null("BanditBrain")
	_sight_timer = sight_check_interval


func _physics_process(delta: float) -> void:
	if not _player_ref or not _bandit or not _brain:
		return
	if _player_ref.has_method("is_dead") and bool(_player_ref.is_dead()):
		_sight_rate = 0.0
		_suspicion_input = 0.0
		_brain.set_visual_contact(false)
		if _brain.alert_level != 0 and _brain.has_method("reset_alert"):
			_brain.reset_alert()
		return

	_brain.update_player_state(_player_ref.global_position, _player_ref.velocity)
	_suspicion_input = _sight_rate
	_sight_timer += delta

	if _sight_timer >= sight_check_interval:
		_sight_timer = 0.0
		_check_sight()
		_suspicion_input = _sight_rate

	_brain.update_exposure(_brain.has_visual_contact(), delta, exposure_buildup_rate, exposure_drain_rate)
	_check_sound()

	var next_suspicion: float = float(_brain.suspicion)
	if _suspicion_input > 0.0:
		next_suspicion = minf(next_suspicion + _suspicion_input * delta, 1.0)
	else:
		var eff_drain: float = suspicion_drain_rate * (1.0 - float(_brain.get_exposure()) * 0.7)
		next_suspicion = maxf(next_suspicion - eff_drain * delta, 0.0)

	_brain.apply_suspicion(next_suspicion, delta, _suspicion_input > 0.0)


func _check_sight() -> void:
	_sight_rate = 0.0
	_brain.set_visual_contact(false)
	var player_pos := _player_ref.global_position + BanditShared.PLAYER_CHEST_HEIGHT
	var bandit_pos := _bandit.global_position + BanditShared.BANDIT_EYE_HEIGHT
	var to_player := player_pos - bandit_pos
	var dist := to_player.length()

	# ── Compute effective sight range from light visibility ─────────────
	var visibility := 1.0
	if _light_probe and _light_probe.has_method("get_visibility"):
		visibility = _light_probe.get_visibility()

	var is_crouching := false
	if _player_ref.has_method("is_in_stealth"):
		is_crouching = _player_ref.is_in_stealth()
	var light_factor := clampf(sqrt(visibility), 0.0, 1.0)
	var effective_range := sight_range
	if is_crouching:
		effective_range = lerpf(sneak_detect_range, sight_range * crouch_range_mult, light_factor)
	else:
		effective_range = lerpf(darkness_stand_detect_range, sight_range, light_factor)

	effective_range *= _brain.get_heightened_sight_multiplier()

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

	var current_fov := sight_fov_deg
	current_fov += _brain.get_heightened_fov_bonus()

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
	_brain.set_visual_contact(true)
	_brain.remember_last_known_position(player_base)
	if instant_visual_combat:
		_brain.force_combat(player_base)


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
		_brain.remember_last_known_position(sound_pos)
		heard = true
	elif player_moving and player_crouching and dist <= eff_crouch:
		var proximity := 1.0 - clampf(dist / eff_crouch, 0.0, 1.0)
		_suspicion_input += suspicion_rate_sound_crouch * proximity
		_brain.remember_last_known_position(sound_pos)
		heard = true
	elif player_moving and not player_crouching and dist <= eff_walk:
		var proximity := 1.0 - clampf(dist / eff_walk, 0.0, 1.0)
		_suspicion_input += suspicion_rate_sound_walk * proximity
		_brain.remember_last_known_position(sound_pos)
		heard = true

	if heard and _brain.alert_level == 0:
		_brain.emit_heard_noise(_approximate_sound_pos(sound_pos))


func _approximate_sound_pos(exact_pos: Vector3) -> Vector3:
	## Phase 1b: Snaps to a 3 m grid then adds distance-proportional noise.
	## Bandits hear “roughly where” not “exactly where” the player made a sound.
	var snapped_pos := Vector3(
		roundf(exact_pos.x / 3.0) * 3.0,
		exact_pos.y,
		roundf(exact_pos.z / 3.0) * 3.0,
	)
	var dist := _bandit.global_position.distance_to(exact_pos)
	var noise := clampf(dist / 20.0, 0.0, 1.0) * 1.5
	if noise > 0.01:
		snapped_pos.x += randf_range(-noise, noise)
		snapped_pos.z += randf_range(-noise, noise)
	return snapped_pos


# ── Terrain locomotion integration ──────────────────────────────────────────

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
