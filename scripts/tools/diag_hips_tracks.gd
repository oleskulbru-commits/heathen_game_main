extends SceneTree
## Diagnostic: dump hips position track values from locomotion FBX
## and check what happens when playing the jog animation

func _init() -> void:
	print("=== Hips Track and Full Root Track Dump ===\n")

	# ── Dump ALL root + hips keys from jog_forward clip ──────────────────
	var loco_scene: PackedScene = load("res://assets/animations/player_animations/player_locomotion/player_locomotion.fbx")
	var loco_inst := loco_scene.instantiate()
	var player := _find_animation_player(loco_inst)

	if player:
		var anim: Animation = player.get_animation("Armature|Jog Forward")
		if anim:
			print("--- Armature|Jog Forward (", anim.length, "s, ", anim.get_track_count(), " tracks) ---")
			for t in anim.get_track_count():
				var path := str(anim.track_get_path(t))
				var bone := _extract_bone(path)
				if bone != "root" and bone != "hips":
					continue
				var ttype := anim.track_get_type(t)
				var type_name := "POSITION" if ttype == Animation.TYPE_POSITION_3D else ("ROTATION" if ttype == Animation.TYPE_ROTATION_3D else ("SCALE" if ttype == Animation.TYPE_SCALE_3D else str(ttype)))
				print("\n  Track[", t, "]: ", path, "  type=", type_name, "  keys=", anim.track_get_key_count(t))
				for k in anim.track_get_key_count(t):
					var time := anim.track_get_key_time(t, k)
					var val = anim.track_get_key_value(t, k)
					print("    key[", k, "] t=", snapped(time, 0.001), "  val=", val)

		# Also check Medium Run
		anim = player.get_animation("Armature|Medium Run")
		if anim:
			print("\n--- Armature|Medium Run (", anim.length, "s, ", anim.get_track_count(), " tracks) ---")
			for t in anim.get_track_count():
				var path := str(anim.track_get_path(t))
				var bone := _extract_bone(path)
				if bone != "root" and bone != "hips":
					continue
				var ttype := anim.track_get_type(t)
				var type_name := "POSITION" if ttype == Animation.TYPE_POSITION_3D else ("ROTATION" if ttype == Animation.TYPE_ROTATION_3D else str(ttype))
				print("\n  Track[", t, "]: ", path, "  type=", type_name, "  keys=", anim.track_get_key_count(t))
				for k in anim.track_get_key_count(t):
					var time := anim.track_get_key_time(t, k)
					var val = anim.track_get_key_value(t, k)
					print("    key[", k, "] t=", snapped(time, 0.001), "  val=", val)

	loco_inst.free()

	# ── Check from saved library too ─────────────────────────────────────
	print("\n--- player_movement.res: jog_forward hips track ---")
	var lib: AnimationLibrary = load("res://scenes/xbots/player_movement.res")
	if lib:
		var jog: Animation = lib.get_animation("jog_forward")
		if jog:
			for t in jog.get_track_count():
				var path := str(jog.track_get_path(t))
				var bone := _extract_bone(path)
				if bone != "hips":
					continue
				var ttype := jog.track_get_type(t)
				if ttype != Animation.TYPE_POSITION_3D:
					continue
				print("  hips position track: ", jog.track_get_key_count(t), " keys")
				for k in mini(jog.track_get_key_count(t), 10):
					var time := jog.track_get_key_time(t, k)
					var val = jog.track_get_key_value(t, k)
					print("    key[", k, "] t=", snapped(time, 0.001), "  val=", val)

	print("\n=== Done ===")
	quit()


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
