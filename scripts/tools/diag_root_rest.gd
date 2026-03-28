extends SceneTree
## Diagnostic: compare root bone rest poses between FBX and xbot skeletons,
## and dump root position track key values to determine the axis correction needed.

func _init() -> void:
	print("=== Root Bone Rest Pose Diagnostic ===\n")

	# ── xbot GLB skeleton ────────────────────────────────────────────────
	print("--- xbot_root.glb skeleton ---")
	var xbot_scene: PackedScene = load("res://assets/xbots/xbot_root.glb")
	var xbot_inst := xbot_scene.instantiate()
	var xbot_skel := _find_skeleton(xbot_inst)
	if xbot_skel:
		var root_idx := xbot_skel.find_bone("root")
		var hips_idx := xbot_skel.find_bone("hips")
		print("  root bone index: ", root_idx)
		print("  root bone rest: ", xbot_skel.get_bone_rest(root_idx))
		print("  root bone rest.origin: ", xbot_skel.get_bone_rest(root_idx).origin)
		print("  root bone rest.basis: ", xbot_skel.get_bone_rest(root_idx).basis)
		if hips_idx >= 0:
			print("  hips bone index: ", hips_idx)
			print("  hips bone rest: ", xbot_skel.get_bone_rest(hips_idx))
			print("  hips bone rest.origin: ", xbot_skel.get_bone_rest(hips_idx).origin)
			print("  hips parent: ", xbot_skel.get_bone_name(xbot_skel.get_bone_parent(hips_idx)))
	xbot_inst.free()

	# ── FBX (player_locomotion) skeleton ─────────────────────────────────
	print("\n--- player_locomotion.fbx skeleton ---")
	var loco_scene: PackedScene = load("res://assets/animations/player_animations/player_locomotion/player_locomotion.fbx")
	var loco_inst := loco_scene.instantiate()
	var loco_skel := _find_skeleton(loco_inst)
	if loco_skel:
		var root_idx := loco_skel.find_bone("root")
		var hips_idx := loco_skel.find_bone("hips")
		if root_idx < 0:
			# Try other names
			for i in loco_skel.get_bone_count():
				print("  bone[", i, "]: ", loco_skel.get_bone_name(i))
				if i < 5:
					print("    rest: ", loco_skel.get_bone_rest(i))
					print("    rest.origin: ", loco_skel.get_bone_rest(i).origin)
					print("    rest.basis: ", loco_skel.get_bone_rest(i).basis)
					var parent_idx := loco_skel.get_bone_parent(i)
					print("    parent: ", loco_skel.get_bone_name(parent_idx) if parent_idx >= 0 else "(none)")
		else:
			print("  root bone index: ", root_idx)
			print("  root bone rest: ", loco_skel.get_bone_rest(root_idx))
			print("  root bone rest.origin: ", loco_skel.get_bone_rest(root_idx).origin)
			print("  root bone rest.basis: ", loco_skel.get_bone_rest(root_idx).basis)
			if hips_idx >= 0:
				print("  hips bone index: ", hips_idx)
				print("  hips bone rest: ", loco_skel.get_bone_rest(hips_idx))
				print("  hips bone rest.origin: ", loco_skel.get_bone_rest(hips_idx).origin)
				print("  hips parent: ", loco_skel.get_bone_name(loco_skel.get_bone_parent(hips_idx)))

	# ── Dump root position track keys from a locomotion clip ─────────────
	print("\n--- Root position track keys from jog_forward ---")
	var loco_player := _find_animation_player(loco_inst)
	if loco_player:
		for clip_name in loco_player.get_animation_list():
			print("\n  Clip: '", clip_name, "'")
			var anim: Animation = loco_player.get_animation(clip_name)
			for t in anim.get_track_count():
				var path := str(anim.track_get_path(t))
				var bone := _extract_bone(path)
				if bone != "root":
					continue
				var ttype := anim.track_get_type(t)
				var type_name := "POSITION" if ttype == Animation.TYPE_POSITION_3D else ("ROTATION" if ttype == Animation.TYPE_ROTATION_3D else str(ttype))
				print("  Track[", t, "]: ", path, "  type=", type_name, "  keys=", anim.track_get_key_count(t))
				for k in mini(anim.track_get_key_count(t), 5):
					var time := anim.track_get_key_time(t, k)
					var val = anim.track_get_key_value(t, k)
					print("    key[", k, "] t=", snapped(time, 0.001), "  val=", val)
				if anim.track_get_key_count(t) > 5:
					print("    ... (", anim.track_get_key_count(t) - 5, " more keys)")
	loco_inst.free()

	# ── Also dump from Action Idle FBX ───────────────────────────────────
	print("\n--- Action Idle.fbx skeleton check ---")
	var idle_scene: PackedScene = load("res://assets/animations/player_animations/Action Idle.fbx")
	if idle_scene:
		var idle_inst := idle_scene.instantiate()
		var idle_skel := _find_skeleton(idle_inst)
		if idle_skel:
			print("  Bone count: ", idle_skel.get_bone_count())
			for i in mini(idle_skel.get_bone_count(), 5):
				print("  bone[", i, "]: ", idle_skel.get_bone_name(i))
				print("    rest.origin: ", idle_skel.get_bone_rest(i).origin)
				print("    rest.basis: ", idle_skel.get_bone_rest(i).basis)
		var idle_player := _find_animation_player(idle_inst)
		if idle_player:
			for clip_name in idle_player.get_animation_list():
				print("\n  Clip: '", clip_name, "'")
				var anim: Animation = idle_player.get_animation(clip_name)
				for t in anim.get_track_count():
					var path := str(anim.track_get_path(t))
					var bone := _extract_bone(path)
					# Check for root or Hips (Mixamo naming)
					if bone.to_lower() != "hips" and bone.to_lower() != "root" and bone != "mixamorig_Hips":
						continue
					var ttype := anim.track_get_type(t)
					var type_name := "POSITION" if ttype == Animation.TYPE_POSITION_3D else ("ROTATION" if ttype == Animation.TYPE_ROTATION_3D else str(ttype))
					print("  Track[", t, "]: ", path, "  type=", type_name, "  keys=", anim.track_get_key_count(t))
					for k in mini(anim.track_get_key_count(t), 5):
						var time := anim.track_get_key_time(t, k)
						var val = anim.track_get_key_value(t, k)
						print("    key[", k, "] t=", snapped(time, 0.001), "  val=", val)
		idle_inst.free()

	# ── Dump from the saved library too ──────────────────────────────────
	print("\n--- player_movement.res (built library) root track keys ---")
	var lib: AnimationLibrary = load("res://scenes/xbots/player_movement.res")
	if lib:
		for anim_name in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			for t in anim.get_track_count():
				var path := str(anim.track_get_path(t))
				var bone := _extract_bone(path)
				if bone != "root":
					continue
				var ttype := anim.track_get_type(t)
				if ttype != Animation.TYPE_POSITION_3D:
					continue
				print("  '", anim_name, "' root position keys: ", anim.track_get_key_count(t))
				for k in mini(anim.track_get_key_count(t), 5):
					var time := anim.track_get_key_time(t, k)
					var val = anim.track_get_key_value(t, k)
					print("    key[", k, "] t=", snapped(time, 0.001), "  val=", val)

	print("\n=== Done ===")
	quit()


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

func _extract_bone(path: String) -> String:
	var colon := path.rfind(":")
	if colon < 0:
		return ""
	return path.substr(colon + 1)
