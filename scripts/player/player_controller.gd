extends CharacterBody3D

signal health_changed(current_health: float)
signal status_changed(message: String)

@export var move_speed: float = 5.0
@export var sprint_multiplier: float = 1.55
@export var acceleration: float = 18.0
@export var gravity_scale: float = 1.35
@export var jump_velocity: float = 5.6
@export var mouse_sensitivity: float = 0.0025
@export var evade_speed: float = 11.5
@export var evade_duration: float = 0.22
@export var evade_cooldown: float = 0.95
@export var attack_range: float = 2.1
@export var attack_angle_degrees: float = 60.0
@export var attack_cooldown: float = 0.55
@export var attack_damage: float = 1.0
@export var omen_range: float = 16.0
@export var omen_duration: float = 3.5
@export var omen_cooldown: float = 5.0
@export var max_health: float = 100.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var visual_root: Node3D = $Visuals

var health: float = 100.0
var _spawn_transform: Transform3D
var _evade_timer: float = 0.0
var _evade_cooldown_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _omen_cooldown_timer: float = 0.0

func _ready() -> void:
	_ensure_input_map()
	health = max_health
	_spawn_transform = global_transform
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health_changed.emit(health)
	status_changed.emit("Reach the torch-lit farm edge without getting pinned down.")

func _ensure_input_map() -> void:
	_set_key_action("move_forward", KEY_W)
	_set_key_action("move_back", KEY_S)
	_set_key_action("move_left", KEY_A)
	_set_key_action("move_right", KEY_D)
	_set_key_action("sprint", KEY_SHIFT)
	_set_key_action("jump", KEY_SPACE)
	_set_key_action("evade", KEY_C)
	_set_key_action("curse_pulse", KEY_Q)
	_set_key_action("interact", KEY_E)
	_set_key_action("ui_cancel", KEY_ESCAPE)
	_ensure_mouse_action("attack", MOUSE_BUTTON_LEFT)

func _set_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	key_event.keycode = keycode
	InputMap.action_add_event(action, key_event)

func _ensure_mouse_action(action: StringName, button_index: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button_index:
			return
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = button_index
	InputMap.action_add_event(action, mouse_event)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-60.0), deg_to_rad(35.0))
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if _evade_cooldown_timer > 0.0:
		_evade_cooldown_timer -= delta
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
	if _omen_cooldown_timer > 0.0:
		_omen_cooldown_timer -= delta

	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	if Input.is_action_just_pressed("curse_pulse"):
		_cast_omen_pulse()
	if Input.is_action_just_pressed("attack"):
		_try_attack()

	if _evade_timer > 0.0:
		_evade_timer -= delta
		move_and_slide()
		_update_visual_facing()
		return

	var input_vector := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var move_direction := (right * input_vector.x) + (forward * input_vector.y)
	if move_direction.length() > 1.0:
		move_direction = move_direction.normalized()

	if Input.is_action_just_pressed("evade"):
		_try_evade(move_direction, forward)

	var target_speed := move_speed
	if Input.is_action_pressed("sprint") and move_direction.length() > 0.1:
		target_speed *= sprint_multiplier
	var target_velocity := move_direction * target_speed
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, acceleration * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	move_and_slide()
	_update_visual_facing()

func _try_evade(move_direction: Vector3, fallback_forward: Vector3) -> void:
	if _evade_cooldown_timer > 0.0:
		return
	var evade_direction := move_direction
	if evade_direction.length() < 0.1:
		evade_direction = fallback_forward
	velocity.x = evade_direction.x * evade_speed
	velocity.z = evade_direction.z * evade_speed
	_evade_timer = evade_duration
	_evade_cooldown_timer = evade_cooldown
	status_changed.emit("You slip sideways across the wet ground.")

func _try_attack() -> void:
	if _attack_cooldown_timer > 0.0:
		return
	_attack_cooldown_timer = attack_cooldown
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best_target: Node3D = null
	var best_distance := attack_range
	for candidate in get_tree().get_nodes_in_group("hostile"):
		var candidate_node := candidate as Node3D
		if candidate_node == null:
			continue
		var offset: Vector3 = candidate_node.global_position - global_position
		var flat_offset := Vector3(offset.x, 0.0, offset.z)
		var distance := flat_offset.length()
		if distance > attack_range or distance <= 0.01:
			continue
		var angle := rad_to_deg(acos(clampf(forward.dot(flat_offset.normalized()), -1.0, 1.0)))
		if angle > attack_angle_degrees:
			continue
		if distance < best_distance:
			best_distance = distance
			best_target = candidate_node
	if best_target != null and best_target.has_method("take_damage"):
		best_target.take_damage(attack_damage)
		status_changed.emit("You lash out to keep the hunter off balance.")
	else:
		status_changed.emit("Your strike cuts only fog and air.")

func _cast_omen_pulse() -> void:
	if _omen_cooldown_timer > 0.0:
		status_changed.emit("The omen still clings to the air. Wait.")
		return
	_omen_cooldown_timer = omen_cooldown
	for revealable in get_tree().get_nodes_in_group("omen_revealable"):
		if revealable is Node3D and revealable.global_position.distance_to(global_position) <= omen_range:
			if revealable.has_method("reveal_from_omen"):
				revealable.reveal_from_omen(omen_duration)
	status_changed.emit("Black breath rolls outward, marking danger through the fog.")

func _update_visual_facing() -> void:
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length() > 0.1:
		visual_root.look_at(global_position + flat_velocity, Vector3.UP)

func take_damage(amount: float, _source_position: Vector3 = Vector3.ZERO) -> void:
	health = maxf(0.0, health - amount)
	health_changed.emit(health)
	status_changed.emit("Pain blooms fast. Another mistake will kill you.")
	if health <= 0.0:
		_respawn()

func set_spawn_transform(spawn_transform: Transform3D) -> void:
	_spawn_transform = spawn_transform

func get_health() -> float:
	return health

func _respawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	health = max_health
	health_changed.emit(health)
	status_changed.emit("You crawl back to shelter. Try the approach again.")