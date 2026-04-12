extends RefCounted
## Shared light-sampling utilities used by both LightProbe (player visibility)
## and StealthNavGrid (bandit dark-route pathfinding).

const LIGHT_ENERGY_SCALE := 0.15
const OCCLUSION_TOLERANCE := 0.3


static func sample_omni(light: OmniLight3D, sample_pos: Vector3, space: PhysicsDirectSpaceState3D, exclude_rids: Array[RID] = []) -> float:
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
	if not exclude_rids.is_empty():
		query.exclude = exclude_rids

	var result := space.intersect_ray(query)
	if result and result.position.distance_to(light_pos) > OCCLUSION_TOLERANCE:
		return 0.0
	return falloff * light.light_energy * LIGHT_ENERGY_SCALE


static func find_omni_lights(node: Node) -> Array[OmniLight3D]:
	var lights: Array[OmniLight3D] = []
	if node is OmniLight3D:
		lights.append(node)
	for child in node.get_children():
		lights.append_array(find_omni_lights(child))
	return lights
