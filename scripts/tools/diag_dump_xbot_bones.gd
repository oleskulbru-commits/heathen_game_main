extends SceneTree

func _init() -> void:
	var scene: PackedScene = load("res://assets/xbots/xbot_root.glb")
	if scene == null:
		printerr("ERROR: Cannot load xbot_root.glb")
		quit(); return

	var inst := scene.instantiate()
	var skel := _find_skeleton(inst)
	if skel:
		print("=== xbot_root.glb skeleton (%d bones) ===" % skel.get_bone_count())
		for i in skel.get_bone_count():
			var parent_idx := skel.get_bone_parent(i)
			var parent_name := skel.get_bone_name(parent_idx) if parent_idx >= 0 else "(ROOT)"
			print("[%02d] %-25s  parent=%s" % [i, skel.get_bone_name(i), parent_name])
	else:
		printerr("No Skeleton3D found")
	inst.free()
	quit()

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null
