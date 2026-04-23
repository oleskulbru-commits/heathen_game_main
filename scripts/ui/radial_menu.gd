extends Control
## Radial ability menu — 5 wedges: 3 spells (top) + 2 gadgets (bottom).
## Hold Q opens, mouse selects wedge, release Q confirms selection.
## Slot layout (clockwise from top):
##   0 = Spell (top-center)
##   1 = Spell (top-right)
##   2 = Gadget (bottom-right)
##   3 = Gadget (bottom-left)
##   4 = Spell (top-left)

const SLOT_COUNT := 5
const WEDGE_RADIUS := 130.0
const DEADZONE := 30.0
## Evenly spaced wedges, starting at top (-PI/2)
var _wedge_angles: Array[float] = []

## Colors per slot type
const SPELL_COLOR := Color(0.6, 0.35, 0.8, 0.9)       # Purple tint for Taufr
const GADGET_COLOR := Color(0.45, 0.65, 0.35, 0.9)     # Green tint for Alchemies
const SPELL_HIGHLIGHT := Color(0.85, 0.5, 1.0, 1.0)
const GADGET_HIGHLIGHT := Color(0.6, 0.9, 0.45, 1.0)
const DIM_ALPHA := 0.55

## Data — set from ability_system before opening
var slot_names: Array[String] = ["Empty", "Empty", "Empty", "Empty", "Empty"]
var slot_descs: Array[String] = ["", "", "", "", ""]
var slot_types: Array[int] = [0, 0, 0, 0, 0]  # 0 = spell, 1 = gadget

var _hovered_index: int = -1
var _labels: Array[Label] = []
var _descs: Array[Label] = []
var _type_labels: Array[Label] = []
var _ring: Control


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)

	# Compute wedge angles — evenly spaced, starting at top
	_wedge_angles.clear()
	for i in SLOT_COUNT:
		_wedge_angles.append(-PI / 2.0 + i * TAU / float(SLOT_COUNT))

	_ring = Control.new()
	_ring.set_anchors_preset(PRESET_CENTER)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring)

	for i in SLOT_COUNT:
		var angle: float = _wedge_angles[i]
		var pos := Vector2(cos(angle), sin(angle)) * WEDGE_RADIUS

		# Slot type label (SPELL / GADGET)
		var type_lbl := Label.new()
		type_lbl.text = "TAUFR" if slot_types[i] == 0 else "ALCHEMY"
		type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		type_lbl.add_theme_font_size_override("font_size", 9)
		type_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.5))
		type_lbl.position = pos - Vector2(60, 36)
		type_lbl.size = Vector2(120, 16)
		type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.add_child(type_lbl)
		_type_labels.append(type_lbl)

		# Name label
		var lbl := Label.new()
		lbl.text = slot_names[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.position = pos - Vector2(60, 20)
		lbl.size = Vector2(120, 40)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.add_child(lbl)
		_labels.append(lbl)

		# Description label
		var desc := Label.new()
		desc.text = slot_descs[i]
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
		desc.position = pos - Vector2(60, -14)
		desc.size = Vector2(120, 20)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.add_child(desc)
		_descs.append(desc)


func update_slots(names: Array[String], descs: Array[String], types: Array[int]) -> void:
	slot_names = names
	slot_descs = descs
	slot_types = types
	for i in SLOT_COUNT:
		if i < _labels.size():
			_labels[i].text = slot_names[i]
			_descs[i].text = slot_descs[i]
			_type_labels[i].text = "TAUFR" if slot_types[i] == 0 else "ALCHEMY"


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
	for i in SLOT_COUNT:
		var diff := absf(_angle_diff(angle, _wedge_angles[i]))
		if diff < best_diff:
			best_diff = diff
			best = i
	return best


func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0.0:
		d += TAU
	return d - PI


func _slot_base_color(i: int) -> Color:
	return SPELL_COLOR if slot_types[i] == 0 else GADGET_COLOR


func _slot_highlight_color(i: int) -> Color:
	return SPELL_HIGHLIGHT if slot_types[i] == 0 else GADGET_HIGHLIGHT


func _update_highlight() -> void:
	for i in SLOT_COUNT:
		if i >= _labels.size():
			continue
		if i == _hovered_index:
			_labels[i].add_theme_color_override("font_color", _slot_highlight_color(i))
			_labels[i].add_theme_font_size_override("font_size", 24)
			_descs[i].modulate.a = 1.0
			_type_labels[i].modulate.a = 1.0
		else:
			_labels[i].add_theme_color_override("font_color", _slot_base_color(i))
			_labels[i].add_theme_font_size_override("font_size", 20)
			_descs[i].modulate.a = DIM_ALPHA
			_type_labels[i].modulate.a = DIM_ALPHA


func _draw() -> void:
	if not visible:
		return
	var center := get_viewport_rect().size * 0.5 - global_position

	# Dark overlay
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0, 0, 0, 0.45))

	# Outer ring
	draw_arc(center, WEDGE_RADIUS - 25.0, 0.0, TAU, 80, Color(0.5, 0.4, 0.3, 0.25), 2.0)
	draw_arc(center, WEDGE_RADIUS + 35.0, 0.0, TAU, 80, Color(0.5, 0.4, 0.3, 0.12), 1.0)

	# Divider lines between wedges
	for i in SLOT_COUNT:
		var boundary_angle: float = _wedge_angles[i] - TAU / float(SLOT_COUNT) / 2.0
		var dir := Vector2(cos(boundary_angle), sin(boundary_angle))
		var p1 := center + dir * (WEDGE_RADIUS - 25.0)
		var p2 := center + dir * (WEDGE_RADIUS + 35.0)
		draw_line(p1, p2, Color(0.4, 0.35, 0.3, 0.2), 1.0)

	# Highlight selected wedge
	if _hovered_index >= 0:
		var angle: float = _wedge_angles[_hovered_index]
		var dir := Vector2(cos(angle), sin(angle))
		var p1 := center + dir * (WEDGE_RADIUS - 35.0)
		var p2 := center + dir * (WEDGE_RADIUS + 45.0)
		var color := _slot_highlight_color(_hovered_index)
		color.a = 0.3
		draw_line(p1, p2, color, 44.0)

	# Center dot
	draw_circle(center, 4.0, Color(0.7, 0.6, 0.5, 0.4))

	queue_redraw()
