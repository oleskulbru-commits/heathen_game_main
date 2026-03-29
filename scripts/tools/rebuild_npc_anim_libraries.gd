extends SceneTree
## Headless-compatible: builds NPC AnimationLibrary .res files from GLB packs.
## Each GLB becomes one library.  Copies all animation data unaltered — bone
## names already match the Mixamo skeleton.  Track paths are normalised to
## "Armature/Skeleton3D".
##
## Run:
##   Godot --headless --path <project> --script res://scripts/tools/rebuild_npc_anim_libraries.gd

const OUTPUT_DIR := "res://scenes/xbots/"

## Each entry: { glb source path → output .res filename }
const SOURCES := {
	"res://assets/animations/npc_animations/male_locomotion.glb":
		"npc_male_locomotion.res",
	"res://assets/animations/npc_animations/female_locomotion.glb":
		"npc_female_locomotion.res",
	"res://assets/animations/npc_animations/farming_pack.glb":
		"npc_farming.res",
	"res://assets/animations/npc_animations/gestures_pack.glb":
		"npc_gestures.res",
	"res://assets/animations/npc_animations/pro_axe_animation_pack.glb":
		"npc_axe.res",
	"res://assets/animations/npc_animations/pro_sword_and_shield_pack.glb":
		"npc_sword_shield.res",
}


func _init() -> void:
	print("=== Rebuild NPC Animation Libraries ===\n")

	for glb_path in SOURCES:
		var res_name: String = SOURCES[glb_path]
		var out_path: String = OUTPUT_DIR + res_name
		_build_library(glb_path, out_path)

	print("\n=== All Done ===")
	quit()


func _build_library(glb_path: String, out_path: String) -> void:
	print("── ", glb_path, " ──")

	var scene: PackedScene = load(glb_path) as PackedScene
	if scene == null:
		printerr("  ERROR: Cannot load ", glb_path)
		return
	var inst := scene.instantiate()
	var player := _find_animation_player(inst)
	if player == null:
		printerr("  ERROR: No AnimationPlayer in ", glb_path)
		inst.free()
		return

	var clip_list := player.get_animation_list()
	print("  Found ", clip_list.size(), " clips")

	var lib := AnimationLibrary.new()
	for clip_name in clip_list:
		var src_anim: Animation = player.get_animation(clip_name)
		var lib_name := _sanitise_clip_name(clip_name)
		var new_anim := _copy_animation(src_anim)
		lib.add_animation(lib_name, new_anim)
		print("    + '", lib_name, "': ", snapped(new_anim.length, 0.001), "s, ", new_anim.get_track_count(), " tracks")

	var err := ResourceSaver.save(lib, out_path)
	if err != OK:
		printerr("  ERROR: Failed to save ", out_path, " (code ", err, ")")
	else:
		print("  SAVED: ", out_path, "  (", lib.get_animation_list().size(), " animations)\n")

	inst.free()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _sanitise_clip_name(clip_name: String) -> String:
	## "Crouch Walk Back" → "crouch_walk_back"
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
	var anim := Animation.new()
	anim.length = src.length
	anim.loop_mode = src.loop_mode

	for i in src.get_track_count():
		var path_str := str(src.track_get_path(i))
		var remapped := _normalise_track_path(path_str)
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


func _normalise_track_path(path: String) -> String:
	var colon_pos := path.rfind(":")
	if colon_pos < 0:
		return path
	var prefix := path.substr(0, colon_pos)
	var bone := path.substr(colon_pos + 1)
	if "Skeleton3D" in prefix and not prefix.begins_with("Armature/"):
		prefix = "Armature/Skeleton3D"
	return prefix + ":" + bone
