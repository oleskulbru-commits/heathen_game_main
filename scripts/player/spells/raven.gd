extends Node3D
## Placeholder raven for the Hrafn (Raven's Dash) spell.
## Replace this mesh with a proper raven model later.
## The raven follows a cubic-bezier path assigned via set_flight_path().

@onready var _mesh: MeshInstance3D = $Body
@onready var _trail: GPUParticles3D = $Trail

var _path_points: PackedVector3Array  ## Bezier control points: [P0, P1, P2, P3]
var _flight_t: float = 0.0
var _active: bool = false
var _wing_time: float = 0.0


func set_flight_path(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	_path_points = PackedVector3Array([p0, p1, p2, p3])
	_flight_t = 0.0
	_active = true
	global_position = p0
	if _trail:
		_trail.emitting = true


func advance(t: float) -> void:
	## t in [0, 1] — progress along the bezier
	if _path_points.size() < 4:
		return
	_flight_t = clampf(t, 0.0, 1.0)
	global_position = _cubic_bezier(_flight_t)
	# Face movement direction
	var look_t := clampf(t + 0.02, 0.0, 1.0)
	var ahead := _cubic_bezier(look_t)
	var dir := ahead - global_position
	if dir.length_squared() > 0.0001:
		look_at(global_position + dir, Vector3.UP)


func finish() -> void:
	_active = false
	if _trail:
		_trail.emitting = false


func _process(delta: float) -> void:
	# Simple wing flap: rock the mesh on X axis
	if _active and _mesh:
		_wing_time += delta * 18.0
		_mesh.rotation.z = sin(_wing_time) * 0.35


func _cubic_bezier(t: float) -> Vector3:
	var p0 := _path_points[0]
	var p1 := _path_points[1]
	var p2 := _path_points[2]
	var p3 := _path_points[3]
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3
