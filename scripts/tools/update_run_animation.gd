@tool
extends EditorScript
## Rebuilds the PlayerMovement AnimationLibrary from the player_locomotion GLB.
## Copies all animation data UNALTERED.  Bone names already match the xbot
## skeleton so no remapping is needed.
##
## Run from the Godot Script Editor:  File ▸ Run  (or the ▶ toolbar button).

const LIBRARY_PATH := "res://scenes/xbots/player_movement.res"
const ROOT_TRACK   := "Armature/Skeleton3D:root"

const GLB_SOURCE := "res://assets/animations/player_animations/player_locomotion/player_locomotion.glb"

# GLB clip name  →  library animation name
const CLIP_RENAME := {
	"Standing Idle":         "idle",
	"Crouch Idle 01":        "crouch_idle",
	"Jog Forward":           "jog_forward",
	"Medium Run":            "run",
	"Female Walk":           "female_walk",
	"Crouch Walk Back":      "crouch_walk_back",
	"Crouch Walk Forward":   "crouch_walk_forward",
	"Crouch Walk Left":      "crouch_walk_left",
	"Crouch Walk Right":     "crouch_walk_right",
	"X Bot":                 "tpose",
}


func _run() -> void:
	print("=== Rebuild PlayerMovement Library ===")

	var scene: PackedScene = load(GLB_SOURCE) as PackedScene
	if scene == null:
		printerr("ERROR: Cannot load ", GLB_SOURCE)
		return
	var inst := scene.instantiate()
	var player := _find_animation_player(inst)
	if player == null:
		printerr("ERROR: No AnimationPlayer in ", GLB_SOURCE)
		inst.queue_free(); return

	print("Loaded: ", GLB_SOURCE)
	for clip_name in player.get_animation_list():
		var a: Animation = player.get_animation(clip_name)
		print("  clip: '", clip_name, "'  duration=", snapped(a.length, 0.001), "s  tracks=", a.get_track_count())

	# --- Build the new library ------------------------------------------------
	var lib := AnimationLibrary.new()
	for clip_name in player.get_animation_list():
		var src_anim: Animation = player.get_animation(clip_name)
		var lib_name: String = CLIP_RENAME.get(clip_name, _sanitise_clip_name(clip_name))
		var new_anim := _copy_animation(src_anim)
		lib.add_animation(lib_name, new_anim)

		var root_idx := new_anim.find_track(NodePath(ROOT_TRACK), Animation.TYPE_POSITION_3D)
		var root_info := "  (has root motion track)" if root_idx >= 0 else "  (NO root motion track)"
		print("Added '", lib_name, "': ", snapped(new_anim.length, 0.001), "s, ", new_anim.get_track_count(), " tracks", root_info)

	# --- Save -----------------------------------------------------------------
	var err := ResourceSaver.save(lib, LIBRARY_PATH)
	if err != OK:
		printerr("ERROR: Failed to save library: ", err)
	else:
		print("\nSUCCESS: Saved ", LIBRARY_PATH)
		print("Animations: ", lib.get_animation_list())

	inst.queue_free()
	print("=== Done ===")


# --- Helpers ------------------------------------------------------------------

func _sanitise_clip_name(clip_name: String) -> String:
	return clip_name.strip_edges().to_lower().replace(" ", "_")


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _copy_animation(src: Animation) -> Animation:
	## Verbatim copy — normalises skeleton path prefix only.
	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = src.loop_mode

	for i in src.get_track_count():
		var path_str := str(src.track_get_path(i))
		var remapped := _normalise_track_path(path_str)
		var idx := anim.add_track(src.track_get_type(i))
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


func _normalise_track_path(path: String) -> String:
	var colon_pos := path.rfind(":")
	if colon_pos < 0:
		return path
	var prefix := path.substr(0, colon_pos)
	var bone := path.substr(colon_pos + 1)
	if "Skeleton3D" in prefix and not prefix.begins_with("Armature/"):
		prefix = "Armature/Skeleton3D"
	return prefix + ":" + bone
