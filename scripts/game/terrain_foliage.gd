extends Node3D
## Procedural foliage streaming system for Terrain3D.
## Attach as a child of the Game node (sibling of Terrain3D and Player).
## Streams MultiMesh vegetation chunks based on player proximity,
## using slope angle and elevation to pick Norwegian fjord-appropriate plants.
## Uses placeholder scenes from assets/level/placeholders/ for mesh + material.

# ── Configuration ────────────────────────────────────────────────────────────
@export var scatter_radius: float = 256.0  ## Distance from player to populate (meters)
@export var chunk_size: float = 64.0       ## World-space size of each chunk
@export var density: float = 0.3           ## Points per square meter (0.1 = sparse, 0.5 = dense)
@export var world_seed: int = 1350         ## Deterministic seed (1350 for the year!)

# ── Node references ──────────────────────────────────────────────────────────
var _terrain: Terrain3D
var _player: Node3D
var _last_chunk := Vector2i(999999, 999999)
var _chunks: Dictionary = {}  # Vector2i -> Array[MultiMeshInstance3D]

# ── Vegetation types ─────────────────────────────────────────────────────────
var _veg_types: Array[Dictionary] = []

# Height range cache
var _height_min: float = 0.0
var _height_max: float = 100.0


func _ready() -> void:
	_terrain = _find_child_by_class(get_parent(), "Terrain3D")
	# Player is under Characters, not World — search from scene root
	_player = get_tree().root.find_child("Player", true, false)
	if not _terrain or not _terrain.data:
		push_warning("TerrainFoliage: No Terrain3D with data found.")
		set_process(false)
		return
	if not _player:
		push_warning("TerrainFoliage: No Player node found.")
		set_process(false)
		return

	var hr: Vector2 = _terrain.data.get_height_range()
	_height_min = hr.x
	_height_max = hr.y

	_build_veg_types()


func _process(_delta: float) -> void:
	var player_chunk := _world_to_chunk(_player.global_position)
	if player_chunk == _last_chunk:
		return
	_last_chunk = player_chunk
	_update_chunks(player_chunk)


# ── Extract mesh + material from a placeholder scene ─────────────────────────

static func _extract_mesh_from_scene(scene_path: String) -> Dictionary:
	var packed := load(scene_path) as PackedScene
	if not packed:
		push_warning("TerrainFoliage: Failed to load scene: " + scene_path)
		return {}
	var instance := packed.instantiate()
	var mesh_instance: MeshInstance3D = null
	# Find the first MeshInstance3D child
	for child in instance.get_children():
		if child is MeshInstance3D:
			mesh_instance = child
			break
	if not mesh_instance or not mesh_instance.mesh:
		instance.queue_free()
		return {}
	var mesh: Mesh = mesh_instance.mesh.duplicate()
	var mat: Material = mesh_instance.material_override
	if mat:
		mat = mat.duplicate()
	elif mesh.get_surface_count() > 0:
		mat = mesh.surface_get_material(0)
		if mat:
			mat = mat.duplicate()
	# Get the mesh's local Y offset from the MeshInstance3D transform
	var y_offset: float = mesh_instance.transform.origin.y
	instance.queue_free()
	return { "mesh": mesh, "material": mat, "y_offset": y_offset }


# ── Vegetation definitions ───────────────────────────────────────────────────

func _build_veg_types() -> void:
	_veg_types.clear()
	var base := "res://assets/level/placeholders/"

	# --- FLAT TO GENTLE SLOPES (grasslands, meadows) ---
	_add_veg("TallGrass", base + "tall_grass_clump.tscn",
		Vector2(0.7, 1.3), 0.0, 25.0, 0.0, 0.7, 1.5)
	_add_veg("GrassPatch", base + "grass_patch.tscn",
		Vector2(0.5, 1.0), 0.0, 20.0, 0.0, 0.6, 1.0)
	_add_veg("Wildflower", base + "wildflower_cluster.tscn",
		Vector2(0.6, 1.0), 0.0, 20.0, 0.05, 0.6, 0.6)
	_add_veg("Blueberry", base + "blueberry_shrub.tscn",
		Vector2(0.7, 1.2), 0.0, 25.0, 0.15, 0.70, 0.4)
	_add_veg("Fern", base + "fern_cluster.tscn",
		Vector2(0.6, 1.2), 0.0, 30.0, 0.05, 0.65, 0.7)
	_add_veg("Bracken", base + "bracken_fern.tscn",
		Vector2(0.7, 1.3), 0.0, 35.0, 0.10, 0.70, 0.4)

	# --- MODERATE SLOPES (shrubland) ---
	_add_veg("Heather", base + "heather_patch.tscn",
		Vector2(0.8, 1.5), 10.0, 40.0, 0.15, 0.90, 0.8)
	_add_veg("Juniper", base + "juniper_bush.tscn",
		Vector2(0.8, 1.6), 5.0, 35.0, 0.10, 0.80, 0.5)
	_add_veg("Bush", base + "bush.tscn",
		Vector2(0.7, 1.4), 5.0, 30.0, 0.10, 0.75, 0.4)

	# --- GROUND COVER (rocky, sparse) ---
	_add_veg("Moss", base + "moss_patch.tscn",
		Vector2(0.8, 1.5), 0.0, 45.0, 0.0, 0.85, 0.6)
	_add_veg("Lichen", base + "lichen_rock.tscn",
		Vector2(0.6, 1.4), 15.0, 55.0, 0.20, 0.95, 0.3)

	# --- LOW ELEVATION / WATERSIDE ---
	_add_veg("Reed", base + "reed_cluster.tscn",
		Vector2(0.8, 1.3), 0.0, 10.0, 0.0, 0.15, 0.9)


func _add_veg(veg_name: String, scene_path: String,
		scale_range: Vector2,
		slope_min_deg: float, slope_max_deg: float,
		elev_min_pct: float, elev_max_pct: float,
		density_mult: float) -> void:
	var data := _extract_mesh_from_scene(scene_path)
	if data.is_empty():
		push_warning("TerrainFoliage: Skipping '%s' — no mesh found in %s" % [veg_name, scene_path])
		return
	if data["material"]:
		data["mesh"].surface_set_material(0, data["material"])
	_veg_types.append({
		"name": veg_name,
		"mesh": data["mesh"],
		"y_offset": data["y_offset"],
		"scale_range": scale_range,
		"slope_min": deg_to_rad(slope_min_deg),
		"slope_max": deg_to_rad(slope_max_deg),
		"elev_min": elev_min_pct,
		"elev_max": elev_max_pct,
		"density_mult": density_mult,
	})


# ── Chunk management ─────────────────────────────────────────────────────────

func _world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / chunk_size), floori(pos.z / chunk_size))


func _update_chunks(center: Vector2i) -> void:
	var radius_chunks := ceili(scatter_radius / chunk_size)
	var needed: Dictionary = {}
	for cx in range(center.x - radius_chunks, center.x + radius_chunks + 1):
		for cz in range(center.y - radius_chunks, center.y + radius_chunks + 1):
			var key := Vector2i(cx, cz)
			var chunk_center := Vector3(
				(cx + 0.5) * chunk_size, 0, (cz + 0.5) * chunk_size)
			var dist := Vector2(
				chunk_center.x - _player.global_position.x,
				chunk_center.z - _player.global_position.z).length()
			if dist <= scatter_radius + chunk_size * 0.71:
				needed[key] = true

	# Remove chunks that are out of range
	var to_remove: Array[Vector2i] = []
	for key: Vector2i in _chunks.keys():
		if not needed.has(key):
			to_remove.append(key)
	for key in to_remove:
		_free_chunk(key)

	# Add new chunks
	for key: Vector2i in needed.keys():
		if not _chunks.has(key):
			_build_chunk(key)


func _build_chunk(key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, world_seed))

	var origin_x := key.x * chunk_size
	var origin_z := key.y * chunk_size
	var step := 1.0 / maxf(density, 0.01)
	var elev_range := _height_max - _height_min
	if elev_range < 0.1:
		elev_range = 1.0

	# Sample terrain points in this chunk
	var points: Array[Dictionary] = []
	var x := origin_x
	while x < origin_x + chunk_size:
		var z := origin_z
		while z < origin_z + chunk_size:
			var px := x + rng.randf_range(-step * 0.4, step * 0.4)
			var pz := z + rng.randf_range(-step * 0.4, step * 0.4)
			var pos := Vector3(px, 0, pz)

			var h: float = _terrain.data.get_height(pos)
			if is_nan(h):
				z += step
				continue
			pos.y = h

			var normal: Vector3 = _terrain.data.get_normal(pos)
			if is_nan(normal.x):
				z += step
				continue

			var slope_rad := acos(clampf(normal.dot(Vector3.UP), 0.0, 1.0))
			var elev_pct := clampf((h - _height_min) / elev_range, 0.0, 1.0)

			points.append({ "pos": pos, "slope": slope_rad, "elev": elev_pct })
			z += step
		x += step

	if points.is_empty():
		_chunks[key] = []
		return

	# For each veg type, collect matching points and build a MultiMesh
	var chunk_nodes: Array[MultiMeshInstance3D] = []
	for vt: Dictionary in _veg_types:
		var transforms: Array[Transform3D] = []
		for pt: Dictionary in points:
			if pt["slope"] < vt["slope_min"] or pt["slope"] > vt["slope_max"]:
				continue
			if pt["elev"] < vt["elev_min"] or pt["elev"] > vt["elev_max"]:
				continue
			if rng.randf() > vt["density_mult"]:
				continue

			var s: float = rng.randf_range(vt["scale_range"].x, vt["scale_range"].y)
			var rot_y: float = rng.randf_range(0, TAU)
			var xform_basis := Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s))
			var pos: Vector3 = pt["pos"]
			pos.y += vt["y_offset"] * s
			transforms.append(Transform3D(xform_basis, pos))

		if transforms.is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = vt["mesh"]
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [vt["name"], key.x, key.y]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		chunk_nodes.append(mmi)

	_chunks[key] = chunk_nodes


func _free_chunk(key: Vector2i) -> void:
	if _chunks.has(key):
		for node: MultiMeshInstance3D in _chunks[key]:
			node.queue_free()
		_chunks.erase(key)


# ── Utility ──────────────────────────────────────────────────────────────────

func _find_child_by_class(parent_node: Node, cls: String) -> Node:
	for child in parent_node.get_children():
		if child.get_class() == cls or child.is_class(cls):
			return child
	return null
