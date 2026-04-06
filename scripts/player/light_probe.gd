extends Node
## Samples light intensity at the player's position using OmniLight3D proximity
## and directional light exposure.  Emits a 0-1 visibility value each tick.
##
## Attach as a child of the player CharacterBody3D.

signal visibility_changed(value: float)

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
		_cached_omni_lights = _find_omni_lights(get_tree().root)

	var total_light := 0.0
	var space_state := player.get_world_3d().direct_space_state

	for light in _cached_omni_lights:
		if is_instance_valid(light):
			total_light += _sample_omni(light, player_pos, space_state)

	total_light += _sample_directional_lights(player_pos, space_state)

	_visibility = clampf(total_light, 0.0, 1.0)
	visibility_changed.emit(_visibility)


func _check_daytime() -> bool:
	var cycle := get_tree().root.find_child("DayNightCycle", true, false)
	if not cycle:
		return true
	var t: float = cycle.time_of_day
	return t >= 6.0 and t < 20.0


func _sample_omni(light: OmniLight3D, sample_pos: Vector3, space: PhysicsDirectSpaceState3D) -> float:
	if not light.visible:
		return 0.0
	var light_pos := light.global_position
	var dist := sample_pos.distance_to(light_pos)
	var range_val: float = light.omni_range
	if dist >= range_val:
		return 0.0

	var atten_exp: float = light.omni_attenuation
	var falloff := 1.0 - pow(dist / range_val, atten_exp)
	falloff = maxf(falloff, 0.0)

	var query := PhysicsRayQueryParameters3D.create(sample_pos, light_pos)
	query.collision_mask = 1
	query.hit_from_inside = false
	if _player_rid.is_valid():
		query.exclude = [_player_rid]
	var result := space.intersect_ray(query)
	if result and result.position.distance_to(light_pos) > 0.3:
		return 0.0

	return falloff * light.light_energy * 0.15


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


func _find_omni_lights(node: Node) -> Array[OmniLight3D]:
	var lights: Array[OmniLight3D] = []
	if node is OmniLight3D:
		lights.append(node)
	for child in node.get_children():
		lights.append_array(_find_omni_lights(child))
	return lights
