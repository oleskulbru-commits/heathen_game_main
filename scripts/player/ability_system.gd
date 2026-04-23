extends Node
## Ability system — manages spell/gadget loadout and the radial menu.
## Attach as a child of the player CharacterBody3D.
##
## 5 slots: 3 Taufr (spells) + 2 Alchemies (gadgets).
## Hold Q → radial menu; release to select; tap Q → cast selected slot.

signal ability_used(slot: int, name: String)
signal spell_selected(slot: int, name: String)
signal radial_open_requested()
signal radial_close_requested()
signal hugr_changed(value: float)

const SpellFullScript := preload("res://scripts/player/spells/spell_full.gd")

const HOLD_THRESHOLD := 0.2
const SLOT_COUNT := 5
enum ModifierCastMode { NONE, SUSTAINED, TARGETED }
## Hugr — the panic meter.  0 = calm, 1 = full panic.
const HUGR_DECAY_RATE := 0.02  ## Per second when not casting

var selected_slot: int = 0
var _q_pressed_time: float = -1.0
var _menu_is_open: bool = false
var _radial_menu: Control  # set by HUD after ready
var _player: CharacterBody3D
var _prev_mouse_mode: Input.MouseMode
var _hugr: float = 0.0  ## Current panic level
var _modifier_cast_spell: SpellBase = null
var _modifier_cast_mode: ModifierCastMode = ModifierCastMode.NONE

## The 5 equipped abilities.  null = empty slot.
var slots: Array = [null, null, null, null, null]  # Array of SpellBase


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	# Default loadout for prototyping — Dash in slot 0
	_equip_default_loadout()


func _equip_default_loadout() -> void:
	var dash := SpellDash.new()
	var full: SpellBase = SpellFullScript.new()
	equip(0, dash)
	equip(1, full)


func equip(slot: int, spell: SpellBase) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	# Cancel any active spell in the slot being replaced
	if slots[slot] and slots[slot].is_active():
		slots[slot].cancel(_player)
	slots[slot] = spell
	_sync_radial_menu()


func unequip(slot: int) -> void:
	equip(slot, null)


func get_selected_spell() -> SpellBase:
	if selected_slot < 0 or selected_slot >= SLOT_COUNT:
		return null
	return slots[selected_slot]


func _sync_radial_menu() -> void:
	if not _radial_menu:
		return
	var names: Array[String] = []
	var descs: Array[String] = []
	var types: Array[int] = []
	for i in SLOT_COUNT:
		var spell: SpellBase = slots[i]
		if spell:
			names.append(spell.verb_name)
			descs.append(spell.description)
			types.append(spell.slot_type)
		else:
			names.append("Empty")
			descs.append("")
			types.append(0)
	if _radial_menu.has_method("update_slots"):
		_radial_menu.update_slots(names, descs, types)


func _unhandled_input(event: InputEvent) -> void:
	if not _player:
		return

	if event.is_action_pressed("curse_pulse"):
		if Input.is_action_pressed("focus") and _try_start_targeted_cast():
			return
		if Input.is_action_pressed("sprint") and _try_start_modifier_cast():
			return
		_q_pressed_time = Time.get_ticks_msec() / 1000.0
		return

	if event.is_action_released("curse_pulse"):
		if _modifier_cast_spell:
			if _modifier_cast_mode == ModifierCastMode.TARGETED:
				_confirm_targeted_cast()
			else:
				_stop_modifier_cast()
			return
		if _q_pressed_time < 0.0:
			return
		var held := Time.get_ticks_msec() / 1000.0 - _q_pressed_time
		_q_pressed_time = -1.0

		if _menu_is_open:
			_close_menu()
		elif held < HOLD_THRESHOLD:
			_cast_selected()
		return

	if event.is_action_released("sprint") and _modifier_cast_spell and _modifier_cast_mode == ModifierCastMode.SUSTAINED:
		_stop_modifier_cast()
		return

	if event.is_action_released("focus") and _modifier_cast_spell and _modifier_cast_mode == ModifierCastMode.TARGETED:
		_confirm_targeted_cast()


func _process(delta: float) -> void:
	if _modifier_cast_spell and not _modifier_cast_spell.is_active():
		_clear_modifier_cast_state()

	# Check if we should open the radial menu
	if _q_pressed_time >= 0.0 and not _menu_is_open and not _modifier_cast_spell:
		var held := Time.get_ticks_msec() / 1000.0 - _q_pressed_time
		if held >= HOLD_THRESHOLD:
			_open_menu()

	# Update all spell cooldowns
	for spell in slots:
		if spell:
			spell.update(delta)

	# Decay Hugr over time
	if _hugr > 0.0:
		_hugr = maxf(0.0, _hugr - HUGR_DECAY_RATE * delta)
		hugr_changed.emit(_hugr)


func _physics_process(delta: float) -> void:
	# Update active spells (e.g. dash movement)
	for spell in slots:
		if spell and spell.is_active():
			spell.physics_update(_player, delta)


func _open_menu() -> void:
	_menu_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var center := get_viewport().get_visible_rect().size * 0.5
	Input.warp_mouse(center)
	_sync_radial_menu()
	if _radial_menu:
		_radial_menu.open()
	radial_open_requested.emit()


func _close_menu() -> void:
	_menu_is_open = false
	if _radial_menu:
		var picked: int = _radial_menu.close()
		if picked >= 0:
			selected_slot = picked
			var spell := get_selected_spell()
			var sname := spell.verb_name if spell else "Empty"
			spell_selected.emit(selected_slot, sname)
	Input.mouse_mode = _prev_mouse_mode
	radial_close_requested.emit()


func _cast_selected() -> void:
	var spell := get_selected_spell()
	if not spell:
		return
	if not spell.is_ready():
		return
	# Don't cast while another spell is active
	for s in slots:
		if s and s.is_active():
			return

	if spell.cast(_player):
		# Apply Hugr
		_hugr = clampf(_hugr + spell.hugr_cost, 0.0, 1.0)
		hugr_changed.emit(_hugr)
		ability_used.emit(selected_slot, spell.verb_name)


func _try_start_modifier_cast() -> bool:
	var spell := get_selected_spell()
	if not spell:
		return false
	for active_spell in slots:
		if active_spell and active_spell.is_active():
			return false
	if not spell.can_start_sustained(_player):
		return false
	if not spell.start_sustained(_player):
		return false
	_modifier_cast_spell = spell
	_modifier_cast_mode = ModifierCastMode.SUSTAINED
	_hugr = clampf(_hugr + spell.hugr_cost, 0.0, 1.0)
	hugr_changed.emit(_hugr)
	ability_used.emit(selected_slot, spell.verb_name)
	return true


func _try_start_targeted_cast() -> bool:
	var spell := get_selected_spell()
	if not spell:
		return false
	for active_spell in slots:
		if active_spell and active_spell.is_active():
			return false
	if not spell.can_start_targeted(_player):
		return false
	if not spell.start_targeted(_player):
		return false
	_modifier_cast_spell = spell
	_modifier_cast_mode = ModifierCastMode.TARGETED
	return true


func _confirm_targeted_cast() -> void:
	if not _modifier_cast_spell:
		return
	var spell := _modifier_cast_spell
	var cast_succeeded: bool = spell.confirm_targeted(_player)
	_clear_modifier_cast_state()
	if not cast_succeeded:
		return
	_hugr = clampf(_hugr + spell.hugr_cost, 0.0, 1.0)
	hugr_changed.emit(_hugr)
	ability_used.emit(selected_slot, spell.verb_name)


func _stop_modifier_cast() -> void:
	if not _modifier_cast_spell:
		return
	_modifier_cast_spell.cancel(_player)
	_clear_modifier_cast_state()


func _clear_modifier_cast_state() -> void:
	_modifier_cast_spell = null
	_modifier_cast_mode = ModifierCastMode.NONE
	_q_pressed_time = -1.0
