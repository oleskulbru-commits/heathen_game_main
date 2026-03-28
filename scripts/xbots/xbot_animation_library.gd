extends Node3D

const ANIMATION_TREE_PATH := NodePath("AnimationTree")
const ANIMATION_PLAYER_PATH := NodePath("AnimationPlayer")

const PARAM_IS_MOVING := "parameters/conditions/is_moving"
const PARAM_IS_STOPPING := "parameters/conditions/is_stopping"
const PARAM_LOCOMOTION_BLEND := "parameters/Locomotion/blend_position"
const PARAM_CROUCH_LOCOMOTION_BLEND := "parameters/CrouchLocomotion/blend_position"

@export var movement_deadzone: float = 0.08
@export var walk_blend_position: float = 1.0
@export var run_blend_position: float = 2.0

@onready var animation_player: AnimationPlayer = get_node_or_null(ANIMATION_PLAYER_PATH) as AnimationPlayer
@onready var animation_tree: AnimationTree = get_node_or_null(ANIMATION_TREE_PATH) as AnimationTree

var _was_moving: bool = false

func _ready() -> void:
	if animation_tree == null:
		push_warning("xbot_root is missing an AnimationTree child. Locomotion updates will be ignored.")
		return
	animation_tree.active = true
	_set_tree_bool(PARAM_IS_MOVING, false)
	_set_tree_bool(PARAM_IS_STOPPING, false)
	_set_tree_float(PARAM_LOCOMOTION_BLEND, 0.0)
	_set_tree_float(PARAM_CROUCH_LOCOMOTION_BLEND, 0.0)

func set_locomotion_from_input(is_moving: bool, is_sprinting: bool) -> void:
	if animation_tree == null:
		return

	_set_tree_bool(PARAM_IS_MOVING, is_moving)
	_set_tree_bool(PARAM_IS_STOPPING, _was_moving and not is_moving)

	if is_moving:
		_set_tree_float(PARAM_LOCOMOTION_BLEND, run_blend_position if is_sprinting else walk_blend_position)
	else:
		_set_tree_float(PARAM_LOCOMOTION_BLEND, 0.0)

	_was_moving = is_moving

func stop_locomotion() -> void:
	if animation_tree == null:
		return
	_set_tree_bool(PARAM_IS_MOVING, false)
	_set_tree_bool(PARAM_IS_STOPPING, _was_moving)
	_set_tree_float(PARAM_LOCOMOTION_BLEND, 0.0)
	_was_moving = false

func has_player_movement_library() -> bool:
	return animation_player != null and animation_player.has_animation_library(&"PlayerMovement")

func _set_tree_bool(parameter_path: String, value: bool) -> void:
	if animation_tree != null:
		animation_tree.set(parameter_path, value)

func get_root_motion_position() -> Vector3:
	if animation_tree == null:
		return Vector3.ZERO
	return animation_tree.get_root_motion_position()

func get_root_motion_rotation() -> Quaternion:
	if animation_tree == null:
		return Quaternion.IDENTITY
	return animation_tree.get_root_motion_rotation()

func _set_tree_float(parameter_path: String, value: float) -> void:
	if animation_tree != null:
		animation_tree.set(parameter_path, value)