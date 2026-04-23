extends MeshInstance3D
## Pulsing heart icon that renders through walls when the player is in focus
## mode and within 40 metres.  Position is updated manually each frame from
## the skeleton bone pose — more reliable than BoneAttachment3D at runtime.

const MAX_DISTANCE := 40.0
const FADE_START := 35.0
const PULSE_SPEED := 1.2
const PULSE_STRENGTH := 0.12
const BASE_COLOR := Color(0.85, 0.12, 0.1, 1.0)

var _player: Node3D
var _shader_mat: ShaderMaterial
var _standard_mat: StandardMaterial3D
var _skel: Skeleton3D
var _bone_idx: int = -1
var _dbg_frame: int = 0
var _base_scale: Vector3 = Vector3.ONE

func _ready() -> void:
	visible = false
	_shader_mat = material_override as ShaderMaterial
	_standard_mat = material_override as StandardMaterial3D
	_base_scale = scale
	var parent_name := "null"
	if get_parent():
		parent_name = get_parent().name
	print("[HeartInd] _ready  shader_mat=", _shader_mat != null, "  standard_mat=", _standard_mat != null, "  parent=", parent_name)

## Called by bandit_controller after add_child so we know which bone to track.
func setup_bone(skel: Skeleton3D, bone_idx: int) -> void:
	_skel = skel
	_bone_idx = bone_idx
	var bone_name := "INVALID"
	if bone_idx >= 0:
		bone_name = skel.get_bone_name(bone_idx)
	print("[HeartInd] setup_bone: bone_idx=", bone_idx,
		"  name=", bone_name)

func _process(_delta: float) -> void:
	_dbg_frame += 1

	# Manually follow the chest bone in world space
	if _skel and _bone_idx >= 0 and is_instance_valid(_skel):
		global_position = _skel.to_global(_skel.get_bone_global_pose(_bone_idx).origin) + Vector3(0, 0.15, 0)

	if not _player:
		_player = get_tree().get_first_node_in_group("player")
	if not _player:
		visible = false
		if _dbg_frame % 120 == 1:
			print("[HeartInd] no player in 'player' group")
		return

	var focused: bool = _player.is_focused() if _player.has_method("is_focused") else false
	if _dbg_frame % 120 == 1:
		print("[HeartInd] frame=", _dbg_frame, "  focused=", focused,
			"  dist=", snappedf(global_position.distance_to(_player.global_position), 0.1),
			"  pos=", global_position, "  visible=", visible)
	if not focused:
		visible = false
		return

	var dist := global_position.distance_to(_player.global_position)
	if dist > MAX_DISTANCE:
		visible = false
		return

	visible = true
	var alpha := 1.0
	if dist > FADE_START:
		alpha = 1.0 - ((dist - FADE_START) / (MAX_DISTANCE - FADE_START))
	var pulse := 1.0 + PULSE_STRENGTH * sin(Time.get_ticks_msec() * 0.001 * PULSE_SPEED * TAU)
	scale = _base_scale * pulse
	if _shader_mat:
		_shader_mat.set_shader_parameter("alpha_mult", alpha)
	elif _standard_mat:
		var tint := BASE_COLOR
		tint.a = alpha
		_standard_mat.albedo_color = tint
		_standard_mat.emission = tint
