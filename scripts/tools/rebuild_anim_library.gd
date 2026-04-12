extends SceneTree
## Headless-compatible: rebuilds the player animation libraries from the
## imported player GLBs. Bone names already match the shared xbot/ybot rigs,
## so only the skeleton track prefix is normalised to "Armature/Skeleton3D".
##
## Run:
##   Godot --headless --path <project> --script res://scripts/tools/rebuild_anim_library.gd

const Helpers := preload("res://scripts/tools/anim_build_helpers.gd")

const OUTPUT_DIR := "res://assets/animations/animation_libraries/"

const SOURCES := {
	"res://assets/animations/player_animations/player_locomotion/player_locomotion.glb": {
		"output": "player_movement.res",
		"rename": {
			"Standing Idle":       "idle",
			"Crouch Idle 01":      "crouch_idle",
			"Jog Forward":         "jog_forward",
			"Medium Run":          "run",
			"Female Walk":         "female_walk",
			"Crouch Walk Back":    "crouch_walk_back",
			"Crouch Walk Forward": "crouch_walk_forward",
			"Crouch Walk Left":    "crouch_walk_left",
			"Crouch Walk Right":   "crouch_walk_right",
			"X Bot":               "tpose",
		},
	},
	"res://assets/animations/player_animations/combat_dodges/combat_dodges.glb": {
		"output": "player_combat.res",
	},
	"res://assets/animations/player_animations/death_animations/death_animations.glb": {
		"output": "player_deaths.res",
	},
	"res://assets/animations/player_animations/gadget_animations/gadget_animations.glb": {
		"output": "player_gadgets.res",
	},
}


func _init() -> void:
	print("=== Rebuild Player Animation Libraries ===\n")

	for glb_path in SOURCES:
		var config: Dictionary = SOURCES[glb_path]
		var out_path := OUTPUT_DIR + str(config.get("output", ""))
		_build_library(glb_path, out_path, config.get("rename", {}))

	print("\n=== All Done ===")
	quit()


func _build_library(glb_path: String, out_path: String, rename_map: Dictionary) -> void:
	print("── ", glb_path, " ──")

	var scene: PackedScene = load(glb_path) as PackedScene
	if scene == null:
		printerr("  ERROR: Cannot load ", glb_path)
		return

	var inst := scene.instantiate()
	var player := Helpers.find_animation_player(inst)
	if player == null:
		printerr("  ERROR: No AnimationPlayer in ", glb_path)
		inst.free()
		return

	var clip_list := player.get_animation_list()
	print("  Found ", clip_list.size(), " clips")

	var lib := AnimationLibrary.new()
	for clip_name in clip_list:
		var src_anim: Animation = player.get_animation(clip_name)
		var lib_name: String = str(rename_map.get(clip_name, Helpers.sanitise_clip_name(clip_name)))
		var new_anim := Helpers.copy_animation(src_anim)
		lib.add_animation(lib_name, new_anim)
		print("    + '", lib_name, "': ", snapped(new_anim.length, 0.001), "s, ", new_anim.get_track_count(), " tracks")

	var err := ResourceSaver.save(lib, out_path)
	if err != OK:
		printerr("  ERROR: Failed to save ", out_path, " (code ", err, ")")
	else:
		print("  SAVED: ", out_path, "  (", lib.get_animation_list().size(), " animations)\n")

	inst.free()
