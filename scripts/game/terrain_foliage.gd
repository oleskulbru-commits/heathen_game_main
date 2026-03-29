extends Node3D
## Procedural foliage streaming system for Terrain3D.
## Attach as a child of the Game node (sibling of Terrain3D and Player).
## Streams MultiMesh vegetation chunks based on player proximity,
## using slope angle and elevation to pick Norwegian fjord-appropriate plants.
## Uses crossed-quad billboards with procedural shaders for each plant type.

# ── Shader preloads ──────────────────────────────────────────────────────────
const SHADER_GRASS      := preload("res://assets/shaders/foliage/grass.gdshader")
const SHADER_WILDFLOWER := preload("res://assets/shaders/foliage/wildflower.gdshader")
const SHADER_BUSH       := preload("res://assets/shaders/foliage/bush.gdshader")
const SHADER_HEATHER    := preload("res://assets/shaders/foliage/heather.gdshader")
const SHADER_FERN       := preload("res://assets/shaders/foliage/fern.gdshader")
const SHADER_MOSS       := preload("res://assets/shaders/foliage/moss_lichen.gdshader")
const SHADER_REED       := preload("res://assets/shaders/foliage/reed.gdshader")

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
	_player = get_parent().get_node_or_null("Player")
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


# ── Vegetation definitions ───────────────────────────────────────────────────

func _build_veg_types() -> void:
	_veg_types.clear()

	# --- FLAT TO GENTLE SLOPES (grasslands, meadows) ---
	_veg_types.append(_veg("TallGrass", _crossed_quad(0.15, 0.5),
		_shader_mat(SHADER_GRASS, {}),
		Vector2(0.7, 1.3), 0.0, 25.0, 0.0, 0.7, 1.5))
	_veg_types.append(_veg("Wildflower", _crossed_quad(0.2, 0.3),
		_shader_mat(SHADER_WILDFLOWER, {}),
		Vector2(0.6, 1.0), 0.0, 20.0, 0.05, 0.6, 0.6))
	_veg_types.append(_veg("Blueberry", _crossed_quad(0.35, 0.3),
		_shader_mat(SHADER_BUSH, {
			"leaf_color_a": Color(0.12, 0.28, 0.12),
			"leaf_color_b": Color(0.20, 0.36, 0.15),
			"berry_color": Color(0.18, 0.08, 0.32),
			"berry_amount": 0.25,
		}),
		Vector2(0.7, 1.2), 0.0, 30.0, 0.15, 0.75, 0.5))

	# --- MODERATE SLOPES (shrubland) ---
	_veg_types.append(_veg("Heather", _crossed_quad(0.5, 0.2),
		_shader_mat(SHADER_HEATHER, {}),
		Vector2(0.8, 1.5), 10.0, 45.0, 0.3, 0.95, 0.8))
	_veg_types.append(_veg("Juniper", _crossed_quad(0.5, 0.45),
		_shader_mat(SHADER_BUSH, {
			"leaf_color_a": Color(0.10, 0.25, 0.15),
			"leaf_color_b": Color(0.15, 0.32, 0.18),
			"berry_color": Color(0.12, 0.15, 0.30),
			"berry_amount": 0.1,
		}),
		Vector2(0.8, 1.6), 5.0, 40.0, 0.1, 0.8, 0.7))
	_veg_types.append(_veg("Fern", _crossed_quad(0.4, 0.35),
		_shader_mat(SHADER_FERN, {}),
		Vector2(0.6, 1.2), 5.0, 35.0, 0.05, 0.65, 0.9))
	_veg_types.append(_veg("Bracken", _crossed_quad(0.5, 0.4),
		_shader_mat(SHADER_FERN, {
			"frond_color_a": Color(0.28, 0.38, 0.08),
			"frond_color_b": Color(0.35, 0.42, 0.12),
		}),
		Vector2(0.7, 1.3), 15.0, 50.0, 0.1, 0.7, 0.4))

	# --- STEEP SLOPES (rocky, sparse) ---
	_veg_types.append(_veg("Moss", _flat_quad(0.6),
		_shader_mat(SHADER_MOSS, {"lichen_blend": 0.0}),
		Vector2(0.8, 1.5), 25.0, 60.0, 0.0, 1.0, 0.6))
	_veg_types.append(_veg("Lichen", _flat_quad(0.4),
		_shader_mat(SHADER_MOSS, {"lichen_blend": 1.0}),
		Vector2(0.6, 1.4), 30.0, 65.0, 0.2, 1.0, 0.3))

	# --- LOW ELEVATION / WATERSIDE ---
	_veg_types.append(_veg("Reed", _crossed_quad(0.12, 0.8),
		_shader_mat(SHADER_REED, {}),
		Vector2(0.8, 1.3), 0.0, 15.0, 0.0, 0.2, 0.9))


func _veg(veg_name: String, mesh: Mesh, mat: ShaderMaterial,
		scale_range: Vector2,
		slope_min_deg: float, slope_max_deg: float,
		elev_min_pct: float, elev_max_pct: float,
		density_mult: float) -> Dictionary:
	mesh.surface_set_material(0, mat)
	return {
		"name": veg_name,
		"mesh": mesh,
		"scale_range": scale_range,
		"slope_min": deg_to_rad(slope_min_deg),
		"slope_max": deg_to_rad(slope_max_deg),
		"elev_min": elev_min_pct,
		"elev_max": elev_max_pct,
		"density_mult": density_mult,
	}


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
			var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s))
			transforms.append(Transform3D(basis, pt["pos"]))

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


# ── Mesh factories ───────────────────────────────────────────────────────────

## Two perpendicular quads forming an X shape — standard foliage billboard.
func _crossed_quad(half_w: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Quad A: facing +Z / -Z
	_add_quad(st, Vector3(-half_w, 0, 0), Vector3(half_w, 0, 0),
				  Vector3(half_w, height, 0), Vector3(-half_w, height, 0))
	# Quad B: facing +X / -X (rotated 90°)
	_add_quad(st, Vector3(0, 0, -half_w), Vector3(0, 0, half_w),
				  Vector3(0, height, half_w), Vector3(0, height, -half_w))
	st.generate_normals()
	return st.commit()


## Flat horizontal quad for ground-hugging vegetation (moss, lichen).
func _flat_quad(half_size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Slight Y offset (0.02) to avoid z-fighting with terrain
	_add_quad(st, Vector3(-half_size, 0.02, -half_size),
				  Vector3( half_size, 0.02, -half_size),
				  Vector3( half_size, 0.02,  half_size),
				  Vector3(-half_size, 0.02,  half_size))
	st.generate_normals()
	return st.commit()


func _add_quad(st: SurfaceTool, bl: Vector3, br: Vector3, tr: Vector3, tl: Vector3) -> void:
	# Triangle 1: bl, br, tr
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	# Triangle 2: bl, tr, tl
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)


## Create a ShaderMaterial from a shader with optional parameter overrides.
func _shader_mat(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	return mat


# ── Utility ──────────────────────────────────────────────────────────────────

func _find_child_by_class(parent_node: Node, cls: String) -> Node:
	for child in parent_node.get_children():
		if child.get_class() == cls or child.is_class(cls):
			return child
	return null
