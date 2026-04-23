extends BanditState
## FatallyWoundedState — Final Committed Thrust landed.
## Health at zero, half speed, blood trail, loud screaming that alerts camp.
## Can be silenced by: light slash, Kafna magic, or 5s bleed-out timer.

var _timer: float = 0.0

const BLEEDOUT_DURATION := 5.0
const WOUNDED_SPEED := 1.5


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = false  # No longer vulnerable — already dying
	_timer = 0.0
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)  # Can still stumble/move
	var combat := get_combat(bandit)
	if combat and combat.has_method("disable_combat"):
		combat.disable_combat()
	if bandit.has_method("clear_target"):
		bandit.clear_target()
	# Set health to zero
	if "_health" in bandit:
		bandit._health = 0.0
	# Drop weapon
	var weapon := bandit.find_child("Shortsword", true, false)
	if not weapon:
		weapon = bandit.find_child("Axe", true, false)
	if weapon:
		weapon.queue_free()
	# TODO: play fatally wounded stumble animation
	# TODO: start screaming audio that alerts nearby bandits
	# TODO: spawn blood trail particles


func exit(_bandit: CharacterBody3D) -> void:
	pass


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	# Stumble away at half speed
	var visual := get_visual_root(bandit)
	if visual:
		var forward := visual.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		bandit.velocity = forward * WOUNDED_SPEED * (1.0 - _timer / BLEEDOUT_DURATION)
	# Alert nearby bandits with screaming
	if int(_timer * 2.0) % 2 == 0:  # Every 0.5s
		_alert_nearby(bandit)
	if _timer >= BLEEDOUT_DURATION:
		transition_to(&"ragdoll")


func _alert_nearby(bandit: CharacterBody3D) -> void:
	for node in bandit.get_tree().get_nodes_in_group("bandit"):
		if node == bandit:
			continue
		if not node is CharacterBody3D:
			continue
		var dist := bandit.global_position.distance_to(node.global_position)
		if dist < 20.0:
			var their_brain := node.get_node_or_null("BanditBrain")
			if their_brain and their_brain.has_method("force_combat"):
				their_brain.force_combat(bandit.global_position)
