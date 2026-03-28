extends CharacterBody3D
## Player controller built around root-motion locomotion with Witcher 3-style
## orbit camera.  The camera orbits freely around the player via mouse; WASD
## movement is relative to the camera.  The visual mesh rotates to face the
## movement direction independently of the camera.

# ── Exports ──────────────────────────────────────────────────────────────────
@export var mouse_sensitivity: float = 0.0025
@export var gravity_scale: float = 1.35
@export var rotation_speed: float = 10.0
@export var head_track_speed: float = 4.5
@export var head_max_yaw_deg: float = 70.0
@export var head_max_pitch_deg: float = 25.0
@export var head_idle_weight: float = 0.55
@export var head_move_weight: float = 0.12

# ── Node references ──────────────────────────────────────────────────────────
@onready var camera_pivot: Node3D = $CameraPivot
@onready var visual_root: Node3D = $xbot_root
@onready var anim_tree: AnimationTree = $xbot_root/AnimationTree
@onready var _skeleton: Skeleton3D = $xbot_root/Armature/Skeleton3D

# ── Camera state ─────────────────────────────────────────────────────────────
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.0

# ── Head look state ──────────────────────────────────────────────────────────
var _look_chain: Array = []  # [{idx, yaw_frac, pitch_frac}]
var _head_look_current: Vector2 = Vector2.ZERO  # x = pitch, y = yaw (radians)
var _look_weight: float = 0.0

# ── Player mode ──────────────────────────────────────────────────────────────
enum PlayerMode { TRAVERSAL, STEALTH }
var _mode: PlayerMode = PlayerMode.TRAVERSAL

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_input_map()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	anim_tree.active = true
	_init_look_chain()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw -= event.relative.x * mouse_sensitivity
		_cam_pitch -= event.relative.y * mouse_sensitivity
		_cam_pitch = clampf(_cam_pitch, deg_to_rad(-60.0), deg_to_rad(35.0))
		camera_pivot.rotation = Vector3(_cam_pitch, _cam_yaw, 0.0)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("crouch"):
		_toggle_crouch()

func _physics_process(delta: float) -> void:
	# ── Gravity ──────────────────────────────────────────────────────────
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	# ── Input → world-space move direction (relative to camera) ──────────
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_basis := camera_pivot.global_transform.basis
	var cam_forward := -cam_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := cam_basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var move_dir := (cam_right * input.x + cam_forward * -input.y)
	if move_dir.length_squared() > 1.0:
		move_dir = move_dir.normalized()

	var is_moving := move_dir.length() > 0.1
	var is_sprinting := is_moving and Input.is_action_pressed("sprint")

	# ── Sprint exits stealth ────────────────────────────────────────────
	if is_sprinting and _mode == PlayerMode.STEALTH:
		_set_mode(PlayerMode.TRAVERSAL)

	# ── Update animation state machine ───────────────────────────────────
	_update_animation(is_moving, is_sprinting)

	# ── Rotate visual mesh toward move direction ─────────────────────────
	if is_moving:
		_face_direction(move_dir, delta)

	# ── Apply root motion ────────────────────────────────────────────────
	_apply_root_motion(delta)

	move_and_slide()

# ── Head look-at ─────────────────────────────────────────────────────────────

func _init_look_chain() -> void:
	# Candidates: [bone_names_to_try, yaw_share, pitch_share]
	# Shares are normalised later so missing bones don't break the split.
	var candidates := [
		[["spine.002", "Spine2", "spine_02", "chest"],  0.12, 0.10],
		[["neck",      "Neck",   "neck_01"],              0.33, 0.35],
		[["head",      "Head"],                             0.55, 0.55],
	]
	_look_chain.clear()
	var total_yaw := 0.0
	var total_pitch := 0.0
	for entry in candidates:
		var idx := -1
		for bone_name in entry[0]:
			idx = _skeleton.find_bone(bone_name)
			if idx >= 0:
				break
		if idx >= 0:
			_look_chain.append({"idx": idx, "yaw_frac": entry[1], "pitch_frac": entry[2]})
			total_yaw += entry[1]
			total_pitch += entry[2]
	# Normalise so fractions always sum to 1.0
	if total_yaw > 0.0:
		for e in _look_chain:
			e.yaw_frac /= total_yaw
			e.pitch_frac /= total_pitch

func _process(delta: float) -> void:
	_apply_head_look(delta)

func _apply_head_look(delta: float) -> void:
	if _look_chain.is_empty():
		return

	# ── Target angles: offset between camera look dir and character facing ──
	var cam_fwd := -camera_pivot.global_transform.basis.z
	var char_fwd := -visual_root.global_transform.basis.z

	# Horizontal yaw – signed angle from character forward to camera forward
	var cam_h := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
	var char_h := Vector3(char_fwd.x, 0.0, char_fwd.z)
	if cam_h.length_squared() < 0.001 or char_h.length_squared() < 0.001:
		return
	cam_h = cam_h.normalized()
	char_h = char_h.normalized()
	var target_yaw := cam_h.signed_angle_to(char_h, Vector3.UP)

	# Vertical pitch – how far the camera looks above/below horizontal
	var target_pitch := -asin(clampf(cam_fwd.y, -1.0, 1.0))

	# Clamp to comfortable range
	var max_yaw := deg_to_rad(head_max_yaw_deg)
	var max_pitch := deg_to_rad(head_max_pitch_deg)
	target_yaw = clampf(target_yaw, -max_yaw, max_yaw)
	target_pitch = clampf(target_pitch, -max_pitch, max_pitch)

	# ── Movement dampening – body already faces move dir, reduce tracking ──
	var input_len := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back").length()
	var target_w := lerpf(head_idle_weight, head_move_weight,
		clampf(input_len * 2.0, 0.0, 1.0))
	_look_weight = lerpf(_look_weight, target_w, clampf(3.0 * delta, 0.0, 1.0))

	# Weighted targets
	var w_yaw := target_yaw * _look_weight
	var w_pitch := target_pitch * _look_weight

	# ── Smooth interpolation ────────────────────────────────────────────────
	var t := clampf(head_track_speed * delta, 0.0, 1.0)
	_head_look_current.y = lerp_angle(_head_look_current.y, w_yaw, t)
	_head_look_current.x = lerp_angle(_head_look_current.x, w_pitch, t)

	# ── Distribute across the bone chain ────────────────────────────────────
	# Step 1: Clear all overrides so we read the clean animated poses.
	for entry in _look_chain:
		_skeleton.set_bone_global_pose_override(entry.idx, Transform3D.IDENTITY, 0.0, true)

	# Step 2: Read clean animated poses, then apply our rotation on top.
	for entry in _look_chain:
		var bone_yaw: float = _head_look_current.y * entry.yaw_frac
		var bone_pitch: float = _head_look_current.x * entry.pitch_frac
		var bone_pose := _skeleton.get_bone_global_pose(entry.idx)
		# Pre-multiply so rotation happens in skeleton (≈ character) space,
		# independent of each bone's rest orientation.
		var extra := Basis(Vector3.UP, bone_yaw) * Basis(Vector3.RIGHT, bone_pitch)
		var modified := bone_pose
		modified.basis = extra * bone_pose.basis
		_skeleton.set_bone_global_pose_override(entry.idx, modified, 1.0, true)

# ── Animation ────────────────────────────────────────────────────────────────

var _was_moving := false

func _update_animation(is_moving: bool, is_sprinting: bool) -> void:
	anim_tree.set("parameters/conditions/is_moving", is_moving)
	anim_tree.set("parameters/conditions/is_stopping", _was_moving and not is_moving)

	if _mode == PlayerMode.STEALTH:
		anim_tree.set("parameters/CrouchLocomotion/blend_position",
			1.0 if is_moving else 0.0)
	else:
		if is_moving:
			var blend := 2.0 if is_sprinting else 1.0
			anim_tree.set("parameters/Locomotion/blend_position", blend)

	_was_moving = is_moving

# ── Mode switching ───────────────────────────────────────────────────────────

func _toggle_crouch() -> void:
	if _mode == PlayerMode.TRAVERSAL:
		_set_mode(PlayerMode.STEALTH)
	else:
		_set_mode(PlayerMode.TRAVERSAL)

func _set_mode(new_mode: PlayerMode) -> void:
	if new_mode == _mode:
		return
	_mode = new_mode
	var playback: AnimationNodeStateMachinePlayback = anim_tree["parameters/playback"]
	var current := playback.get_current_node()
	if _mode == PlayerMode.STEALTH:
		if current == &"Locomotion":
			playback.travel("CrouchLocomotion")
		else:
			playback.travel("CrouchIdle")
	else:
		if current == &"CrouchLocomotion":
			playback.travel("Locomotion")
		else:
			playback.travel("Idle")

# ── Facing ───────────────────────────────────────────────────────────────────

func _face_direction(dir: Vector3, delta: float) -> void:
	var target_angle := atan2(dir.x, dir.z)
	var current_angle := visual_root.rotation.y
	visual_root.rotation.y = lerp_angle(current_angle, target_angle, clampf(rotation_speed * delta, 0.0, 1.0))

# ── Root Motion ──────────────────────────────────────────────────────────────

func _apply_root_motion(delta: float) -> void:
	var root_motion := anim_tree.get_root_motion_position()
	# Transform from the visual mesh's local space → world space
	root_motion = visual_root.global_transform.basis * root_motion
	# Root motion is a per-frame displacement; convert to velocity
	if delta > 0.0:
		velocity.x = root_motion.x / delta
		velocity.z = root_motion.z / delta

# ── Input Map ────────────────────────────────────────────────────────────────

func _ensure_input_map() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("crouch", KEY_CTRL)
	_bind_key("ui_cancel", KEY_ESCAPE)

func _bind_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for evt in InputMap.action_get_events(action):
		if evt is InputEventKey:
			InputMap.action_erase_event(action, evt)
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.keycode = keycode
	InputMap.action_add_event(action, key)
