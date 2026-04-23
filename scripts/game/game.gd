extends Node3D

func _ready() -> void:
	_ensure_input_map()


func _ensure_input_map() -> void:
	_set_key_action("move_forward", KEY_W)
	_set_key_action("move_back", KEY_S)
	_set_key_action("move_left", KEY_A)
	_set_key_action("move_right", KEY_D)
	_set_key_action("dodge_modifier", KEY_SPACE)
	_set_key_action("sprint", KEY_SHIFT)
	_clear_key_action("jump")
	_set_key_action("evade", KEY_CTRL)
	_set_key_action("crouch", KEY_C)
	_set_key_action("draw_weapon", KEY_R)
	_set_key_action("curse_pulse", KEY_Q)
	_set_key_action("interact", KEY_E)
	_set_key_action("ui_cancel", KEY_ESCAPE)
	_ensure_mouse_action("attack", MOUSE_BUTTON_LEFT)
	_ensure_mouse_action("focus", MOUSE_BUTTON_RIGHT)

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


func _clear_key_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)

func _ensure_mouse_action(action: StringName, button_index: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button_index:
			return
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = button_index
	InputMap.action_add_event(action, mouse_event)
