extends BanditState
## OverextendedState — Player dodged a heavy attack.
## Axe stuck in ground/wood, 2-second weapon-yank animation.

var _timer: float = 0.0

const OVEREXTENDED_DURATION := 2.0


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = true
	_timer = 0.0
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(true)
	if bandit.has_method("clear_target"):
		bandit.clear_target()
	bandit.velocity = Vector3.ZERO
	var combat := get_combat(bandit)
	if combat and combat.has_method("stop_combat"):
		combat.stop_combat()
	# TODO: play weapon-stuck yank animation


func exit(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)


func physics_process_state(_bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	if _timer >= OVEREXTENDED_DURATION:
		transition_to(&"alert")
