extends Node
class_name BanditStateMachine
## Finite State Machine for bandit AI.
## Manages a dictionary of BanditState instances keyed by StringName.
## Drives enter/exit/process/physics_process on the active state.

signal state_changed(old_state: StringName, new_state: StringName)

var current_state: BanditState = null
var current_state_name: StringName = &""
var _states: Dictionary = {}  # StringName -> BanditState
var _bandit: CharacterBody3D


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	if not _bandit:
		push_error("[BanditFSM] Must be a child of a CharacterBody3D")
		return
	_register_states()
	# Start in patrol
	if _states.has(&"patrol"):
		change_state(&"patrol")


func _process(delta: float) -> void:
	if current_state and _bandit:
		current_state.process_state(_bandit, delta)


func _physics_process(delta: float) -> void:
	if current_state and _bandit:
		current_state.physics_process_state(_bandit, delta)


# ── State registration ───────────────────────────────────────────────────────

func _register_states() -> void:
	_add_state(&"patrol", preload("res://scripts/enemies/fsm/states/patrol_state.gd").new())
	_add_state(&"curious", preload("res://scripts/enemies/fsm/states/curious_state.gd").new())
	_add_state(&"investigate", preload("res://scripts/enemies/fsm/states/investigate_state.gd").new())
	_add_state(&"alert", preload("res://scripts/enemies/fsm/states/alert_state.gd").new())
	_add_state(&"deep_stagger", preload("res://scripts/enemies/fsm/states/deep_stagger_state.gd").new())
	_add_state(&"micro_stagger", preload("res://scripts/enemies/fsm/states/micro_stagger_state.gd").new())
	_add_state(&"lost_target", preload("res://scripts/enemies/fsm/states/lost_target_state.gd").new())
	_add_state(&"blinded", preload("res://scripts/enemies/fsm/states/blinded_state.gd").new())
	_add_state(&"overextended", preload("res://scripts/enemies/fsm/states/overextended_state.gd").new())
	_add_state(&"disarmed", preload("res://scripts/enemies/fsm/states/disarmed_state.gd").new())
	_add_state(&"pinned", preload("res://scripts/enemies/fsm/states/pinned_state.gd").new())
	_add_state(&"fleeing", preload("res://scripts/enemies/fsm/states/fleeing_state.gd").new())
	_add_state(&"fatally_wounded", preload("res://scripts/enemies/fsm/states/fatally_wounded_state.gd").new())
	_add_state(&"ragdoll", preload("res://scripts/enemies/fsm/states/ragdoll_state.gd").new())
	_add_state(&"dodge", preload("res://scripts/enemies/fsm/states/dodge_state.gd").new())


func _add_state(state_name: StringName, state: BanditState) -> void:
	state.machine = self
	_states[state_name] = state


# ── State transitions ────────────────────────────────────────────────────────

func change_state(new_state_name: StringName) -> void:
	if not _states.has(new_state_name):
		push_error("[BanditFSM] Unknown state: %s" % new_state_name)
		return
	if new_state_name == current_state_name:
		return
	var old_name := current_state_name
	if current_state:
		current_state.exit(_bandit)
	current_state_name = new_state_name
	current_state = _states[new_state_name]
	current_state.enter(_bandit)
	state_changed.emit(old_name, new_state_name)


func get_state(state_name: StringName) -> BanditState:
	return _states.get(state_name)


func is_in_state(state_name: StringName) -> bool:
	return current_state_name == state_name


func is_vulnerable() -> bool:
	return current_state != null and current_state.is_vulnerable


# ── External event injection ─────────────────────────────────────────────────
## These are called by bandit_brain, combat, or spells to force transitions.

func on_player_spotted() -> void:
	## Brain detected the player visually — enter alert/combat.
	if current_state_name in [&"ragdoll", &"fatally_wounded", &"lost_target"]:
		return
	change_state(&"alert")


func on_noise_heard(source_pos: Vector3) -> void:
	## Heard a sound — investigate unless in a higher-priority state.
	if current_state_name in [&"alert", &"deep_stagger", &"micro_stagger",
			&"lost_target", &"blinded", &"overextended", &"disarmed",
			&"pinned", &"fleeing", &"fatally_wounded", &"ragdoll"]:
		return
	var state := _states.get(&"investigate") as BanditState
	if state and state.has_method("set_investigate_position"):
		state.set_investigate_position(source_pos)
	change_state(&"investigate")


func on_lure_spotted(_lure_pos: Vector3) -> void:
	## Saw a Gull-Epli (fool's gold) lure.
	if current_state_name in [&"alert", &"deep_stagger", &"micro_stagger",
			&"lost_target", &"blinded", &"overextended", &"disarmed",
			&"pinned", &"fleeing", &"fatally_wounded", &"ragdoll"]:
		return
	var state := _states.get(&"curious") as BanditState
	if state and state.has_method("set_lure_position"):
		state.set_lure_position(_lure_pos)
	change_state(&"curious")


func on_heavy_hit() -> void:
	## Committed Thrust landed — only deals damage if currently vulnerable.
	if current_state_name == &"fatally_wounded":
		return
	# Block absorb: Committed Thrust against a blocking bandit = absorbed + counter
	var combat := _bandit.get_node_or_null("BanditCombat")
	if combat and combat.has_method("is_blocking") and combat.is_blocking():
		combat.on_block_heavy_hit()
		return
	if current_state_name == &"deep_stagger":
		change_state(&"fatally_wounded")
	elif is_vulnerable():
		change_state(&"deep_stagger")


func on_light_hit() -> void:
	## Light slash landed.
	var combat := _bandit.get_node_or_null("BanditCombat")
	# Poise: heavy attack wind-up absorbs light hits without interrupting
	if combat and combat.has_method("has_poise") and combat.has_poise():
		return
	# Block: light slash bounces off
	if combat and combat.has_method("is_blocking") and combat.is_blocking():
		combat.on_block_light_hit()
		return
	# Feed light hit count to combat for block decision
	if combat and combat.has_method("register_light_hit_received"):
		combat.register_light_hit_received()
	if current_state_name == &"deep_stagger":
		change_state(&"micro_stagger")


func on_dodge_success() -> void:
	## Player dodged the bandit's heavy attack.
	if current_state_name == &"alert":
		change_state(&"overextended")


func on_blinded() -> void:
	## Soot Pot or Ash Decoy explosion.
	if current_state_name in [&"fatally_wounded", &"ragdoll"]:
		return
	change_state(&"blinded")


func on_disarmed() -> void:
	## Fúll (Iron Rot) destroyed the weapon.
	if current_state_name in [&"fatally_wounded", &"ragdoll"]:
		return
	change_state(&"disarmed")


func on_pinned() -> void:
	## Gandr (Shadow Bind) rooted in place.
	if current_state_name in [&"fatally_wounded", &"ragdoll"]:
		return
	change_state(&"pinned")


func on_terrified() -> void:
	## Mara (Nightmare Dust) — morale break.
	if current_state_name in [&"fatally_wounded", &"ragdoll"]:
		return
	change_state(&"fleeing")


func on_hrafn_dash_behind(player_pos: Vector3) -> void:
	## Player used Hrafn and landed behind the bandit.
	## Only triggers LostTarget if within backstab range.
	if current_state_name in [&"fatally_wounded", &"ragdoll"]:
		return
	if not _bandit:
		return
	var dist := _bandit.global_position.distance_to(player_pos)
	if dist < 3.0:
		change_state(&"lost_target")
	else:
		# Too far away — just re-alert
		change_state(&"alert")


func on_silenced() -> void:
	## Kafna magic or final slash on fatally wounded.
	if current_state_name == &"fatally_wounded":
		change_state(&"ragdoll")


func on_killed() -> void:
	change_state(&"ragdoll")
