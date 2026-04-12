extends Control
## Radial ability menu — shows 3 wedges arranged in a circle.
## Hold Q opens, mouse selects wedge, release Q confirms selection.

const ABILITY_NAMES := ["Drukna", "Hrafn", "Gellir"]
const ABILITY_DESCS := ["Extinguish flames", "Teleport dash", "Freeze enemies"]
const WEDGE_RADIUS := 120.0
const DEADZONE := 30.0
const WEDGE_ANGLES := [-PI / 2.0, -PI / 2.0 + TAU / 3.0, -PI / 2.0 + 2.0 * TAU / 3.0]

var _hovered_index: int = -1
var _labels: Array[Label] = []
var _descs: Array[Label] = []
var _ring: Control


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Full-screen overlay
	set_anchors_preset(PRESET_FULL_RECT)

	_ring = Control.new()
	_ring.set_anchors_preset(PRESET_CENTER)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)

	for i in 3:
		var angle: float = WEDGE_ANGLES[i]
		var pos := Vector2(cos(angle), sin(angle)) * WEDGE_RADIUS

		var lbl := Label.new()
		lbl.text = ABILITY_NAMES[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.position = pos - Vector2(60, 20)
		lbl.size = Vector2(120, 40)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.add_child(lbl)
		_labels.append(lbl)

		var desc := Label.new()
		desc.text = ABILITY_DESCS[i]
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
		desc.position = pos - Vector2(60, -14)
		desc.size = Vector2(120, 20)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.add_child(desc)
		_descs.append(desc)


func open() -> void:
	visible = true
	_hovered_index = -1
	_update_highlight()


func close() -> int:
	visible = false
	return _hovered_index


func _process(_delta: float) -> void:
	if not visible:
		return
	var center := get_viewport_rect().size * 0.5
	var mouse := get_viewport().get_mouse_position()
	var offset := mouse - center
	if offset.length() < DEADZONE:
		_hovered_index = -1
	else:
		var angle := offset.angle()
		_hovered_index = _angle_to_wedge(angle)
	_update_highlight()


func _angle_to_wedge(angle: float) -> int:
	var best := -1
	var best_diff := TAU
	for i in 3:
		var diff := absf(_angle_diff(angle, WEDGE_ANGLES[i]))
		if diff < best_diff:
			best_diff = diff
			best = i
	return best


func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI


func _update_highlight() -> void:
	for i in 3:
		if i == _hovered_index:
			_labels[i].add_theme_color_override("font_color", Color(1.0, 0.75, 0.3, 1.0))
			_labels[i].add_theme_font_size_override("font_size", 24)
			_descs[i].modulate.a = 1.0
		else:
			_labels[i].add_theme_color_override("font_color", Color(0.85, 0.82, 0.75, 0.7))
			_labels[i].add_theme_font_size_override("font_size", 20)
			_descs[i].modulate.a = 0.5


func _draw() -> void:
	if not visible:
		return
	var center := get_viewport_rect().size * 0.5 - global_position
	# Dark overlay
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.4))
	# Center ring
	draw_arc(center, WEDGE_RADIUS - 20.0, 0.0, TAU, 64, Color(0.6, 0.5, 0.35, 0.3), 2.0)
	draw_arc(center, WEDGE_RADIUS + 30.0, 0.0, TAU, 64, Color(0.6, 0.5, 0.35, 0.15), 1.0)
	# Highlight wedge
	if _hovered_index >= 0:
		var angle: float = WEDGE_ANGLES[_hovered_index]
		var dir := Vector2(cos(angle), sin(angle))
		var p1 := center + dir * (WEDGE_RADIUS - 30.0)
		var p2 := center + dir * (WEDGE_RADIUS + 40.0)
		draw_line(p1, p2, Color(1.0, 0.7, 0.3, 0.4), 40.0)
	queue_redraw()
