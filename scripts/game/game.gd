extends Node3D

@onready var level = $FjordSlice
@onready var title_label: Label = $CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/TitleLabel
@onready var objective_label: Label = $CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/ObjectiveLabel
@onready var progress_label: Label = $CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/ProgressLabel
@onready var status_label: Label = $CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/StatusLabel
@onready var health_label: Label = $CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/HealthLabel
@onready var controls_label: Label = $CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/ControlsLabel
@onready var prompt_label: Label = $CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/PromptLabel

func _ready() -> void:
	_ensure_input_map()
	var player = level.get_player()
	level.objective_updated.connect(_set_objective)
	level.progress_updated.connect(_set_progress)
	level.status_updated.connect(_set_status)
	level.prompt_updated.connect(_set_prompt)
	level.level_completed.connect(_on_level_completed)
	player.health_changed.connect(_set_health)
	player.status_changed.connect(_set_status)
	_set_objective(level.get_current_objective())
	_set_progress(level.get_current_progress_text())
	_set_status(level.get_current_status())
	_set_health(player.get_health())
	_set_prompt(level.get_current_prompt())
	controls_label.text = "WASD move | Shift sprint | Space jump | C evade | LMB strike | Q omen pulse | E interact | Esc free mouse"
	title_label.text = "HEATHEN // Escape Slice Prototype"

func _ensure_input_map() -> void:
	_set_key_action("move_forward", KEY_W)
	_set_key_action("move_back", KEY_S)
	_set_key_action("move_left", KEY_A)
	_set_key_action("move_right", KEY_D)
	_set_key_action("sprint", KEY_SHIFT)
	_set_key_action("jump", KEY_SPACE)
	_set_key_action("evade", KEY_C)
	_set_key_action("curse_pulse", KEY_Q)
	_set_key_action("interact", KEY_E)
	_set_key_action("ui_cancel", KEY_ESCAPE)
	_ensure_mouse_action("attack", MOUSE_BUTTON_LEFT)

func _set_key_action(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	key_event.keycode = keycode
	InputMap.action_add_event(action, key_event)

func _ensure_mouse_action(action: StringName, button_index: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button_index:
			return
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = button_index
	InputMap.action_add_event(action, mouse_event)

func _set_objective(text: String) -> void:
	objective_label.text = "Objective: %s" % text

func _set_status(text: String) -> void:
	status_label.text = "Status: %s" % text

func _set_progress(text: String) -> void:
	progress_label.text = text

func _set_health(value: float) -> void:
	health_label.text = "Health: %d" % int(round(value))

func _set_prompt(text: String) -> void:
	prompt_label.text = text

func _on_level_completed() -> void:
	_set_status("Escape route completed. Expand this benchmark with better stealth, village pressure, and shoreline atmosphere.")
	_set_objective("Return to editor and iterate on woods tension, village traversal, and the boat getaway.")