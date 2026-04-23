extends BanditState
## RagdollState — Dead. Terminal state.
## AI FSM stops processing. Skeleton transitions to physics ragdoll.
## Becomes a lootable corpse.

func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	# Mark dead
	if "_is_dead" in bandit:
		bandit._is_dead = true
	# Emit died signal
	if bandit.has_signal("died"):
		bandit.died.emit()
	# Stop all AI
	bandit.velocity = Vector3.ZERO
	if bandit.has_method("clear_target"):
		bandit.clear_target()
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(true)
	# Disable all AI child nodes
	for node_name in ["BanditBrain", "BanditPerception", "BanditTorchSearch",
			"BanditPatrol", "BanditBodyDetector", "BanditDebugVision", "BanditCombat"]:
		var node := bandit.get_node_or_null(node_name)
		if node:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	# Remove from bandit group so other systems stop targeting us
	if bandit.is_in_group("bandit"):
		bandit.remove_from_group("bandit")
	# Disable AnimationTree so ragdoll can take over
	var visual := get_visual_root(bandit)
	if visual:
		var anim_tree := visual.get_node_or_null("AnimationTree") as AnimationTree
		if anim_tree:
			anim_tree.active = false
	# TODO: enable physical bones for ragdoll
	# TODO: add to "lootable" group
	bandit.add_to_group("corpse")
	# Stop the FSM itself
	if machine:
		machine.set_process(false)
		machine.set_physics_process(false)


func exit(_bandit: CharacterBody3D) -> void:
	pass  # Terminal — never exits


func physics_process_state(_bandit: CharacterBody3D, _delta: float) -> void:
	pass  # Terminal — no processing
