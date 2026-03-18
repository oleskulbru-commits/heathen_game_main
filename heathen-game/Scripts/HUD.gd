extends CanvasLayer

const SPELL_WHEEL_OFFSETS := [
	Vector2(0.0, -148.0),
	Vector2(188.0, 0.0),
	Vector2(0.0, 148.0),
	Vector2(-188.0, 0.0)
]

@onready var health_label: Label = $HealthPanel/HealthMargin/HealthVBox/HealthLabel
@onready var health_bar: ProgressBar = $HealthPanel/HealthMargin/HealthVBox/HealthBar
@onready var game_over_overlay: Control = $GameOverOverlay
@onready var restart_button: Button = $GameOverOverlay/GameOverCenter/GameOverPanel/GameOverMargin/GameOverVBox/RestartButton

var player: Node
var spell_names: Array[String] = []
var spell_descriptions: Array[String] = []
var selected_spell_index := 0
var spell_wheel_overlay: Control
var spell_status_label: Label
var spell_hint_label: Label
var spell_feedback_label: Label
var spell_center_title_label: Label
var spell_center_description_label: Label
var spell_option_panels: Array[PanelContainer] = []
var spell_option_name_labels: Array[Label] = []
var spell_option_description_labels: Array[Label] = []
var threat_status_label: Label
var threat_detail_label: Label
var threat_meter: ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_overlay.visible = false
	_build_spell_ui()
	restart_button.pressed.connect(_on_restart_pressed)
	call_deferred("_bind_player")


func _bind_player() -> void:
	if player != null and is_instance_valid(player):
		return

	player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	player.connect("health_changed", Callable(self, "_on_player_health_changed"))
	player.connect("died", Callable(self, "_on_player_died"))
	player.connect("spell_wheel_toggled", Callable(self, "_on_spell_wheel_toggled"))
	player.connect("spell_selection_changed", Callable(self, "_on_spell_selection_changed"))
	player.connect("spell_cast", Callable(self, "_on_spell_cast"))
	player.connect("stealth_feedback_changed", Callable(self, "_on_player_stealth_feedback_changed"))
	_on_player_health_changed(float(player.get("health")), float(player.get("max_health")))
	if player.has_method("get_spell_names") and player.has_method("get_spell_descriptions") and player.has_method("get_selected_spell_index"):
		_on_spell_selection_changed(player.get_spell_names(), player.get_spell_descriptions(), int(player.get_selected_spell_index()))
	if player.has_method("get_stealth_feedback_label") and player.has_method("get_stealth_feedback_detail") and player.has_method("get_stealth_feedback_strength"):
		_on_player_stealth_feedback_changed(player.get_stealth_feedback_label(), player.get_stealth_feedback_detail(), player.get_stealth_feedback_strength())


func _on_player_health_changed(current_health: float, maximum_health: float) -> void:
	health_bar.max_value = maximum_health
	health_bar.value = current_health
	health_label.text = "Health %d / %d" % [int(round(current_health)), int(round(maximum_health))]


func _on_player_died() -> void:
	spell_wheel_overlay.visible = false
	game_over_overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_tree().reload_current_scene()


func _build_spell_ui() -> void:
	var threat_panel := PanelContainer.new()
	threat_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	threat_panel.offset_left = -348.0
	threat_panel.offset_top = 24.0
	threat_panel.offset_right = -24.0
	threat_panel.offset_bottom = 154.0
	add_child(threat_panel)

	var threat_margin := MarginContainer.new()
	threat_margin.add_theme_constant_override("margin_left", 16)
	threat_margin.add_theme_constant_override("margin_top", 14)
	threat_margin.add_theme_constant_override("margin_right", 16)
	threat_margin.add_theme_constant_override("margin_bottom", 14)
	threat_panel.add_child(threat_margin)

	var threat_vbox := VBoxContainer.new()
	threat_vbox.add_theme_constant_override("separation", 6)
	threat_margin.add_child(threat_vbox)

	threat_status_label = Label.new()
	threat_status_label.text = "Hugr: Stillness"
	threat_vbox.add_child(threat_status_label)

	threat_meter = ProgressBar.new()
	threat_meter.custom_minimum_size = Vector2(0.0, 18.0)
	threat_meter.max_value = 1.0
	threat_meter.value = 0.0
	threat_meter.show_percentage = false
	threat_vbox.add_child(threat_meter)

	threat_detail_label = Label.new()
	threat_detail_label.text = "No hostile pulse nearby."
	threat_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	threat_vbox.add_child(threat_detail_label)

	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	status_panel.offset_left = -348.0
	status_panel.offset_top = -132.0
	status_panel.offset_right = -24.0
	status_panel.offset_bottom = -24.0
	add_child(status_panel)

	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 16)
	status_margin.add_theme_constant_override("margin_top", 14)
	status_margin.add_theme_constant_override("margin_right", 16)
	status_margin.add_theme_constant_override("margin_bottom", 14)
	status_panel.add_child(status_margin)

	var status_vbox := VBoxContainer.new()
	status_vbox.add_theme_constant_override("separation", 6)
	status_margin.add_child(status_vbox)

	spell_status_label = Label.new()
	spell_status_label.text = "Spell: Ember Burst"
	status_vbox.add_child(spell_status_label)

	spell_hint_label = Label.new()
	spell_hint_label.text = "Tap Q to cast. Hold Q + WASD to select."
	spell_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_vbox.add_child(spell_hint_label)

	spell_feedback_label = Label.new()
	spell_feedback_label.text = "Placeholder spells are active."
	spell_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_vbox.add_child(spell_feedback_label)

	spell_wheel_overlay = Control.new()
	spell_wheel_overlay.visible = false
	spell_wheel_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spell_wheel_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(spell_wheel_overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.03, 0.3)
	spell_wheel_overlay.add_child(backdrop)

	var center_panel := PanelContainer.new()
	center_panel.custom_minimum_size = Vector2(220.0, 106.0)
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -110.0
	center_panel.offset_top = -53.0
	center_panel.offset_right = 110.0
	center_panel.offset_bottom = 53.0
	spell_wheel_overlay.add_child(center_panel)

	var center_margin := MarginContainer.new()
	center_margin.add_theme_constant_override("margin_left", 16)
	center_margin.add_theme_constant_override("margin_top", 14)
	center_margin.add_theme_constant_override("margin_right", 16)
	center_margin.add_theme_constant_override("margin_bottom", 14)
	center_panel.add_child(center_margin)

	var center_vbox := VBoxContainer.new()
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.add_theme_constant_override("separation", 6)
	center_margin.add_child(center_vbox)

	spell_center_title_label = Label.new()
	spell_center_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spell_center_title_label.text = "Selected Spell"
	center_vbox.add_child(spell_center_title_label)

	spell_center_description_label = Label.new()
	spell_center_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spell_center_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center_vbox.add_child(spell_center_description_label)

	for option_index: int in range(SPELL_WHEEL_OFFSETS.size()):
		var option_panel := PanelContainer.new()
		option_panel.custom_minimum_size = Vector2(170.0, 84.0)
		option_panel.set_anchors_preset(Control.PRESET_CENTER)
		var offset: Vector2 = SPELL_WHEEL_OFFSETS[option_index]
		option_panel.offset_left = offset.x - 85.0
		option_panel.offset_top = offset.y - 42.0
		option_panel.offset_right = offset.x + 85.0
		option_panel.offset_bottom = offset.y + 42.0
		spell_wheel_overlay.add_child(option_panel)
		spell_option_panels.append(option_panel)

		var option_margin := MarginContainer.new()
		option_margin.add_theme_constant_override("margin_left", 14)
		option_margin.add_theme_constant_override("margin_top", 12)
		option_margin.add_theme_constant_override("margin_right", 14)
		option_margin.add_theme_constant_override("margin_bottom", 12)
		option_panel.add_child(option_margin)

		var option_vbox := VBoxContainer.new()
		option_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		option_vbox.add_theme_constant_override("separation", 4)
		option_margin.add_child(option_vbox)

		var option_name_label := Label.new()
		option_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_vbox.add_child(option_name_label)
		spell_option_name_labels.append(option_name_label)

		var option_description_label := Label.new()
		option_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		option_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		option_vbox.add_child(option_description_label)
		spell_option_description_labels.append(option_description_label)

	_refresh_spell_ui()


func _on_spell_wheel_toggled(is_visible: bool) -> void:
	spell_wheel_overlay.visible = is_visible
	_refresh_spell_ui()


func _on_spell_selection_changed(next_spell_names: Array[String], next_spell_descriptions: Array[String], next_selected_spell_index: int) -> void:
	spell_names = next_spell_names
	spell_descriptions = next_spell_descriptions
	selected_spell_index = next_selected_spell_index
	_refresh_spell_ui()


func _on_spell_cast(spell_name: String, cast_text: String) -> void:
	spell_feedback_label.text = "%s: %s" % [spell_name, cast_text]


func _on_player_stealth_feedback_changed(reading_label: String, reading_detail: String, pulse_strength: float) -> void:
	threat_status_label.text = "Hugr: %s" % reading_label
	threat_detail_label.text = reading_detail
	threat_meter.value = clampf(pulse_strength, 0.0, 1.0)
	var threat_color := Color(0.66, 0.82, 0.7, 1.0).lerp(Color(0.96, 0.23, 0.2, 1.0), pulse_strength)
	threat_status_label.modulate = threat_color
	threat_detail_label.modulate = Color(0.9, 0.92, 0.96, 0.82).lerp(Color(1.0, 0.86, 0.84, 1.0), pulse_strength)


func _refresh_spell_ui() -> void:
	var selected_spell_name := "None"
	var selected_spell_description := "No spell selected."
	if not spell_names.is_empty() and selected_spell_index >= 0 and selected_spell_index < spell_names.size():
		selected_spell_name = spell_names[selected_spell_index]
		if selected_spell_index < spell_descriptions.size():
			selected_spell_description = spell_descriptions[selected_spell_index]

	spell_status_label.text = "Spell: %s" % selected_spell_name
	spell_center_title_label.text = selected_spell_name
	spell_center_description_label.text = selected_spell_description

	for option_index: int in range(spell_option_panels.size()):
		var has_spell := option_index < spell_names.size()
		spell_option_panels[option_index].visible = has_spell
		if not has_spell:
			continue

		spell_option_name_labels[option_index].text = spell_names[option_index]
		spell_option_description_labels[option_index].text = spell_descriptions[option_index] if option_index < spell_descriptions.size() else ""
		if option_index == selected_spell_index:
			spell_option_panels[option_index].modulate = Color(1.18, 1.05, 0.82, 1.0)
			spell_option_panels[option_index].scale = Vector2.ONE * 1.04
		else:
			spell_option_panels[option_index].modulate = Color(0.82, 0.86, 0.92, 0.92)
			spell_option_panels[option_index].scale = Vector2.ONE
