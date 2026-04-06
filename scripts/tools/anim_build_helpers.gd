## Shared helpers for headless animation library build scripts.
## Usage:  const Helpers := preload("res://scripts/tools/anim_build_helpers.gd")

static func find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_animation_player(child)
		if found != null:
			return found
	return null


static func sanitise_clip_name(clip_name: String) -> String:
	## "Crouch Walk Back" → "crouch_walk_back"
	return clip_name.strip_edges().to_lower().replace(" ", "_")


static func copy_animation(src: Animation) -> Animation:
	## Verbatim copy — normalises skeleton path prefix only.
	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = src.loop_mode

	for i in src.get_track_count():
		var path_str := str(src.track_get_path(i))
		var remapped := normalise_track_path(path_str)
		var track_type := src.track_get_type(i)

		var idx := anim.add_track(track_type)
		anim.track_set_path(idx, NodePath(remapped))
		anim.track_set_interpolation_type(idx, src.track_get_interpolation_type(i))
		for k in src.track_get_key_count(i):
			anim.track_insert_key(
				idx,
				src.track_get_key_time(i, k),
				src.track_get_key_value(i, k),
				src.track_get_key_transition(i, k)
			)
	return anim


static func normalise_track_path(path: String) -> String:
	## Ensure skeleton tracks use "Armature/Skeleton3D:bone" format.
	var colon_pos := path.rfind(":")
	if colon_pos < 0:
		return path
	var prefix := path.substr(0, colon_pos)
	var bone := path.substr(colon_pos + 1)
	if "Skeleton3D" in prefix and not prefix.begins_with("Armature/"):
		prefix = "Armature/Skeleton3D"
	return prefix + ":" + bone
