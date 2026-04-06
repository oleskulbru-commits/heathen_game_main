extends MeshInstance3D
## Debug vision cone overlay for bandits.
## Draws a flat wedge representing the FOV and effective sight range.
## Color shifts from green → yellow → orange → red with suspicion.
## Toggle with the exported `enabled` flag or remove the node in production.

@export var segments: int = 24
@export var enabled: bool = true

var _perception: Node
var _visual_root: Node3D
var _imm: ImmediateMesh
var _mat: StandardMaterial3D


func _ready() -> void:
	var bandit := get_parent()
	_perception = bandit.get_node_or_null("BanditPerception")
	_visual_root = bandit.get_node_or_null("ybot_root") as Node3D

	_imm = ImmediateMesh.new()
	mesh = _imm

	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat


func _process(_delta: float) -> void:
	if not enabled or not _perception:
		_imm.clear_surfaces()
		return
	_draw_cone()


func _draw_cone() -> void:
	_imm.clear_surfaces()

	# Compute effective range the same way perception does
	var effective_range: float = _perception.sight_range
	var half_fov := deg_to_rad(_perception.sight_fov_deg * 0.5)

	# Pick color from suspicion
	var s: float = _perception.suspicion
	var tc: float = _perception.threshold_curious
	var ta: float = _perception.threshold_alert
	var tb: float = _perception.threshold_combat
	var color: Color
	if s <= 0.0:
		color = Color(0.2, 0.8, 0.2, 0.12)
	elif s < tc:
		color = Color(0.2, 0.8, 0.2, 0.12).lerp(Color(1.0, 0.9, 0.3, 0.18), s / tc)
	elif s < ta:
		color = Color(1.0, 0.9, 0.3, 0.18).lerp(Color(1.0, 0.5, 0.0, 0.22), (s - tc) / (ta - tc))
	elif s < tb:
		color = Color(1.0, 0.5, 0.0, 0.22).lerp(Color(1.0, 0.1, 0.1, 0.28), (s - ta) / (tb - ta))
	else:
		color = Color(1.0, 0.1, 0.1, 0.28)

	# Determine the model's visual forward direction.
	# The ybot model faces +Z in its rest pose, so transform that axis through
	# the current rotation to get the actual visual forward direction.
	var forward := Vector3.FORWARD
	if _visual_root:
		forward = _visual_root.global_transform.basis * Vector3(0, 0, 1)
	else:
		forward = get_parent().global_transform.basis * Vector3(0, 0, 1)
	forward.y = 0.0
	forward = forward.normalized()

	var yaw := atan2(forward.x, forward.z)

	# Origin at eye height in local space
	var origin := Vector3(0.0, 1.5, 0.0)

	_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := lerpf(-half_fov, half_fov, float(i) / float(segments)) + yaw
		var a1 := lerpf(-half_fov, half_fov, float(i + 1) / float(segments)) + yaw

		var d0 := Vector3(sin(a0), 0.0, cos(a0)) * effective_range
		var d1 := Vector3(sin(a1), 0.0, cos(a1)) * effective_range

		_imm.surface_set_color(color)
		_imm.surface_add_vertex(origin)
		_imm.surface_set_color(color)
		_imm.surface_add_vertex(origin + d0)
		_imm.surface_set_color(color)
		_imm.surface_add_vertex(origin + d1)
	_imm.surface_end()
