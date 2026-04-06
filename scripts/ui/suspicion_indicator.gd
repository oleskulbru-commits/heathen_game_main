extends Node2D
## AC Origins / TLOU-style directional suspicion indicator.
## Draws arc segments around screen centre that point toward each enemy
## whose suspicion is above zero.  Arc length and colour scale with suspicion.

@export var arc_radius: float = 120.0
@export var arc_thickness_min: float = 3.0
@export var arc_thickness_max: float = 7.0
@export var arc_angle_min_deg: float = 12.0   ## at threshold_curious
@export var arc_angle_max_deg: float = 50.0   ## at threshold_combat
@export var arc_segments: int = 32

const COLOR_ZERO    := Color(1.0, 0.9, 0.3, 0.0)   # fully transparent
const COLOR_CURIOUS := Color(1.0, 0.9, 0.3, 0.85)   # yellow
const COLOR_ALERT   := Color(1.0, 0.5, 0.0, 0.92)   # orange
const COLOR_COMBAT  := Color(1.0, 0.1, 0.1, 1.0)    # red

var _camera: Camera3D
var _player: CharacterBody3D
var _any_active: bool = false


func _ready() -> void:
	await get_tree().process_frame
	_player = _find_player()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _player:
		return
	_camera = get_viewport().get_camera_3d()
	if not _camera:
		return

	var centre := get_viewport_rect().size * 0.5
	var cam_fwd := -_camera.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length_squared() < 0.001:
		return
	cam_fwd = cam_fwd.normalized()

	_any_active = false

	for node in get_tree().get_nodes_in_group("bandit"):
		var perception := node.get_node_or_null("BanditPerception")
		if not perception:
			continue
		var sus: float = perception.suspicion
		if sus <= 0.0:
			continue

		_any_active = true

		var tc: float = perception.threshold_curious
		var ta: float = perception.threshold_alert
		var tb: float = perception.threshold_combat

		# ── Colour ──────────────────────────────────────────────────────
		var color: Color
		if sus < tc:
			color = COLOR_ZERO.lerp(COLOR_CURIOUS, sus / tc)
		elif sus < ta:
			color = COLOR_CURIOUS.lerp(COLOR_ALERT, (sus - tc) / (ta - tc))
		elif sus < tb:
			color = COLOR_ALERT.lerp(COLOR_COMBAT, (sus - ta) / (tb - ta))
		else:
			color = COLOR_COMBAT

		# ── Direction (signed angle on XZ plane) ────────────────────────
		var to_bandit: Vector3 = node.global_position - _player.global_position
		to_bandit.y = 0.0
		if to_bandit.length_squared() < 0.01:
			continue
		to_bandit = to_bandit.normalized()

		# Signed angle: 0 = camera forward (top of screen), +CW
		var angle := atan2(cam_fwd.cross(to_bandit).y, cam_fwd.dot(to_bandit))

		# ── Arc geometry ────────────────────────────────────────────────
		# Normalise suspicion into 0–1 for scaling (starts visible at threshold_curious)
		var t := clampf(sus, 0.0, 1.0)
		var half_arc := deg_to_rad(lerpf(arc_angle_min_deg, arc_angle_max_deg, t)) * 0.5
		var thickness := lerpf(arc_thickness_min, arc_thickness_max, t)

		# draw_arc angles: 0 = right (+X on screen).
		# Our angle: 0 = up (camera forward).  Screen convention: up = -PI/2.
		var screen_angle := angle - PI * 0.5

		# Godot draw_arc wants start/end in radians, counterclockwise.
		var start_angle := screen_angle - half_arc
		var end_angle := screen_angle + half_arc

		# Build a PackedVector2Array for the arc manually (draw_arc doesn't
		# support variable thickness well, so we use draw_polyline).
		var points := PackedVector2Array()
		for i in range(arc_segments + 1):
			var frac := float(i) / float(arc_segments)
			var a := lerpf(start_angle, end_angle, frac)
			points.append(centre + Vector2(cos(a), sin(a)) * arc_radius)

		draw_polyline(points, color, thickness, true)


func _find_player() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as CharacterBody3D
	var p := get_tree().root.find_child("Player", true, false)
	if p is CharacterBody3D:
		return p
	return null
