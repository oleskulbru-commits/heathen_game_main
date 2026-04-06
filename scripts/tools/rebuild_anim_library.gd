extends SceneTree
## Headless-compatible: rebuilds PlayerMovement AnimationLibrary from the
## player_locomotion GLB.  Copies all animation data UNALTERED.  Bone names
## already match the xbot skeleton so no remapping is needed — only the track
## path prefix is normalised to "Armature/Skeleton3D".
##
## Run:  Godot --headless --path <project> --script res://scripts/tools/rebuild_anim_library.gd

const Helpers := preload("res://scripts/tools/anim_build_helpers.gd")

const LIBRARY_PATH := "res://scenes/xbots/player_movement.res"

const GLB_SOURCE := "res://assets/animations/player_animations/player_locomotion/player_locomotion.glb"

# Optional rename:  GLB clip name  →  library animation name.
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


func _init() -> void:
	print("=== Rebuild PlayerMovement Library ===")

	var scene: PackedScene = load(GLB_SOURCE) as PackedScene
	if scene == null:
		printerr("ERROR: Cannot load ", GLB_SOURCE)
		quit(); return
	var inst := scene.instantiate()
	var player := Helpers.find_animation_player(inst)
	if player == null:
		printerr("ERROR: No AnimationPlayer in ", GLB_SOURCE)
		inst.free(); quit(); return

	print("Loaded: ", GLB_SOURCE)
	for clip_name in player.get_animation_list():
		var a: Animation = player.get_animation(clip_name)
		print("  clip: '", clip_name, "'  duration=", snapped(a.length, 0.001), "s  tracks=", a.get_track_count())

	var lib := AnimationLibrary.new()
	for clip_name in player.get_animation_list():
		var src_anim: Animation = player.get_animation(clip_name)
		var lib_name: String = CLIP_RENAME.get(clip_name, Helpers.sanitise_clip_name(clip_name))
		var new_anim := Helpers.copy_animation(src_anim)
		lib.add_animation(lib_name, new_anim)
		print("Added '", lib_name, "': ", snapped(new_anim.length, 0.001), "s, ", new_anim.get_track_count(), " tracks")

	var err := ResourceSaver.save(lib, LIBRARY_PATH)
	if err != OK:
		printerr("ERROR: Failed to save library: ", err)
	else:
		print("\nSUCCESS: Saved ", LIBRARY_PATH)
		print("Animations (", lib.get_animation_list().size(), "): ", lib.get_animation_list())

	inst.free()
	print("=== Done ===")
	quit()
