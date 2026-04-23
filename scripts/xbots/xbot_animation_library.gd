extends Node3D
## Root script for the ybot/xbot visual model.
## Exposes animation_player and animation_tree references for controllers.

const Helpers := preload("res://scripts/tools/anim_build_helpers.gd")

const OPTIONAL_LIBRARY_SOURCES := {
	"PlayerCombat": {
		"resource": "res://assets/animations/animation_libraries/player_combat.res",
		"source": "res://assets/animations/player_animations/combat_dodges/combat_dodges.glb",
		"probe": "standing_dodge_forward",
		"aliases": ["PlayerCombat", "player_combat"],
	},
	"PlayerDeaths": {
		"resource": "res://assets/animations/animation_libraries/player_deaths.res",
		"source": "res://assets/animations/player_animations/death_animations/death_animations.glb",
		"probe": "standing_death_forward_01",
		"aliases": ["PlayerDeaths", "player_deaths"],
	},
	"PlayerGadgets": {
		"resource": "res://assets/animations/animation_libraries/player_gadgets.res",
		"source": "res://assets/animations/player_animations/gadget_animations/gadget_animations.glb",
		"probe": "throw_object",
		"aliases": ["PlayerGadgets", "player_gadgets"],
	},
	"PlayerActionAdventure": {
		"resource": "res://assets/animations/animation_libraries/player_action_adventure.res",
		"source": "res://assets/animations/player_animations/action_adventure_animations/action_adventure_animations.glb",
		"aliases": ["PlayerActionAdventure", "player_action_adventure"],
	},
}

@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree") as AnimationTree

## Cached reference to the OneShot's AnimationNodeAnimation for changing the action clip.
var _action_anim_node: AnimationNodeAnimation
var _action_shot_node: AnimationNodeOneShot
var _combat_run_arm_node: AnimationNodeBlend2
var _action_leg_filter_paths: Array[NodePath] = []
var _action_left_arm_filter_paths: Array[NodePath] = []
var _leg_filter_ready: bool = false
var _left_arm_filter_ready: bool = false
var _action_leg_filter_enabled: bool = false
var _action_left_arm_filter_enabled: bool = false
var _combat_run_arm_filter_ready: bool = false


func _ready() -> void:
	_ensure_optional_libraries()
	_cache_oneshot_nodes()
	_build_leg_filter.call_deferred()
	_build_left_arm_filter.call_deferred()
	_build_combat_run_arm_filter.call_deferred()


func _cache_oneshot_nodes() -> void:
	if not animation_tree:
		return
	var blend_tree := animation_tree.tree_root as AnimationNodeBlendTree
	if not blend_tree:
		_cache_combat_filter_nodes()
		return
	if blend_tree.has_node(&"ActionAnim"):
		_action_anim_node = blend_tree.get_node(&"ActionAnim") as AnimationNodeAnimation
	if blend_tree.has_node(&"ActionShot"):
		_action_shot_node = blend_tree.get_node(&"ActionShot") as AnimationNodeOneShot
	_cache_combat_filter_nodes()


## Fire a one-shot action animation.  The state machine keeps running underneath
## so the blend-back is perfectly smooth.
func play_action(anim_name: StringName, fade_in: float = -1.0, fade_out: float = -1.0) -> void:
	if not animation_tree or not _action_anim_node:
		return
	_action_anim_node.animation = anim_name
	_action_anim_node.use_custom_timeline = false
	_action_anim_node.start_offset = 0.0
	if _action_shot_node:
		if fade_in >= 0.0:
			_action_shot_node.fadein_time = fade_in
		if fade_out >= 0.0:
			_action_shot_node.fadeout_time = fade_out
	animation_tree.set("parameters/ActionShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
## Abort the current one-shot, triggering its fade-out back to the state machine.
func abort_action() -> void:
	if not animation_tree:
		return
	animation_tree.set("parameters/ActionShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Returns true while a one-shot action is playing (including its fade-out).
func is_action_playing() -> bool:
	if not animation_tree:
		return false
	return bool(animation_tree.get("parameters/ActionShot/active"))
## Enable or disable the leg filter on the ActionShot node.
## When enabled, leg bones pass through from the StateMachine (locomotion),
## so the player can walk while the upper body plays the attack animation.
func set_action_leg_filter(enabled: bool) -> void:
	if not _action_shot_node or not _leg_filter_ready:
		return
	_action_leg_filter_enabled = enabled
	_set_action_filter_paths(_action_leg_filter_paths, enabled)
	_refresh_action_filter_enabled()


func set_action_left_arm_filter(enabled: bool) -> void:
	if not _action_shot_node or not _left_arm_filter_ready:
		return
	_action_left_arm_filter_enabled = enabled
	_set_action_filter_paths(_action_left_arm_filter_paths, enabled)
	_refresh_action_filter_enabled()


## Build the bone filter on the ActionShot OneShot node.
## Marks leg bones as filtered (pass-through from input 0 / locomotion).
func _build_leg_filter() -> void:
	if not _action_shot_node:
		return
	var skeleton := get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if not skeleton:
		return
	# Candidate names for leg root bones (Mixamo / Blender / custom rigs)
	var leg_root_candidates := [
		["LeftUpLeg", "upper_leg.L", "thigh.L", "left_upper_leg", "mixamorig_LeftUpLeg"],
		["RightUpLeg", "upper_leg.R", "thigh.R", "right_upper_leg", "mixamorig_RightUpLeg"],
	]
	var leg_bone_indices: Array[int] = []
	for candidates in leg_root_candidates:
		for bone_name in candidates:
			var idx := skeleton.find_bone(bone_name)
			if idx >= 0:
				leg_bone_indices.append_array(_collect_bone_descendants(skeleton, idx))
				break
	if leg_bone_indices.is_empty():
		push_warning("[xbot_animation_library] Could not find leg bones for filter.")
		return
	# Build filter path strings: "Armature/Skeleton3D:bone_name"
	# The AnimationNodeOneShot filter uses track-style paths relative to the AnimationTree root node
	var skel_path := str(animation_tree.get_path_to(skeleton))
	_action_leg_filter_paths.clear()
	for idx in leg_bone_indices:
		var bone_name := skeleton.get_bone_name(idx)
		var filter_path := "%s:%s" % [skel_path, bone_name]
		_action_leg_filter_paths.append(NodePath(filter_path))
	_set_action_filter_paths(_action_leg_filter_paths, false)
	_leg_filter_ready = true
	_refresh_action_filter_enabled()


func _build_left_arm_filter() -> void:
	if not _action_shot_node:
		return
	var skeleton := get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if not skeleton:
		return
	var arm_root_candidates := [
		"LeftShoulder", "shoulder.L", "clavicle.L", "left_shoulder", "mixamorig_LeftShoulder",
		"LeftArm", "upper_arm.L", "arm.L", "left_upper_arm", "mixamorig_LeftArm"
	]
	var arm_bone_indices: Array[int] = []
	for bone_name in arm_root_candidates:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			arm_bone_indices = _collect_bone_descendants(skeleton, idx)
			break
	if arm_bone_indices.is_empty():
		push_warning("[xbot_animation_library] Could not find left-arm bones for action filter.")
		return
	var skel_path := str(animation_tree.get_path_to(skeleton))
	_action_left_arm_filter_paths.clear()
	for idx in arm_bone_indices:
		var bone_name := skeleton.get_bone_name(idx)
		var filter_path := "%s:%s" % [skel_path, bone_name]
		_action_left_arm_filter_paths.append(NodePath(filter_path))
	_set_action_filter_paths(_action_left_arm_filter_paths, false)
	_left_arm_filter_ready = true
	_refresh_action_filter_enabled()


func _set_action_filter_paths(paths: Array[NodePath], enabled: bool) -> void:
	if not _action_shot_node:
		return
	for filter_path in paths:
		_action_shot_node.set_filter_path(filter_path, enabled)


func _refresh_action_filter_enabled() -> void:
	if not _action_shot_node:
		return
	_action_shot_node.filter_enabled = _action_leg_filter_enabled or _action_left_arm_filter_enabled


func _cache_combat_filter_nodes() -> void:
	if not animation_tree:
		return
	var state_machine := animation_tree.tree_root as AnimationNodeStateMachine
	if not state_machine or not state_machine.has_node(&"Combat"):
		return
	var combat_tree := state_machine.get_node(&"Combat") as AnimationNodeBlendTree
	if not combat_tree or not combat_tree.has_node(&"RunArmMask"):
		return
	_combat_run_arm_node = combat_tree.get_node(&"RunArmMask") as AnimationNodeBlend2


func _build_combat_run_arm_filter() -> void:
	if not _combat_run_arm_node:
		return
	var skeleton := get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if not skeleton:
		return
	var arm_root_candidates := [
		"RightShoulder", "shoulder.R", "clavicle.R", "right_shoulder", "mixamorig_RightShoulder",
		"RightArm", "upper_arm.R", "arm.R", "right_upper_arm", "mixamorig_RightArm"
	]
	var arm_bone_indices: Array[int] = []
	for bone_name in arm_root_candidates:
		var idx := skeleton.find_bone(bone_name)
		if idx >= 0:
			arm_bone_indices = _collect_bone_descendants(skeleton, idx)
			break
	if arm_bone_indices.is_empty():
		push_warning("[xbot_animation_library] Could not find right-arm bones for combat run mask.")
		return
	var skeleton_path := str(animation_tree.get_path_to(skeleton))
	for idx in arm_bone_indices:
		var bone_name := skeleton.get_bone_name(idx)
		var filter_path := "%s:%s" % [skeleton_path, bone_name]
		_combat_run_arm_node.set_filter_path(NodePath(filter_path), true)
	_combat_run_arm_node.filter_enabled = true
	_combat_run_arm_node.set("blend_amount", 1.0)
	_combat_run_arm_filter_ready = true


func _collect_bone_descendants(skeleton: Skeleton3D, parent_idx: int) -> Array[int]:
	var result: Array[int] = [parent_idx]
	for child_idx in skeleton.get_bone_children(parent_idx):
		result.append_array(_collect_bone_descendants(skeleton, child_idx))
	return result


func _ensure_optional_libraries() -> void:
	if not animation_player:
		return
	for library_name in OPTIONAL_LIBRARY_SOURCES:
		var config: Dictionary = OPTIONAL_LIBRARY_SOURCES[library_name]
		if _optional_library_present(config):
			continue
		var library := _load_optional_library(config)
		if library:
			animation_player.add_animation_library(StringName(library_name), library)


func _optional_library_present(config: Dictionary) -> bool:
	var probe := str(config.get("probe", ""))
	var aliases: Array = config.get("aliases", [])
	for alias_value in aliases:
		var alias := StringName(str(alias_value))
		if animation_player.has_animation_library(alias):
			return true
		if not probe.is_empty() and animation_player.has_animation(StringName(str(alias) + "/" + probe)):
			return true
	return false


func _load_optional_library(config: Dictionary) -> AnimationLibrary:
	var resource_path := str(config.get("resource", ""))
	if not resource_path.is_empty() and ResourceLoader.exists(resource_path):
		var saved_library := load(resource_path) as AnimationLibrary
		if saved_library:
			return saved_library

	var source_path := str(config.get("source", ""))
	if source_path.is_empty() or not ResourceLoader.exists(source_path):
		return null

	var scene := load(source_path) as PackedScene
	if scene == null:
		push_warning("[xbot_animation_library] Could not load animation source %s" % source_path)
		return null

	var instance := scene.instantiate()
	var source_player := Helpers.find_animation_player(instance)
	if source_player == null:
		instance.free()
		push_warning("[xbot_animation_library] No AnimationPlayer found in %s" % source_path)
		return null

	var library := AnimationLibrary.new()
	for clip_name in source_player.get_animation_list():
		var source_anim := source_player.get_animation(clip_name)
		if source_anim == null:
			continue
		library.add_animation(Helpers.sanitise_clip_name(str(clip_name)), Helpers.copy_animation(source_anim))

	instance.free()
	return library