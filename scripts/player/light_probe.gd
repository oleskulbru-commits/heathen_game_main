extends Node
## Samples light intensity at the player's position using OmniLight3D proximity
## and directional light exposure.  Emits a 0-1 visibility value each tick.
##
## Attach as a child of the player CharacterBody3D.

signal visibility_changed(value: float)

const LightSampler := preload("res://scripts/common/light_sampler.gd")

@export var probe_interval: float = 0.1
@export var darkness_threshold: float = 0.15

var _timer: float = 0.0
var _visibility: float = 0.0
var _is_daytime: bool = false
var _cached_omni_lights: Array[OmniLight3D] = []
var _cache_timer: float = 0.0
var _player_rid: RID
const CACHE_INTERVAL := 2.0


func get_visibility() -> float:
	return _visibility


func is_daytime() -> bool:
	return _is_daytime


func is_hidden() -> bool:
	return not _is_daytime and _visibility < darkness_threshold


func _physics_process(delta: float) -> void:
	_timer += delta
	_cache_timer += delta
	if _timer < probe_interval:
		return
	_timer = 0.0

	var player := get_parent() as CharacterBody3D
	if not player:
		return

	if not _player_rid.is_valid():
		_player_rid = player.get_rid()

	var player_pos := player.global_position + Vector3(0.0, 1.0, 0.0)

	_is_daytime = _check_daytime()

	if _is_daytime:
		_visibility = 1.0
		visibility_changed.emit(_visibility)
		return

	if _cached_omni_lights.is_empty() or _cache_timer >= CACHE_INTERVAL:
		_cache_timer = 0.0
		_cached_omni_lights = LightSampler.find_omni_lights(get_tree().root)

	var total_light := 0.0
	var space_state := player.get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if _player_rid.is_valid():
		exclude.append(_player_rid)

	for light in _cached_omni_lights:
		if is_instance_valid(light):
			total_light += LightSampler.sample_omni(light, player_pos, space_state, exclude)

	total_light += _sample_directional_lights(player_pos, space_state)

	_visibility = clampf(total_light, 0.0, 1.0)
	visibility_changed.emit(_visibility)


func _check_daytime() -> bool:
	var cycle := get_tree().root.find_child("DayNightCycle", true, false)
	if not cycle:
		return true
	var t: float = cycle.time_of_day
	return t >= 6.0 and t < 20.0


func _sample_directional_lights(sample_pos: Vector3, space: PhysicsDirectSpaceState3D) -> float:
	var total := 0.0
	var lighting := get_tree().root.find_child("Lighting", true, false)
	if not lighting:
		return 0.0

	for child in lighting.get_children():
		if child is DirectionalLight3D and child.visible and child.light_energy > 0.05:
			var dir_light := child as DirectionalLight3D
			var light_dir := -dir_light.global_transform.basis.z.normalized()
			var sky_pos := sample_pos - light_dir * 50.0
			var query := PhysicsRayQueryParameters3D.create(sky_pos, sample_pos)
			query.collision_mask = 1
			var result := space.intersect_ray(query)
			if not result:
				total += child.light_energy * 0.08
	return total
