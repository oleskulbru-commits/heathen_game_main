extends CharacterBody3D
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
@export var gravity_scale: float = 1.35
@export var blend_lerp_speed: float = 8.0

var _anim_tree: AnimationTree
var _anim_player: AnimationPlayer
var _was_moving := false
var _current_loco_blend: float = 0.0
var _using_activity := false

const ACTIVITY_LIB_NAME := &"Activity"


func _ready() -> void:
	for child in get_children():
		if child is Node3D:
			var tree := child.find_child("AnimationTree") as AnimationTree
			if tree:
				_anim_tree = tree
				break
			var player := child.find_child("AnimationPlayer") as AnimationPlayer
			if player:
				_anim_player = player
	if not _anim_player:
		for child in get_children():
			if child is Node3D:
				_anim_player = child.find_child("AnimationPlayer") as AnimationPlayer
				if _anim_player:
					break
	if _anim_tree:
		_anim_tree.active = true
	_setup_activity()


func _setup_activity() -> void:
	if activity_library.is_empty() or activity_animation.is_empty():
		return
	if not _anim_player:
		return
	var lib_path := activity_library
	if not lib_path.begins_with("res://"):
		lib_path = "res://scenes/xbots/" + lib_path
	var lib := load(lib_path) as AnimationLibrary
	if not lib:
		push_warning("Villager: Cannot load activity library '%s'" % lib_path)
		return
	if _anim_player.has_animation_library(ACTIVITY_LIB_NAME):
		_anim_player.remove_animation_library(ACTIVITY_LIB_NAME)
	_anim_player.add_animation_library(ACTIVITY_LIB_NAME, lib)
	# Disable the state machine and play directly via AnimationPlayer
	if _anim_tree:
		_anim_tree.active = false
	var full_name := StringName(str(ACTIVITY_LIB_NAME) + "/" + activity_animation)
	if _anim_player.has_animation(full_name):
		_anim_player.play(full_name)
		# Loop the animation
		var anim := _anim_player.get_animation(full_name)
		if anim:
			anim.loop_mode = Animation.LOOP_LINEAR
		_using_activity = true
	else:
		push_warning("Villager: Animation '%s' not found in library" % activity_animation)
		if _anim_tree:
			_anim_tree.active = true


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta
	velocity.x = 0.0
	velocity.z = 0.0
	if not _using_activity:
		_update_animation(false, delta)
	move_and_slide()


func _update_animation(is_moving: bool, delta: float) -> void:
	if not _anim_tree:
		return
	_anim_tree.set("parameters/conditions/is_moving", is_moving)
	_anim_tree.set("parameters/conditions/is_stopping", _was_moving and not is_moving)
	var target := 1.0 if is_moving else 0.0
	_current_loco_blend = move_toward(_current_loco_blend, target, blend_lerp_speed * delta)
	_anim_tree.set("parameters/Locomotion/blend_position", _current_loco_blend)
	_was_moving = is_moving
