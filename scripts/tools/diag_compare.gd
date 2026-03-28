extends SceneTree
## Diagnostic: compare transforms between FBX and xbot skeletons side by side.
## Instantiate both, play the same animation, and compare bone positions.

var _step := 0
var _fbx_inst: Node
var _xbot_inst: Node

func _init() -> void:
	print("=== Side-by-Side FBX vs xbot Skeleton Comparison ===\n")

	# ── Check FBX Armature transform ─────────────────────────────────────
	var loco_scene: PackedScene = load("res://assets/animations/player_animations/player_locomotion/player_locomotion.fbx")
	_fbx_inst = loco_scene.instantiate()
	root.add_child(_fbx_inst)

	print("--- FBX scene node tree ---")
	_print_tree(_fbx_inst, 0)

	# Find the Armature node in FBX
	var fbx_armature := _find_node_by_type(_fbx_inst, "Node3D")
	if fbx_armature:
		print("\nFBX Armature node: ", fbx_armature.name)
		print("  transform: ", fbx_armature.transform)
		print("  scale: ", fbx_armature.scale)
		print("  rotation: ", fbx_armature.rotation)
		print("  rotation_degrees: ", fbx_armature.rotation_degrees)

	var fbx_skel := _find_skeleton(_fbx_inst)
	if fbx_skel:
		print("\nFBX Skeleton3D: ", fbx_skel.name)
		print("  transform: ", fbx_skel.transform)
		print("  scale: ", fbx_skel.scale)

	# ── Check xbot Armature transform ────────────────────────────────────
	var xbot_scene: PackedScene = load("res://assets/xbots/xbot_root.glb")
	_xbot_inst = xbot_scene.instantiate()
	root.add_child(_xbot_inst)

	print("\n--- xbot GLB scene node tree ---")
	_print_tree(_xbot_inst, 0)

	var xbot_armature := _find_node_by_type(_xbot_inst, "Node3D")
	if xbot_armature:
		print("\nxbot Armature node: ", xbot_armature.name)
		print("  transform: ", xbot_armature.transform)
		print("  scale: ", xbot_armature.scale)
		print("  rotation_degrees: ", xbot_armature.rotation_degrees)

	var xbot_skel := _find_skeleton(_xbot_inst)
	if xbot_skel:
		print("\nxbot Skeleton3D: ", xbot_skel.name)
		print("  transform: ", xbot_skel.transform)

func _process(_delta: float) -> bool:
	_step += 1
	if _step == 1:
		_play_and_compare()
	elif _step >= 5:
		_check_positions()
		_fbx_inst.queue_free()
		_xbot_inst.queue_free()
		quit()
	return false

func _play_and_compare() -> void:
	# Play jog on FBX
	var fbx_player := _find_animation_player(_fbx_inst)
	if fbx_player:
		print("\n--- Playing Armature|Jog Forward on FBX ---")
		print("  Available: ", fbx_player.get_animation_list())
		fbx_player.play("Armature|Jog Forward")
		fbx_player.seek(1.0, true)  # Seek to 1 second

func _check_positions() -> void:
	var fbx_skel := _find_skeleton(_fbx_inst)
	var xbot_skel := _find_skeleton(_xbot_inst)

	if fbx_skel:
		print("\n--- FBX bone positions at t=1s ---")
		var root_idx := fbx_skel.find_bone("root")
		var hips_idx := fbx_skel.find_bone("hips")
		if root_idx >= 0:
			print("  root bone:")
			print("    pose_position: ", fbx_skel.get_bone_pose_position(root_idx))
			print("    global_pose.origin: ", fbx_skel.get_bone_global_pose(root_idx).origin)
			print("    global_rest.origin: ", fbx_skel.get_bone_global_rest(root_idx).origin)
		if hips_idx >= 0:
			print("  hips bone:")
			print("    pose_position: ", fbx_skel.get_bone_pose_position(hips_idx))
			print("    global_pose.origin: ", fbx_skel.get_bone_global_pose(hips_idx).origin)
			print("    global_rest.origin: ", fbx_skel.get_bone_global_rest(hips_idx).origin)

		# Check a foot bone
		for fname in ["foot.R", "foot.L"]:
			var fidx := fbx_skel.find_bone(fname)
			if fidx >= 0:
				print("  ", fname, " global_pose.origin: ", fbx_skel.get_bone_global_pose(fidx).origin)

	if xbot_skel:
		print("\n--- xbot bone rest positions ---")
		var root_idx := xbot_skel.find_bone("root")
		var hips_idx := xbot_skel.find_bone("hips")
		if root_idx >= 0:
			print("  root global_rest.origin: ", xbot_skel.get_bone_global_rest(root_idx).origin)
		if hips_idx >= 0:
			print("  hips global_rest.origin: ", xbot_skel.get_bone_global_rest(hips_idx).origin)

	# Also check what the Armature transform does to world positions
	if fbx_skel:
		var root_idx := fbx_skel.find_bone("root")
		if root_idx >= 0:
			var global_pose_origin := fbx_skel.get_bone_global_pose(root_idx).origin
			var skel_global_transform := fbx_skel.global_transform
			var world_pos := skel_global_transform * global_pose_origin
			print("\n  FBX root WORLD position (skel.global_transform * bone): ", world_pos)

		var hips_idx := fbx_skel.find_bone("hips")
		if hips_idx >= 0:
			var global_pose_origin := fbx_skel.get_bone_global_pose(hips_idx).origin
			var skel_global_transform := fbx_skel.global_transform
			var world_pos := skel_global_transform * global_pose_origin
			print("  FBX hips WORLD position: ", world_pos)


func _print_tree(node: Node, depth: int) -> void:
	var indent := ""
	for i in depth:
		indent += "  "
	var info := indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		var n3d := node as Node3D
		if n3d.scale != Vector3.ONE:
			info += " scale=" + str(n3d.scale)
		if n3d.rotation != Vector3.ZERO:
			info += " rot=" + str(snapped(n3d.rotation_degrees, Vector3(0.01, 0.01, 0.01)))
	print(info)
	if depth < 3:
		for child in node.get_children():
			_print_tree(child, depth + 1)

func _find_node_by_type(node: Node, type_name: String) -> Node3D:
	for child in node.get_children():
		if child is Node3D and child.get_class() == type_name:
			return child as Node3D
		if child is Node3D and child.name == "Armature":
			return child as Node3D
	return null

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
