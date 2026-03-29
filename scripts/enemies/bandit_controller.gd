extends CharacterBody3D
## Basic bandit controller.  Uses the ybot_root skin with the same animation
## library and AnimationTree state machine as the player.  Movement is driven
## by AI (NavigationAgent3D) instead of player input.

@export var move_speed: float = 3.5
@export var rotation_speed: float = 10.0
@export var gravity_scale: float = 1.35
@export var blend_lerp_speed: float = 8.0

@onready var visual_root: Node3D = $ybot_root
@onready var anim_tree: AnimationTree = $ybot_root/AnimationTree
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var _was_moving := false
var _current_loco_blend: float = 0.0

func _ready() -> void:
	anim_tree.active = true
	nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	var is_moving := false
	if not nav_agent.is_navigation_finished():
		var next_pos := nav_agent.get_next_path_position()
		var dir := (next_pos - global_position)
		dir.y = 0.0
		if dir.length() > 0.1:
			dir = dir.normalized()
			is_moving = true
			_face_direction(dir, delta)
			velocity.x = dir.x * move_speed
			velocity.z = dir.z * move_speed
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	_update_animation(is_moving, delta)

	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(velocity)
	else:
		_on_velocity_computed(velocity)

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity.x = safe_velocity.x
	velocity.z = safe_velocity.z
	move_and_slide()

func set_target(pos: Vector3) -> void:
	nav_agent.target_position = pos

func _face_direction(dir: Vector3, delta: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	var current_angle := visual_root.rotation.y
	visual_root.rotation.y = lerp_angle(current_angle, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))

func _update_animation(is_moving: bool, delta: float) -> void:
	anim_tree.set("parameters/conditions/is_moving", is_moving)
	anim_tree.set("parameters/conditions/is_stopping", _was_moving and not is_moving)

	var target := 1.0 if is_moving else 0.0
	_current_loco_blend = move_toward(_current_loco_blend, target, blend_lerp_speed * delta)
	anim_tree.set("parameters/Locomotion/blend_position", _current_loco_blend)

	_was_moving = is_moving
