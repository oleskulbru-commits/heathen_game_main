extends "res://scripts/common/humanoid_controller.gd"
## Villager NPC controller with optional looping activity animation.
## Set `activity_library` and `activity_animation` in the inspector to have the
## NPC play a farming/gesture clip instead of the locomotion idle.
##
## Finds the AnimationTree and AnimationPlayer in the first Node3D child.

@export_enum("Idle", "Working", "Fearful", "Sick", "Guard", "Child") var role: String = "Idle"
## Path to a .res AnimationLibrary (e.g. npc_farming.res, npc_gestures.res).
## Leave empty for default locomotion idle.
@export var activity_library: String = ""
## Animation name inside that library to play on loop (e.g. "dig_and_plant_seeds").
@export var activity_animation: String = ""

var _using_activity := false

const ACTIVITY_LIB_NAME := &"Activity"



func _on_controller_ready() -> void:
	_setup_activity()


func _setup_activity() -> void:
	if activity_library.is_empty() or activity_animation.is_empty():
		return
	if not anim_player:
		return
	var lib_path := activity_library
	if not lib_path.begins_with("res://"):
		lib_path = "res://assets/animations/animation_libraries/" + lib_path
	var lib := load(lib_path) as AnimationLibrary
	if not lib:
		push_warning("Villager: Cannot load activity library '%s'" % lib_path)
		return
	if anim_player.has_animation_library(ACTIVITY_LIB_NAME):
		anim_player.remove_animation_library(ACTIVITY_LIB_NAME)
	anim_player.add_animation_library(ACTIVITY_LIB_NAME, lib)
	# Disable the state machine and play directly via AnimationPlayer
	if anim_tree:
		anim_tree.active = false
	var full_name := StringName(str(ACTIVITY_LIB_NAME) + "/" + activity_animation)
	if anim_player.has_animation(full_name):
		anim_player.play(full_name)
		# Loop the animation
		var anim := anim_player.get_animation(full_name)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		_using_activity = true
	else:
		push_warning("Villager: Animation '%s' not found in library" % activity_animation)
		if anim_tree:
			anim_tree.active = true


func _update_animation_state(is_moving: bool, delta: float) -> void:
	if _using_activity:
		return
	super(is_moving, delta)
