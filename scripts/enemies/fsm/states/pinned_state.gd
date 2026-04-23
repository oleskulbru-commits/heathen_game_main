extends BanditState
## PinnedState — Gandr (Shadow Bind) rooted in place.
## Velocity locked to zero, can still rotate and attack if player walks in front.

var _timer: float = 0.0

const PIN_DURATION := 5.0  ## Magic timer — tune per spell


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = true
	_timer = 0.0
	# Stop movement but do NOT action-lock (he can still swing)
	if bandit.has_method("clear_target"):
		bandit.clear_target()
	bandit.velocity = Vector3.ZERO


func exit(_bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	# Combat module stays enabled — it handles attacks


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	# Force velocity to zero every frame — he's pinned
	bandit.velocity.x = 0.0
	bandit.velocity.z = 0.0
	# Still rotate toward the player
	var brain := get_brain(bandit)
	if brain and brain.has_method("get_player_position"):
		var player_pos: Vector3 = brain.get_player_position()
		if player_pos != Vector3.INF and bandit.has_method("look_toward"):
			bandit.look_toward(player_pos)
	if _timer >= PIN_DURATION:
		transition_to(&"alert")
