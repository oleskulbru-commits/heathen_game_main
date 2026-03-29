extends SceneTree
## Generates placeholder asset scenes for 1350s Norwegian hamlet level design.
## Each asset is a StaticBody3D with primitive meshes and CollisionShape3D.
##
## Run:
##   Godot --headless --path <project> --script res://scripts/tools/generate_placeholder_assets.gd

const OUT_DIR := "res://assets/level/placeholders/"


func _init() -> void:
	print("=== Generating Placeholder Assets ===\n")
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# -- Natural --
	_make_pine_tree()
	_make_birch_tree()
	_make_rock_small()
	_make_rock_large()
	_make_boulder()
	_make_cliff_face()
	_make_grass_patch()
	_make_bush()
	_make_log()
	_make_fjord_edge()

	# -- Structures --
	_make_longhouse()
	_make_stabbur()
	_make_animal_pen()
	_make_chicken_coop()
	_make_dock()
	_make_boat()
	_make_well()
	_make_woodpile()
	_make_hay_bale()
	_make_grave_marker()

	# -- Details --
	_make_barrel()
	_make_crate()
	_make_rope_coil()
	_make_torch()
	_make_cart()
	_make_plow()

	print("\n=== All Done ===")
	quit()


# === NATURAL ===

func _make_pine_tree() -> void:
	var root := StaticBody3D.new()
	root.name = "PineTree"
	var trunk := _cylinder_mesh(0.15, 6.0, Color(0.35, 0.22, 0.1))
	trunk.position.y = 3.0
	root.add_child(trunk); trunk.owner = root
	for i in 3:
		var h := 2.5 - i * 0.3
		var r := 1.8 - i * 0.5
		var cone := _cylinder_mesh(r, h, Color(0.12, 0.28, 0.1))
		cone.position.y = 4.5 + i * 1.8
		root.add_child(cone); cone.owner = root
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 1.8; shape.height = 10.0
	col.shape = shape; col.position.y = 5.0
	root.add_child(col); col.owner = root
	_save(root, "pine_tree")

func _make_birch_tree() -> void:
	var root := StaticBody3D.new()
	root.name = "BirchTree"
	var trunk := _cylinder_mesh(0.1, 5.0, Color(0.9, 0.88, 0.82))
	trunk.position.y = 2.5
	root.add_child(trunk); trunk.owner = root
	var canopy := _sphere_mesh(1.8, Color(0.45, 0.55, 0.2))
	canopy.position.y = 6.0
	root.add_child(canopy); canopy.owner = root
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 1.0; shape.height = 8.0
	col.shape = shape; col.position.y = 4.0
	root.add_child(col); col.owner = root
	_save(root, "birch_tree")

func _make_rock_small() -> void:
	var root := StaticBody3D.new()
	root.name = "RockSmall"
	var mesh := _box_mesh(Vector3(0.5, 0.35, 0.4), Color(0.45, 0.43, 0.4))
	mesh.position.y = 0.175
	root.add_child(mesh); mesh.owner = root
	_add_box_col(root, Vector3(0.5, 0.35, 0.4), Vector3(0, 0.175, 0))
	_save(root, "rock_small")

func _make_rock_large() -> void:
	var root := StaticBody3D.new()
	root.name = "RockLarge"
	var mesh := _box_mesh(Vector3(1.8, 1.0, 1.5), Color(0.4, 0.38, 0.35))
	mesh.position.y = 0.5
	root.add_child(mesh); mesh.owner = root
	_add_box_col(root, Vector3(1.8, 1.0, 1.5), Vector3(0, 0.5, 0))
	_save(root, "rock_large")

func _make_boulder() -> void:
	var root := StaticBody3D.new()
	root.name = "Boulder"
	var mesh := _sphere_mesh(1.2, Color(0.38, 0.36, 0.33))
	mesh.position.y = 0.9
	root.add_child(mesh); mesh.owner = root
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.2
	col.shape = shape; col.position.y = 0.9
	root.add_child(col); col.owner = root
	_save(root, "boulder")

func _make_cliff_face() -> void:
	var root := StaticBody3D.new()
	root.name = "CliffFace"
	var mesh := _box_mesh(Vector3(8.0, 6.0, 1.5), Color(0.35, 0.33, 0.3))
	mesh.position.y = 3.0
	root.add_child(mesh); mesh.owner = root
	_add_box_col(root, Vector3(8.0, 6.0, 1.5), Vector3(0, 3.0, 0))
	_save(root, "cliff_face")

func _make_grass_patch() -> void:
	var root := StaticBody3D.new()
	root.name = "GrassPatch"
	var mesh := _box_mesh(Vector3(2.0, 0.05, 2.0), Color(0.3, 0.45, 0.15))
	mesh.position.y = 0.025
	root.add_child(mesh); mesh.owner = root
	_add_box_col(root, Vector3(2.0, 0.05, 2.0), Vector3(0, 0.025, 0))
	_save(root, "grass_patch")

func _make_bush() -> void:
	var root := StaticBody3D.new()
	root.name = "Bush"
	var mesh := _sphere_mesh(0.6, Color(0.2, 0.35, 0.12))
	mesh.position.y = 0.5
	root.add_child(mesh); mesh.owner = root
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.6
	col.shape = shape; col.position.y = 0.5
	root.add_child(col); col.owner = root
	_save(root, "bush")

func _make_log() -> void:
	var root := StaticBody3D.new()
	root.name = "Log"
	var mesh := _cylinder_mesh(0.2, 3.0, Color(0.35, 0.22, 0.1))
	mesh.position.y = 0.2; mesh.rotation_degrees.z = 90.0
	root.add_child(mesh); mesh.owner = root
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.2; shape.height = 3.0
	col.shape = shape; col.position.y = 0.2; col.rotation_degrees.z = 90.0
	root.add_child(col); col.owner = root
	_save(root, "log")

func _make_fjord_edge() -> void:
	var root := StaticBody3D.new()
	root.name = "FjordEdge"
	var water := _box_mesh(Vector3(6.0, 0.1, 4.0), Color(0.15, 0.25, 0.35))
	water.position.y = -0.05
	root.add_child(water); water.owner = root
	var shore := _box_mesh(Vector3(6.0, 0.3, 1.0), Color(0.4, 0.38, 0.35))
	shore.position.y = 0.15; shore.position.z = -2.5
	root.add_child(shore); shore.owner = root
	_add_box_col(root, Vector3(6.0, 0.3, 5.0), Vector3.ZERO)
	_save(root, "fjord_edge")


# === STRUCTURES ===

func _make_longhouse() -> void:
	var root := StaticBody3D.new()
	root.name = "Longhouse"
	var body := _box_mesh(Vector3(12.0, 3.0, 5.0), Color(0.3, 0.2, 0.12))
	body.position.y = 1.5
	root.add_child(body); body.owner = root
	var roof := _box_mesh(Vector3(13.0, 0.4, 6.0), Color(0.25, 0.38, 0.15))
	roof.position.y = 3.2
	root.add_child(roof); roof.owner = root
	_add_box_col(root, Vector3(12.0, 3.4, 5.0), Vector3(0, 1.7, 0))
	_save(root, "longhouse")

func _make_stabbur() -> void:
	var root := StaticBody3D.new()
	root.name = "Stabbur"
	for x in [-0.8, 0.8]:
		for z in [-0.6, 0.6]:
			var post := _cylinder_mesh(0.08, 0.8, Color(0.3, 0.2, 0.1))
			post.position = Vector3(x, 0.4, z)
			root.add_child(post); post.owner = root
	var body := _box_mesh(Vector3(2.0, 1.8, 1.6), Color(0.35, 0.22, 0.12))
	body.position.y = 1.7
	root.add_child(body); body.owner = root
	var roof := _box_mesh(Vector3(2.4, 0.25, 2.0), Color(0.25, 0.18, 0.1))
	roof.position.y = 2.75
	root.add_child(roof); roof.owner = root
	_add_box_col(root, Vector3(2.0, 3.0, 1.6), Vector3(0, 1.5, 0))
	_save(root, "stabbur")

func _make_animal_pen() -> void:
	var root := StaticBody3D.new()
	root.name = "AnimalPen"
	var fc := Color(0.35, 0.22, 0.1)
	var back := _box_mesh(Vector3(4.0, 1.0, 0.1), fc)
	back.position = Vector3(0, 0.5, -2.0)
	root.add_child(back); back.owner = root
	var left := _box_mesh(Vector3(0.1, 1.0, 4.0), fc)
	left.position = Vector3(-2.0, 0.5, 0)
	root.add_child(left); left.owner = root
	var right := _box_mesh(Vector3(0.1, 1.0, 4.0), fc)
	right.position = Vector3(2.0, 0.5, 0)
	root.add_child(right); right.owner = root
	var front_l := _box_mesh(Vector3(1.5, 1.0, 0.1), fc)
	front_l.position = Vector3(-1.25, 0.5, 2.0)
	root.add_child(front_l); front_l.owner = root
	for d: Array in [
		[Vector3(4.0, 1.0, 0.1), Vector3(0, 0.5, -2.0)],
		[Vector3(0.1, 1.0, 4.0), Vector3(-2.0, 0.5, 0)],
		[Vector3(0.1, 1.0, 4.0), Vector3(2.0, 0.5, 0)],
		[Vector3(1.5, 1.0, 0.1), Vector3(-1.25, 0.5, 2.0)],
	]:
		_add_box_col(root, d[0], d[1])
	_save(root, "animal_pen")

func _make_chicken_coop() -> void:
	var root := StaticBody3D.new()
	root.name = "ChickenCoop"
	var body := _box_mesh(Vector3(1.2, 0.8, 0.9), Color(0.35, 0.22, 0.12))
	body.position.y = 0.4
	root.add_child(body); body.owner = root
	var roof := _box_mesh(Vector3(1.4, 0.15, 1.1), Color(0.28, 0.18, 0.1))
	roof.position.y = 0.88
	root.add_child(roof); roof.owner = root
	_add_box_col(root, Vector3(1.2, 0.95, 0.9), Vector3(0, 0.475, 0))
	_save(root, "chicken_coop")

func _make_dock() -> void:
	var root := StaticBody3D.new()
	root.name = "Dock"
	var deck := _box_mesh(Vector3(6.0, 0.15, 2.0), Color(0.3, 0.2, 0.1))
	deck.position.y = 0.8
	root.add_child(deck); deck.owner = root
	for x in [-2.5, 0.0, 2.5]:
		for z in [-0.7, 0.7]:
			var post := _cylinder_mesh(0.1, 1.0, Color(0.25, 0.17, 0.08))
			post.position = Vector3(x, 0.4, z)
			root.add_child(post); post.owner = root
	_add_box_col(root, Vector3(6.0, 0.15, 2.0), Vector3(0, 0.8, 0))
	_save(root, "dock")

func _make_boat() -> void:
	var root := StaticBody3D.new()
	root.name = "Boat"
	var hull := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.5; capsule.height = 3.0
	hull.mesh = capsule
	hull.material_override = _mat(Color(0.3, 0.2, 0.1))
	hull.position.y = 0.3; hull.rotation_degrees.z = 90.0
	root.add_child(hull); hull.owner = root
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5; shape.height = 3.0
	col.shape = shape; col.position.y = 0.3; col.rotation_degrees.z = 90.0
	root.add_child(col); col.owner = root
	_save(root, "boat")

func _make_well() -> void:
	var root := StaticBody3D.new()
	root.name = "Well"
	var ring := _cylinder_mesh(0.6, 0.8, Color(0.4, 0.38, 0.35))
	ring.position.y = 0.4
	root.add_child(ring); ring.owner = root
	for x in [-0.4, 0.4]:
		var post := _cylinder_mesh(0.05, 1.5, Color(0.3, 0.2, 0.1))
		post.position = Vector3(x, 1.55, 0)
		root.add_child(post); post.owner = root
	var bar := _cylinder_mesh(0.04, 1.0, Color(0.3, 0.2, 0.1))
	bar.position.y = 2.3; bar.rotation_degrees.z = 90.0
	root.add_child(bar); bar.owner = root
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.6; shape.height = 0.8
	col.shape = shape; col.position.y = 0.4
	root.add_child(col); col.owner = root
	_save(root, "well")

func _make_woodpile() -> void:
	var root := StaticBody3D.new()
	root.name = "Woodpile"
	var mesh := _box_mesh(Vector3(1.5, 0.8, 0.6), Color(0.35, 0.22, 0.1))
	mesh.position.y = 0.4
	root.add_child(mesh); mesh.owner = root
	_add_box_col(root, Vector3(1.5, 0.8, 0.6), Vector3(0, 0.4, 0))
	_save(root, "woodpile")

func _make_hay_bale() -> void:
	var root := StaticBody3D.new()
	root.name = "HayBale"
	var mesh := _cylinder_mesh(0.45, 0.8, Color(0.7, 0.6, 0.3))
	mesh.position.y = 0.4
	root.add_child(mesh); mesh.owner = root
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45; shape.height = 0.8
	col.shape = shape; col.position.y = 0.4
	root.add_child(col); col.owner = root
	_save(root, "hay_bale")

func _make_grave_marker() -> void:
	var root := StaticBody3D.new()
	root.name = "GraveMarker"
	var grey := Color(0.45, 0.43, 0.4)
	var post := _box_mesh(Vector3(0.08, 0.7, 0.06), grey)
	post.position.y = 0.35
	root.add_child(post); post.owner = root
	var bar := _box_mesh(Vector3(0.35, 0.06, 0.06), grey)
	bar.position.y = 0.55
	root.add_child(bar); bar.owner = root
	_add_box_col(root, Vector3(0.35, 0.7, 0.06), Vector3(0, 0.35, 0))
	_save(root, "grave_marker")


# === DETAILS ===

func _make_barrel() -> void:
	var root := StaticBody3D.new()
	root.name = "Barrel"
	var mesh := _cylinder_mesh(0.3, 0.9, Color(0.35, 0.2, 0.1))
	mesh.position.y = 0.45
	root.add_child(mesh); mesh.owner = root
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.3; shape.height = 0.9
	col.shape = shape; col.position.y = 0.45
	root.add_child(col); col.owner = root
	_save(root, "barrel")

func _make_crate() -> void:
	var root := StaticBody3D.new()
	root.name = "Crate"
	var mesh := _box_mesh(Vector3(0.6, 0.6, 0.6), Color(0.4, 0.28, 0.14))
	mesh.position.y = 0.3
	root.add_child(mesh); mesh.owner = root
	_add_box_col(root, Vector3(0.6, 0.6, 0.6), Vector3(0, 0.3, 0))
	_save(root, "crate")

func _make_rope_coil() -> void:
	var root := StaticBody3D.new()
	root.name = "RopeCoil"
	var mesh := _cylinder_mesh(0.25, 0.15, Color(0.55, 0.45, 0.3))
	mesh.position.y = 0.075
	root.add_child(mesh); mesh.owner = root
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.25; shape.height = 0.15
	col.shape = shape; col.position.y = 0.075
	root.add_child(col); col.owner = root
	_save(root, "rope_coil")

func _make_torch() -> void:
	var root := StaticBody3D.new()
	root.name = "Torch"
	var bracket := _box_mesh(Vector3(0.04, 0.04, 0.2), Color(0.25, 0.2, 0.15))
	bracket.position = Vector3(0, 1.8, -0.1)
	root.add_child(bracket); bracket.owner = root
	var stick := _cylinder_mesh(0.03, 0.5, Color(0.3, 0.2, 0.1))
	stick.position.y = 2.05
	root.add_child(stick); stick.owner = root
	var flame := _sphere_mesh(0.08, Color(0.95, 0.6, 0.1))
	flame.position.y = 2.35
	root.add_child(flame); flame.owner = root
	_add_box_col(root, Vector3(0.1, 0.8, 0.2), Vector3(0, 2.0, 0))
	_save(root, "torch")

func _make_cart() -> void:
	var root := StaticBody3D.new()
	root.name = "Cart"
	var wood := Color(0.35, 0.22, 0.1)
	var bed := _box_mesh(Vector3(2.0, 0.1, 1.0), wood)
	bed.position.y = 0.55
	root.add_child(bed); bed.owner = root
	var lw := _box_mesh(Vector3(2.0, 0.3, 0.06), wood)
	lw.position = Vector3(0, 0.75, -0.47)
	root.add_child(lw); lw.owner = root
	var rw := _box_mesh(Vector3(2.0, 0.3, 0.06), wood)
	rw.position = Vector3(0, 0.75, 0.47)
	root.add_child(rw); rw.owner = root
	for side in [-0.55, 0.55]:
		for xp in [-0.6, 0.6]:
			var wheel := _cylinder_mesh(0.3, 0.06, Color(0.25, 0.17, 0.08))
			wheel.position = Vector3(xp, 0.3, side)
			wheel.rotation_degrees.x = 90.0
			root.add_child(wheel); wheel.owner = root
	var handle := _box_mesh(Vector3(0.06, 0.06, 0.8), wood)
	handle.position = Vector3(1.2, 0.55, 0)
	root.add_child(handle); handle.owner = root
	_add_box_col(root, Vector3(2.0, 0.6, 1.0), Vector3(0, 0.55, 0))
	_save(root, "cart")

func _make_plow() -> void:
	var root := StaticBody3D.new()
	root.name = "Plow"
	var wood := Color(0.35, 0.22, 0.1)
	var iron := Color(0.3, 0.3, 0.32)
	var beam := _box_mesh(Vector3(2.0, 0.08, 0.08), wood)
	beam.position.y = 0.5
	root.add_child(beam); beam.owner = root
	var blade := _box_mesh(Vector3(0.3, 0.4, 0.04), iron)
	blade.position = Vector3(-0.7, 0.2, 0)
	blade.rotation_degrees.z = -20.0
	root.add_child(blade); blade.owner = root
	for z in [-0.15, 0.15]:
		var h := _box_mesh(Vector3(0.04, 0.6, 0.04), wood)
		h.position = Vector3(0.8, 0.8, z)
		h.rotation_degrees.z = 10.0
		root.add_child(h); h.owner = root
	_add_box_col(root, Vector3(2.0, 0.6, 0.3), Vector3(0, 0.5, 0))
	_save(root, "plow")


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

func _sphere_mesh(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius; sm.height = radius * 2.0
	mi.mesh = sm
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
