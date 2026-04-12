extends Node
## Ability system — manages the radial menu and executes Norse abilities.
## Attach as a child of the player CharacterBody3D.
##
## Abilities:
##   0 = Drukna   — extinguish all flames within 5 m
##   1 = Hrafn    — teleport-dash 5 m in camera-facing direction
##   2 = Gellir   — freeze all enemies within 3 m for 5 s

signal ability_used(index: int, name: String)
signal radial_open_requested()
signal radial_close_requested()

const HOLD_THRESHOLD := 0.2
const DRUKNA_RANGE := 5.0
const HRAFN_RANGE := 5.0
const GELLIR_RANGE := 3.0
const GELLIR_DURATION := 5.0
const ABILITY_NAMES := ["Drukna", "Hrafn", "Gellir"]

var selected_ability: int = 0
var _q_pressed_time: float = -1.0
var _menu_is_open: bool = false
var _radial_menu: Control  # set by HUD after ready
var _player: CharacterBody3D
var _prev_mouse_mode: Input.MouseMode


func _ready() -> void:
	_player = get_parent() as CharacterBody3D


func _unhandled_input(event: InputEvent) -> void:
	if not _player:
		return

	if event.is_action_pressed("curse_pulse"):
		_q_pressed_time = Time.get_ticks_msec() / 1000.0

	if event.is_action_released("curse_pulse"):
		var held := Time.get_ticks_msec() / 1000.0 - _q_pressed_time
		_q_pressed_time = -1.0

		if _menu_is_open:
			# Close menu and confirm selection
			_close_menu()
		elif held < HOLD_THRESHOLD:
			# Tap — use selected ability
			_use_ability(selected_ability)


func _process(_delta: float) -> void:
	if _q_pressed_time < 0.0 or _menu_is_open:
		return
	var held := Time.get_ticks_msec() / 1000.0 - _q_pressed_time
	if held >= HOLD_THRESHOLD:
		_open_menu()


func _open_menu() -> void:
	_menu_is_open = true
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Warp mouse to screen center so wedge selection starts neutral
	var center := get_viewport().get_visible_rect().size * 0.5
	Input.warp_mouse(center)
	if _radial_menu:
		_radial_menu.open()
	radial_open_requested.emit()


func _close_menu() -> void:
	_menu_is_open = false
	if _radial_menu:
		var picked: int = _radial_menu.close()
		if picked >= 0:
			selected_ability = picked
	Input.mouse_mode = _prev_mouse_mode
	radial_close_requested.emit()


func _use_ability(index: int) -> void:
	match index:
		0: _drukna()
		1: _hrafn()
		2: _gellir()
	ability_used.emit(index, ABILITY_NAMES[index])


# ── Drukna — Extinguish Flames ──────────────────────────────────────────────

func _drukna() -> void:
	var pos := _player.global_position
	var torches: Array[Node] = []
	torches.append_array(get_tree().get_nodes_in_group("torch"))
	if torches.is_empty():
		torches.append_array(get_tree().get_nodes_in_group("flame"))
	for torch in torches:
		if not is_instance_valid(torch):
			continue
		if torch.global_position.distance_to(pos) > DRUKNA_RANGE:
			continue
		# Turn off flame, light, and particles
		for child in torch.get_children():
			if child is OmniLight3D or child is GPUParticles3D:
				child.visible = false
			elif child is MeshInstance3D and child.name == "Flame":
				child.visible = false


# ── Hrafn — Teleport Dash ───────────────────────────────────────────────────

func _hrafn() -> void:
	var cam_pivot := _player.get_node_or_null("CameraPivot") as Node3D
	if not cam_pivot:
		return
	var cam_basis := cam_pivot.global_transform.basis
	var forward := -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var origin := _player.global_position + Vector3(0.0, 0.5, 0.0)
	var destination := origin + forward * HRAFN_RANGE

	# Raycast to avoid teleporting into geometry
	var space := _player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	var result := space.intersect_ray(query)
	if result:
		destination = result.position - forward * 0.5

	destination.y = _player.global_position.y
	_player.global_position = destination


# ── Gellir — Freeze Enemies ─────────────────────────────────────────────────

func _gellir() -> void:
	var pos := _player.global_position
	for bandit in get_tree().get_nodes_in_group("bandit"):
		if not is_instance_valid(bandit):
			continue
		if bandit.global_position.distance_to(pos) > GELLIR_RANGE:
			continue
		if bandit.has_method("freeze"):
			bandit.freeze(GELLIR_DURATION)
