extends RefCounted
class_name BanditState
## Base class for all bandit FSM states.
## Each state owns enter/exit/process logic and declares its own transitions.

## Set true in subclasses whose state makes the bandit vulnerable to a
## Committed Thrust (heavy attack) takedown.
var is_vulnerable: bool = false

## Reference to the owning state machine — set by BanditStateMachine.
var machine: Node = null


func enter(_bandit: CharacterBody3D) -> void:
	pass


func exit(_bandit: CharacterBody3D) -> void:
	pass


func process_state(_bandit: CharacterBody3D, _delta: float) -> void:
	pass


func physics_process_state(_bandit: CharacterBody3D, _delta: float) -> void:
	pass


# ── Helpers available to all states ──────────────────────────────────────────

func get_brain(bandit: CharacterBody3D) -> Node:
	return bandit.get_node_or_null("BanditBrain")


func get_combat(bandit: CharacterBody3D) -> Node:
	return bandit.get_node_or_null("BanditCombat")


func get_patrol(bandit: CharacterBody3D) -> Node:
	return bandit.get_node_or_null("BanditPatrol")


func get_perception(bandit: CharacterBody3D) -> Node:
	return bandit.get_node_or_null("BanditPerception")


func get_anim_player(bandit: CharacterBody3D) -> AnimationPlayer:
	var vr := bandit.get_node_or_null("ybot_root")
	if vr:
		return vr.get_node_or_null("AnimationPlayer") as AnimationPlayer
	return null


func get_visual_root(bandit: CharacterBody3D) -> Node3D:
	return bandit.get_node_or_null("ybot_root") as Node3D


func transition_to(state_name: StringName) -> void:
	if machine and machine.has_method("change_state"):
		machine.change_state(state_name)
