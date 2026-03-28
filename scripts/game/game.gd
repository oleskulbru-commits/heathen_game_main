extends Node3D

@onready var level: Node = get_node_or_null("FjordSlice")
@onready var player: Node = _resolve_player()
@onready var title_label: Label = get_node_or_null("CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/TitleLabel") as Label
@onready var objective_label: Label = get_node_or_null("CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/ObjectiveLabel") as Label
@onready var progress_label: Label = get_node_or_null("CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/ProgressLabel") as Label
@onready var status_label: Label = get_node_or_null("CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/StatusLabel") as Label
@onready var health_label: Label = get_node_or_null("CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/HealthLabel") as Label
@onready var controls_label: Label = get_node_or_null("CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/ControlsLabel") as Label
@onready var prompt_label: Label = get_node_or_null("CanvasLayer/MarginContainer/PanelContainer/VBoxContainer/PromptLabel") as Label

func _ready() -> void:
	_ensure_input_map()
	_connect_level_signals()
	_connect_player_signals()
	_seed_hud_state()
	if controls_label != null:
		controls_label.text = "WASD move | Shift sprint | Space jump | C evade | LMB strike | Q omen or advanced rite | E interact | Esc free mouse"
	if title_label != null:
		title_label.text = "HEATHEN // Quiet Place Slice Prototype"

func _resolve_player() -> Node:
	if level != null and level.has_method("get_player"):
		return level.get_player()
	return get_node_or_null("Player")

func _connect_level_signals() -> void:
	if level == null:
		return
	if level.has_signal("objective_updated"):
		level.objective_updated.connect(_set_objective)
	if level.has_signal("progress_updated"):
		level.progress_updated.connect(_set_progress)
	if level.has_signal("status_updated"):
		level.status_updated.connect(_set_status)
	if level.has_signal("prompt_updated"):
		level.prompt_updated.connect(_set_prompt)
	if level.has_signal("level_completed"):
		level.level_completed.connect(_on_level_completed)

func _connect_player_signals() -> void:
	if player == null:
		return
	if player.has_signal("health_changed"):
		player.health_changed.connect(_set_health)
	if player.has_signal("status_changed"):
		player.status_changed.connect(_set_status)

func _seed_hud_state() -> void:
	if level != null:
		if level.has_method("get_current_objective"):
			_set_objective(level.get_current_objective())
		if level.has_method("get_current_progress_text"):
			_set_progress(level.get_current_progress_text())
		if level.has_method("get_current_status"):
			_set_status(level.get_current_status())
		if level.has_method("get_current_prompt"):
			_set_prompt(level.get_current_prompt())
	else:
		_set_objective("Prototype bootstrap in progress.")
		_set_progress("No level slice instantiated in the current main scene.")
		_set_prompt("")

	if player != null and player.has_method("get_health"):
		_set_health(player.get_health())
	elif health_label != null:
		_set_health(0.0)

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
	if objective_label != null:
		objective_label.text = "Objective: %s" % text

func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = "Status: %s" % text

func _set_progress(text: String) -> void:
	if progress_label != null:
		progress_label.text = text

func _set_health(value: float) -> void:
	if health_label != null:
		health_label.text = "Health: %d" % int(round(value))

func _set_prompt(text: String) -> void:
	if prompt_label != null:
		prompt_label.text = text

func _on_level_completed() -> void:
	_set_status("Quiet Place route completed. Expand this benchmark with stronger cabin atmosphere, village stealth pressure, and a sharper dock passage.")
	_set_objective("Return to editor and iterate on the cabin ritual loop, village theft, and rite-assisted escape.")
