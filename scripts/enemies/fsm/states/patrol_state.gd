extends BanditState
## PatrolState — Baseline unaware behavior.
## Weapon sheathed, walks patrol route or idles at post.
## Delegates actual patrol logic to BanditPatrol node.

func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	var patrol := get_patrol(bandit)
	if patrol and patrol.has_method("resume_patrol"):
		patrol.resume_patrol()
	var combat := get_combat(bandit)
	if combat and combat.has_method("disable_combat"):
		combat.disable_combat()


func exit(bandit: CharacterBody3D) -> void:
	var patrol := get_patrol(bandit)
	if patrol and patrol.has_method("pause_patrol"):
		patrol.pause_patrol()


func physics_process_state(bandit: CharacterBody3D, _delta: float) -> void:
	var brain := get_brain(bandit)
	if not brain:
		return
	# Brain's alert level drives transitions
	if brain.alert_level >= 3:
		transition_to(&"alert")
	elif brain.alert_level >= 1:
		transition_to(&"investigate")
