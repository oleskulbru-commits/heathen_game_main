@tool
extends SceneTree

func _init() -> void:
	var lib: AnimationLibrary = load("res://assets/animations/animation_libraries/player_combat.res")
	if not lib:
		print("ERROR: Could not load player_combat.res")
		quit()
		return
	print("=== Animation Library: player_combat.res ===")
	print("Animation names: ", lib.get_animation_list())
	for anim_name in lib.get_animation_list():
		var name_str := str(anim_name)
		if not "dodge" in name_str.to_lower():
			continue
		var anim: Animation = lib.get_animation(anim_name)
		print("\n--- %s (length=%.3f, tracks=%d) ---" % [anim_name, anim.length, anim.get_track_count()])
		for t in anim.get_track_count():
			var path := anim.track_get_path(t)
			var type := anim.track_get_type(t)
			var key_count := anim.track_get_key_count(t)
			var type_name := ""
			match type:
				Animation.TYPE_POSITION_3D: type_name = "POSITION_3D"
				Animation.TYPE_ROTATION_3D: type_name = "ROTATION_3D"
				Animation.TYPE_SCALE_3D: type_name = "SCALE_3D"
				Animation.TYPE_BLEND_SHAPE: type_name = "BLEND_SHAPE"
				Animation.TYPE_VALUE: type_name = "VALUE"
				Animation.TYPE_METHOD: type_name = "METHOD"
				Animation.TYPE_BEZIER: type_name = "BEZIER"
				Animation.TYPE_AUDIO: type_name = "AUDIO"
				Animation.TYPE_ANIMATION: type_name = "ANIMATION"
				_: type_name = "UNKNOWN(%d)" % type
			# Only show first track or root-ish tracks in detail
			var path_str := str(path)
			if key_count <= 30 or "root" in path_str.to_lower() or path_str == "." or path_str == "%GeneralSkeleton:" or ":" not in path_str:
				print("  Track %d: %s [%s] keys=%d" % [t, path, type_name, key_count])
				if type == Animation.TYPE_POSITION_3D and key_count <= 40:
					for k in key_count:
						var time := anim.track_get_key_time(t, k)
						var val = anim.track_get_key_value(t, k)
						print("    key %d: t=%.4f pos=%s" % [k, time, str(val)])
			else:
				print("  Track %d: %s [%s] keys=%d (skipped)" % [t, path, type_name, key_count])
	quit()
