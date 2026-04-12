extends Node3D

@export var width: float = 0.9
@export var height: float = 0.1
@export var border_size: float = 0.02
@export var vertical_offset: Vector3 = Vector3(0.0, 0.34, 0.0)
@export var auto_hide_delay: float = 1.5

var _skeleton: Skeleton3D
var _bone_idx: int = -1
var _hide_timer: float = 0.0
var _persistent_visible: bool = false

var _frame_mesh: MeshInstance3D
var _background_mesh: MeshInstance3D
var _fill_mesh: MeshInstance3D


func _ready() -> void:
	_frame_mesh = _make_bar_mesh(width + border_size * 2.0, height + border_size * 2.0, Color(0.02, 0.02, 0.02, 0.95))
	_background_mesh = _make_bar_mesh(width, height, Color(0.16, 0.03, 0.03, 0.82))
	_fill_mesh = _make_bar_mesh(width, height, Color(0.85, 0.14, 0.12, 0.96))
	add_child(_frame_mesh)
	add_child(_background_mesh)
	add_child(_fill_mesh)
	_set_fill_ratio(1.0)
	visible = false


func setup_bone(skeleton: Skeleton3D, bone_idx: int) -> void:
	_skeleton = skeleton
	_bone_idx = bone_idx


func set_health_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	_set_fill_ratio(ratio)
	var fill_mat := _fill_mesh.material_override as StandardMaterial3D
	if fill_mat:
		fill_mat.albedo_color = Color(0.75, 0.1, 0.12, 0.96).lerp(Color(0.18, 0.82, 0.28, 0.98), ratio)


func set_persistent_visible(value: bool) -> void:
	_persistent_visible = value
	_refresh_visibility()


func show_temporarily(duration: float = -1.0) -> void:
	_hide_timer = auto_hide_delay if duration < 0.0 else maxf(duration, 0.0)
	_refresh_visibility()


func hide_immediately() -> void:
	_persistent_visible = false
	_hide_timer = 0.0
	_refresh_visibility()


func _process(delta: float) -> void:
	if _skeleton and _bone_idx >= 0 and is_instance_valid(_skeleton):
		global_position = _skeleton.to_global(_skeleton.get_bone_global_pose(_bone_idx).origin) + vertical_offset

	if not _persistent_visible and _hide_timer > 0.0:
		_hide_timer = maxf(_hide_timer - delta, 0.0)
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = _persistent_visible or _hide_timer > 0.0


func _set_fill_ratio(ratio: float) -> void:
	var fill_width := maxf(width * ratio, 0.001)
	var fill_quad := _fill_mesh.mesh as QuadMesh
	if fill_quad:
		fill_quad.size = Vector2(fill_width, height)
	_fill_mesh.position.x = (-width * 0.5) + (fill_width * 0.5)


func _make_bar_mesh(mesh_width: float, mesh_height: float, color: Color) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(mesh_width, mesh_height)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = _make_material(color)
	return mesh_instance


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = color
	return material