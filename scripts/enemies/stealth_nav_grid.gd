extends RefCounted
## Builds a light-aware AStar3D graph on the XZ plane so bandits can prefer
## dark / shadowed routes when searching for the player.
##
## Usage:
##   var grid := preload("res://scripts/enemies/stealth_nav_grid.gd").new()
##   grid.build(search_center, bandit.get_world_3d(), bandit.get_tree())
##   var path := grid.get_stealth_path(bandit.global_position, target_pos)

const LightSampler := preload("res://scripts/common/light_sampler.gd")

# ── Configuration ────────────────────────────────────────────────────────────
var cell_size: float = 2.0
var grid_radius: float = 30.0
var light_penalty: float = 3.0
var height_sample_max: float = 50.0
var nav_snap_tolerance: float = 1.5

# ── Internal ─────────────────────────────────────────────────────────────────
var _astar := AStar3D.new()
var _grid_width: int = 0
var _grid_origin_x: float = 0.0
var _grid_origin_z: float = 0.0
var _built := false


func build(center: Vector3, world: World3D, scene_tree: SceneTree) -> void:
	_astar.clear()
	_built = false

	var space := world.direct_space_state
	if not space:
		return

	var map: RID = world.navigation_map

	var lights := LightSampler.find_omni_lights(scene_tree.root)

	# Grid dimensions
	var half := grid_radius
	_grid_origin_x = center.x - half
	_grid_origin_z = center.z - half
	_grid_width = int(ceil(grid_radius * 2.0 / cell_size)) + 1
	var total_cells := _grid_width * _grid_width
	_astar.reserve_space(total_cells)

	# ── Pass 1: add walkable points ─────────────────────────────────────
	for zi in _grid_width:
		for xi in _grid_width:
			var wx := _grid_origin_x + xi * cell_size
			var wz := _grid_origin_z + zi * cell_size
			var ray_origin := Vector3(wx, center.y + height_sample_max, wz)

			# Raycast down to find ground
			var ray_query := PhysicsRayQueryParameters3D.create(
				ray_origin,
				Vector3(wx, center.y - height_sample_max, wz)
			)
			ray_query.collision_mask = 1
			var hit := space.intersect_ray(ray_query)
			var ground_pos: Vector3
			if hit:
				ground_pos = hit.position
			else:
				ground_pos = Vector3(wx, center.y, wz)

			# Verify it's on the nav mesh
			var nav_pos := NavigationServer3D.map_get_closest_point(map, ground_pos)
			if nav_pos.distance_to(ground_pos) > nav_snap_tolerance:
				continue

			# Sample light level
			var total_light := 0.0
			for light in lights:
				if is_instance_valid(light):
					total_light += LightSampler.sample_omni(light, nav_pos, space)

			var weight := 1.0 + total_light * light_penalty
			var point_id := zi * _grid_width + xi
			_astar.add_point(point_id, nav_pos, weight)

	# ── Pass 2: connect neighbours (8-directional) ──────────────────────
	for zi in _grid_width:
		for xi in _grid_width:
			var point_id := zi * _grid_width + xi
			if not _astar.has_point(point_id):
				continue
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dz == 0:
						continue
					var nx := xi + dx
					var nz := zi + dz
					if nx < 0 or nx >= _grid_width or nz < 0 or nz >= _grid_width:
						continue
					var neighbor_id := nz * _grid_width + nx
					if _astar.has_point(neighbor_id):
						if not _astar.are_points_connected(point_id, neighbor_id):
							_astar.connect_points(point_id, neighbor_id)

	_built = _astar.get_point_count() > 0


func get_stealth_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not _built or _astar.get_point_count() < 2:
		return PackedVector3Array()

	var from_id := _astar.get_closest_point(from)
	var to_id := _astar.get_closest_point(to)

	if from_id == to_id:
		return PackedVector3Array([to])

	return _astar.get_point_path(from_id, to_id, true)


func is_valid() -> bool:
	return _built



