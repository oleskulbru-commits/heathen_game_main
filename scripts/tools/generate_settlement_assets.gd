extends SceneTree
## Generates additional placeholder assets needed for the Frafjord settlement.
## Run:
##   Godot --headless --path <project> --script res://scripts/tools/generate_settlement_assets.gd

const OUT_DIR := "res://assets/level/placeholders/"


func _init() -> void:
	print("=== Generating Settlement Assets ===\n")

	_make_cottage()
	_make_barn()
	_make_smithy()
	_make_midden_heap()
	_make_shrine_post()
	_make_burnt_building()
	_make_field_tended()
	_make_field_overgrown()
	_make_path_segment()
	_make_wooden_fence()

	print("\n=== All Done ===")
	quit()


# --- Cottage: smaller farmhouse (6 x 2.5 x 3.5 m) ---
func _make_cottage() -> void:
	var root := StaticBody3D.new()
	root.name = "Cottage"
	var body := _box_mesh(Vector3(6.0, 2.5, 3.5), Color(0.32, 0.2, 0.11))
	body.position.y = 1.25
	root.add_child(body); body.owner = root
	var roof := _box_mesh(Vector3(6.5, 0.3, 4.0), Color(0.22, 0.35, 0.14))
	roof.position.y = 2.65
	root.add_child(roof); roof.owner = root
	_add_box_col(root, Vector3(6.0, 2.8, 3.5), Vector3(0, 1.4, 0))
	_save(root, "cottage")


# --- Barn: storage/animal building (8 x 3 x 4.5 m) ---
func _make_barn() -> void:
	var root := StaticBody3D.new()
	root.name = "Barn"
	var body := _box_mesh(Vector3(8.0, 3.0, 4.5), Color(0.28, 0.17, 0.09))
	body.position.y = 1.5
	root.add_child(body); body.owner = root
	var roof := _box_mesh(Vector3(8.5, 0.35, 5.0), Color(0.2, 0.32, 0.12))
	roof.position.y = 3.18
	root.add_child(roof); roof.owner = root
	# Large door opening (recessed box to hint at entrance)
	var door := _box_mesh(Vector3(1.8, 2.2, 0.15), Color(0.22, 0.14, 0.07))
	door.position = Vector3(0, 1.1, 2.32)
	root.add_child(door); door.owner = root
	_add_box_col(root, Vector3(8.0, 3.35, 4.5), Vector3(0, 1.68, 0))
	_save(root, "barn")


# --- Smithy: small forge (3.5 x 2.5 x 3 m) with chimney ---
func _make_smithy() -> void:
	var root := StaticBody3D.new()
	root.name = "Smithy"
	var body := _box_mesh(Vector3(3.5, 2.5, 3.0), Color(0.3, 0.2, 0.11))
	body.position.y = 1.25
	root.add_child(body); body.owner = root
	var roof := _box_mesh(Vector3(4.0, 0.25, 3.5), Color(0.22, 0.15, 0.08))
	roof.position.y = 2.63
	root.add_child(roof); roof.owner = root
	# Chimney
	var chimney := _box_mesh(Vector3(0.5, 1.5, 0.5), Color(0.3, 0.28, 0.26))
	chimney.position = Vector3(-1.0, 3.25, -0.8)
	root.add_child(chimney); chimney.owner = root
	# Anvil
	var anvil := _box_mesh(Vector3(0.4, 0.4, 0.25), Color(0.25, 0.25, 0.27))
	anvil.position = Vector3(2.5, 0.2, 0)
	root.add_child(anvil); anvil.owner = root
	_add_box_col(root, Vector3(3.5, 2.75, 3.0), Vector3(0, 1.38, 0))
	_save(root, "smithy")


# --- Midden heap: waste mound ---
func _make_midden_heap() -> void:
	var root := StaticBody3D.new()
	root.name = "MiddenHeap"
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.2; sm.height = 0.8
	mi.mesh = sm
	mi.material_override = _mat(Color(0.25, 0.22, 0.18))
	mi.position.y = 0.2; mi.scale = Vector3(1.0, 0.5, 1.0)
	root.add_child(mi); mi.owner = root
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 0.6, 2.4)
	col.shape = shape; col.position.y = 0.3
	root.add_child(col); col.owner = root
	_save(root, "midden_heap")


# --- Shrine post: Norse offering post with horizontal shelf ---
func _make_shrine_post() -> void:
	var root := StaticBody3D.new()
	root.name = "ShrinePost"
	var wood := Color(0.3, 0.2, 0.1)
	# Main vertical post
	var post := _cylinder_mesh(0.08, 2.2, wood)
	post.position.y = 1.1
	root.add_child(post); post.owner = root
	# Crossbar (Christian-Norse syncretism)
	var bar := _box_mesh(Vector3(0.5, 0.06, 0.06), wood)
	bar.position.y = 1.7
	root.add_child(bar); bar.owner = root
	# Small offering shelf at base
	var shelf := _box_mesh(Vector3(0.4, 0.04, 0.25), wood)
	shelf.position.y = 0.6
	root.add_child(shelf); shelf.owner = root
	# Base stone
	var stone := _box_mesh(Vector3(0.5, 0.15, 0.5), Color(0.4, 0.38, 0.35))
	stone.position.y = 0.075
	root.add_child(stone); stone.owner = root
	_add_box_col(root, Vector3(0.5, 2.2, 0.5), Vector3(0, 1.1, 0))
	_save(root, "shrine_post")


# --- Burnt building: charred/collapsed ruin ---
func _make_burnt_building() -> void:
	var root := StaticBody3D.new()
	root.name = "BurntBuilding"
	var charcoal := Color(0.12, 0.1, 0.08)
	# Main collapsed walls
	var wall1 := _box_mesh(Vector3(5.0, 1.5, 0.2), charcoal)
	wall1.position = Vector3(0, 0.75, -1.75)
	root.add_child(wall1); wall1.owner = root
	var wall2 := _box_mesh(Vector3(0.2, 1.2, 3.5), charcoal)
	wall2.position = Vector3(-2.4, 0.6, 0)
	root.add_child(wall2); wall2.owner = root
	# Collapsed section (tilted)
	var fallen := _box_mesh(Vector3(5.0, 0.2, 2.0), charcoal)
	fallen.position = Vector3(0, 0.5, 0.5)
	fallen.rotation_degrees.z = 15.0
	root.add_child(fallen); fallen.owner = root
	# Rubble
	var rubble := _box_mesh(Vector3(3.0, 0.3, 2.5), Color(0.15, 0.13, 0.1))
	rubble.position.y = 0.15
	root.add_child(rubble); rubble.owner = root
	_add_box_col(root, Vector3(5.0, 1.5, 3.5), Vector3(0, 0.75, 0))
	_save(root, "burnt_building")


# --- Cultivated field (tended, with row lines) ---
func _make_field_tended() -> void:
	var root := StaticBody3D.new()
	root.name = "FieldTended"
	# Base earth
	var base := _box_mesh(Vector3(8.0, 0.05, 6.0), Color(0.35, 0.28, 0.18))
	base.position.y = 0.025
	root.add_child(base); base.owner = root
	# Crop rows (thin green strips)
	var green := Color(0.25, 0.38, 0.12)
	for i in 5:
		var row := _box_mesh(Vector3(7.0, 0.12, 0.3), green)
		row.position = Vector3(0, 0.06, -2.0 + i * 1.0)
		root.add_child(row); row.owner = root
	_add_box_col(root, Vector3(8.0, 0.15, 6.0), Vector3(0, 0.075, 0))
	_save(root, "field_tended")


# --- Overgrown field (abandoned, taller weeds) ---
func _make_field_overgrown() -> void:
	var root := StaticBody3D.new()
	root.name = "FieldOvergrown"
	# Base earth
	var base := _box_mesh(Vector3(8.0, 0.05, 6.0), Color(0.32, 0.28, 0.18))
	base.position.y = 0.025
	root.add_child(base); base.owner = root
	# Weedy overgrowth patches
	var weed := Color(0.35, 0.42, 0.2)
	for i in 4:
		for j in 3:
			var patch := _box_mesh(Vector3(1.2, 0.25, 0.8), weed)
			patch.position = Vector3(-2.5 + i * 2.0, 0.13, -1.5 + j * 1.5)
			root.add_child(patch); patch.owner = root
	_add_box_col(root, Vector3(8.0, 0.3, 6.0), Vector3(0, 0.15, 0))
	_save(root, "field_overgrown")


# --- Path segment: worn dirt strip (4 x 0.02 x 1.2 m) ---
func _make_path_segment() -> void:
	var root := StaticBody3D.new()
	root.name = "PathSegment"
	var mesh := _box_mesh(Vector3(4.0, 0.02, 1.2), Color(0.38, 0.3, 0.2))
	mesh.position.y = 0.01
	root.add_child(mesh); mesh.owner = root
	_add_box_col(root, Vector3(4.0, 0.02, 1.2), Vector3(0, 0.01, 0))
	_save(root, "path_segment")


# --- Wooden fence: 3 posts + 2 rails (3 m long, 1 m high) ---
func _make_wooden_fence() -> void:
	var root := StaticBody3D.new()
	root.name = "WoodenFence"
	var wood := Color(0.35, 0.22, 0.1)
	# 3 posts
	for x in [-1.4, 0.0, 1.4]:
		var post := _cylinder_mesh(0.05, 1.0, wood)
		post.position = Vector3(x, 0.5, 0)
		root.add_child(post); post.owner = root
	# 2 horizontal rails
	for y in [0.35, 0.7]:
		var rail := _box_mesh(Vector3(3.0, 0.06, 0.06), wood)
		rail.position.y = y
		root.add_child(rail); rail.owner = root
	_add_box_col(root, Vector3(3.0, 1.0, 0.1), Vector3(0, 0.5, 0))
	_save(root, "wooden_fence")


# === HELPERS ===

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m

func _box_mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	return mi

func _cylinder_mesh(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius; cm.bottom_radius = radius; cm.height = height
	mi.mesh = cm
	mi.material_override = _mat(color)
	return mi

func _add_box_col(parent: Node, size: Vector3, pos: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape; col.position = pos
	parent.add_child(col); col.owner = parent

func _save(root: Node, file_name: String) -> void:
	var scene := PackedScene.new()
	scene.pack(root)
	var path := OUT_DIR + file_name + ".tscn"
	var err := ResourceSaver.save(scene, path)
	if err != OK:
		printerr("  FAIL: ", path, " (code ", err, ")")
	else:
		print("  OK ", path)
	root.free()
