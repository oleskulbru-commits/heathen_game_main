extends SceneTree
## Quick diagnostic: list clips and bones in the new player_locomotion.glb

func _init() -> void:
	print("=== Inspect player_locomotion.glb ===\n")

	var scene: PackedScene = load("res://assets/animations/player_animations/player_locomotion/player_locomotion.glb")
	if scene == null:
		printerr("ERROR: Cannot load GLB")
		quit(); return

	var inst := scene.instantiate()

	# Print node tree
	print("--- Node tree ---")
	_print_tree(inst, 0)

	# Skeleton bones
	var skel := _find_skeleton(inst)
	if skel:
		print("\n--- Skeleton bones (", skel.get_bone_count(), ") ---")
		for i in skel.get_bone_count():
			var parent_idx := skel.get_bone_parent(i)
			var parent_name := skel.get_bone_name(parent_idx) if parent_idx >= 0 else "(none)"
			print("  [", i, "] ", skel.get_bone_name(i), "  parent=", parent_name)
			if i < 3:
				print("    rest.origin: ", skel.get_bone_rest(i).origin)
				print("    rest.basis: ", skel.get_bone_rest(i).basis)

	# Animation clips
	var player := _find_animation_player(inst)
	if player:
		print("\n--- Animation clips ---")
		for clip_name in player.get_animation_list():
			var anim: Animation = player.get_animation(clip_name)
			print("  '", clip_name, "'  duration=", snapped(anim.length, 0.001), "s  tracks=", anim.get_track_count(), "  loop=", anim.loop_mode)
			# Show first 3 track paths
			for t in mini(anim.get_track_count(), 5):
				var ttype := anim.track_get_type(t)
				var type_name := "POS" if ttype == Animation.TYPE_POSITION_3D else ("ROT" if ttype == Animation.TYPE_ROTATION_3D else ("SCL" if ttype == Animation.TYPE_SCALE_3D else str(ttype)))
				print("    track[", t, "]: ", anim.track_get_path(t), "  ", type_name, "  keys=", anim.track_get_key_count(t))
				# Show first key value for position tracks
				if ttype == Animation.TYPE_POSITION_3D and anim.track_get_key_count(t) > 0:
					print("      key[0] val=", anim.track_get_key_value(t, 0))
					if anim.track_get_key_count(t) > 1:
						var last_k := anim.track_get_key_count(t) - 1
						print("      key[", last_k, "] val=", anim.track_get_key_value(t, last_k))

	inst.free()
	print("\n=== Done ===")
	quit()


func _print_tree(node: Node, depth: int) -> void:
	var indent := ""
	for i in depth:
		indent += "  "
	var info := indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		var n := node as Node3D
		if n.scale != Vector3.ONE:
			info += " scale=" + str(n.scale)
		if n.rotation != Vector3.ZERO:
			info += " rot_deg=" + str(snapped(n.rotation_degrees, Vector3(0.01, 0.01, 0.01)))
	print(info)
	if depth < 4:
		for child in node.get_children():
			_print_tree(child, depth + 1)

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null
