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
}

@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree") as AnimationTree


func _ready() -> void:
	_ensure_optional_libraries()


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