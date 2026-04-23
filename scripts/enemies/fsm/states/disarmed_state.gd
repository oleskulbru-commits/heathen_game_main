extends BanditState
	## DisarmedState — Fúll (Iron Rot) destroyed the weapon.
	## 2-second shock window, then returns to AlertState where combat logic
	## already falls back to unarmed behavior when no weapon remains.

var _timer: float = 0.0

const SHOCK_DURATION := 2.0


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
	var anim := get_anim_player(bandit)
	if anim and anim.has_animation(&"npc_axe/standing_react_large_from_right"):
		anim.play(&"npc_axe/standing_react_large_from_right", 0.06)


func exit(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	# Stumble backward during shock
	if _timer < SHOCK_DURATION:
		var visual := get_visual_root(bandit)
		if visual:
			var back_dir := -visual.global_transform.basis.z
			back_dir.y = 0.0
			bandit.velocity = back_dir.normalized() * 1.0 * (1.0 - _timer / SHOCK_DURATION)
	if _timer >= SHOCK_DURATION:
		transition_to(&"alert")
