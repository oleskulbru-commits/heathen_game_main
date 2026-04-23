extends BanditState
## MicroStaggerState — Light slash landed during DeepStagger.
## Brief 0.5s flinch that resets the heavy-attack stagger window.

var _timer: float = 0.0

const FLINCH_DURATION := 0.5


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = true
	_timer = 0.0
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(true)
	bandit.velocity = Vector3.ZERO
	# Play flinch animation
	var anim := get_anim_player(bandit)
	if anim:
		var flinch_anim := &"npc_axe/standing_react_large_from_right"
		if anim.has_animation(flinch_anim):
			anim.play(flinch_anim, 0.06)


func exit(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)


func physics_process_state(_bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	if _timer >= FLINCH_DURATION:
		# Flinch over — return to combat (deep_stagger deals 50% HP on enter,
		# so looping back into it would be lethal after two light hits).
		transition_to(&"alert")
