extends Node2D
## Detection meter — shows the highest current bandit suspicion as a segmented
## fill bar with a pulsing "eye" icon and text labels for alert states.
## Sits at the bottom-centre of the screen.

# ── Fill colours ────────────────────────────────────────────────────────────
const COLOR_FRAME   := Color(0.85, 0.82, 0.75, 0.70)  # off-white frame, always visible
const COLOR_EMPTY   := Color(0.25, 0.22, 0.18, 0.55)  # dark slot background
const COLOR_CURIOUS := Color(1.0,  0.9,  0.3,  1.0)   # yellow
const COLOR_ALERT   := Color(1.0,  0.45, 0.0,  1.0)   # orange
const COLOR_COMBAT  := Color(1.0,  0.1,  0.1,  1.0)   # red

# Bar geometry
const BAR_W      := 180.0
const BAR_H      := 10.0
const SEGMENTS   := 10

# Label strings per alert level
const ALERT_LABELS := ["", "SPOTTED", "ALERT", "COMBAT"]

var _suspicion: float = 0.0     # smoothed display value
var _peak_suspicion: float = 0.0  # raw from perceptions
var _alert_level: int = 0
var _label_alpha: float = 0.0
var _pulse: float = 0.0          # for the eye icon
var _dbg_frame: int = 0

func _ready() -> void:
	print("[DetectionMeter] ready, drawing at viewport ", get_viewport_rect().size)

func _process(delta: float) -> void:
	_gather_suspicion()
	_suspicion = lerpf(_suspicion, _peak_suspicion, clampf(8.0 * delta, 0.0, 1.0))
	# Label fade in/out
	var label_target := 1.0 if _alert_level > 0 else 0.0
	_label_alpha = lerpf(_label_alpha, label_target, clampf(4.0 * delta, 0.0, 1.0))
	# Eye pulse speed increases with suspicion
	_pulse = fmod(_pulse + delta * (0.8 + _suspicion * 2.5), TAU)
	_dbg_frame += 1
	if _dbg_frame % 120 == 1:
		print("[DetectionMeter] frame=", _dbg_frame, "  peak_sus=", _peak_suspicion, "  smoothed=", _suspicion, "  alert=", _alert_level, "  vp=", get_viewport_rect().size)
	queue_redraw()

func _gather_suspicion() -> void:
	_peak_suspicion = 0.0
	_alert_level = 0
	var bandits := get_tree().get_nodes_in_group("bandit")
	if _dbg_frame % 120 == 1:
		print("[DetectionMeter] _gather: bandit_count=", bandits.size())
	for node in bandits:
		var source := node.get_node_or_null("BanditBrain")
		if not source:
			source = node.get_node_or_null("BanditPerception")
		if not source:
			if _dbg_frame % 120 == 1:
				print("[DetectionMeter]   bandit '", node.name, "' has no BanditBrain/BanditPerception child")
			continue
		var sus: float = source.suspicion
		if sus > _peak_suspicion:
			_peak_suspicion = sus
			_alert_level = source.alert_level

func _draw() -> void:
	# Use viewport rect — Control.size is 0 when direct child of CanvasLayer
	var vp := get_viewport_rect().size
	var centre_x := vp.x * 0.5
	var bar_top := vp.y - 54.0
	var bar_left := centre_x - BAR_W * 0.5

	# Suspicion drives opacity; empty bar always dimly visible
	var fill_alpha := clampf(_suspicion * 12.0, 0.0, 1.0)

	# Current fill colour
	var fill_color := _suspicion_color(_suspicion)

	# ── Eye outline icon (above bar) ───────────────────────────────────
	_draw_eye(centre_x, bar_top - 18.0, fill_color, fill_alpha)

	# ── Segmented bar ─────────────────────────────────────────────────
	var gap := 2.0
	var seg_w := (BAR_W - gap * (SEGMENTS - 1)) / SEGMENTS
	var filled_segments := _suspicion * SEGMENTS

	for i in range(SEGMENTS):
		var seg_x := bar_left + i * (seg_w + gap)
		var seg_fill := clampf(filled_segments - i, 0.0, 1.0)

		# Background always drawn (dim frame)
		var bg_col := COLOR_EMPTY
		bg_col.a = 0.55
		draw_rect(Rect2(seg_x, bar_top, seg_w, BAR_H), bg_col, true)

		if seg_fill > 0.0:
			var fc := fill_color
			fc.a = seg_fill
			draw_rect(Rect2(seg_x, bar_top, seg_w * seg_fill, BAR_H), fc, true)

	# ── Alert state label ──────────────────────────────────────────────
	if _label_alpha > 0.01 and _alert_level > 0 and _alert_level < ALERT_LABELS.size():
		var label_str: String = ALERT_LABELS[_alert_level]
		var label_col := fill_color
		label_col.a *= _label_alpha
		# Pulsing opacity for "COMBAT"
		if _alert_level == 3:
			label_col.a *= 0.6 + 0.4 * sin(_pulse * 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(centre_x - 30.0, bar_top - 38.0),
			label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, label_col)

	# ── Debug: suspicion numeric value (always shown, small text below bar) ──
	var dbg_str := "sus: %.2f" % _peak_suspicion
	draw_string(ThemeDB.fallback_font,
		Vector2(bar_left, bar_top + BAR_H + 12.0),
		dbg_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))

func _draw_eye(cx: float, cy: float, color: Color, fill_alpha: float) -> void:
	var pulse_scale := 1.0 + 0.08 * sin(_pulse)
	var eye_w := 22.0 * pulse_scale
	var eye_h := 12.0 * pulse_scale

	# Outer eye shape — always drawn in frame color
	var points := PackedVector2Array()
	var pts_bot := PackedVector2Array()
	var n := 20
	for i in range(n + 1):
		var t := float(i) / n
		var a := lerpf(-PI * 0.85, PI * 0.85, t)
		points.append(Vector2(cx + cos(a) * eye_w * 0.5, cy - absf(sin(a)) * eye_h * 0.5))
		pts_bot.append(Vector2(cx + cos(a) * eye_w * 0.5, cy + absf(sin(a)) * eye_h * 0.5))

	draw_polyline(points, COLOR_FRAME, 1.5, true)
	draw_polyline(pts_bot, COLOR_FRAME, 1.5, true)

	# Pupil — grows with suspicion
	var pupil_r := 3.5 * pulse_scale * clampf(fill_alpha * 2.0 + 0.4, 0.4, 1.0)
	var pupil_col := color if fill_alpha > 0.01 else COLOR_FRAME
	pupil_col.a = 0.8
	draw_circle(Vector2(cx, cy), pupil_r, pupil_col)

func _suspicion_color(sus: float) -> Color:
	# Matches suspicion_indicator.gd thresholds (use typical defaults)
	var tc := 0.3
	var ta := 0.6
	var tb := 0.9
	if sus < tc:
		return COLOR_EMPTY.lerp(COLOR_CURIOUS, sus / tc)
	elif sus < ta:
		return COLOR_CURIOUS.lerp(COLOR_ALERT, (sus - tc) / (ta - tc))
	elif sus < tb:
		return COLOR_ALERT.lerp(COLOR_COMBAT, (sus - ta) / (tb - ta))
	return COLOR_COMBAT
