extends BanditState
## DeepStaggerState — First Committed Thrust landed.
## 50% health damage, stumbles backward for 1.5s.

var _timer: float = 0.0

const STAGGER_DURATION := 1.5
const HEALTH_DAMAGE_RATIO := 0.5


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = true
	_timer = 0.0
	# Deal 50% max health damage directly (bypass take_damage to avoid recursive FSM routing)
	var max_hp: float = bandit.max_health if "max_health" in bandit else 100.0
	var dmg := max_hp * HEALTH_DAMAGE_RATIO
	if "_health" in bandit:
		bandit._health = maxf(float(bandit._health) - dmg, 0.0)
	if bandit.has_signal("health_changed"):
		bandit.health_changed.emit(float(bandit._health) if "_health" in bandit else 0.0, max_hp)
	# Lock movement
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(true)
	if bandit.has_method("clear_target"):
		bandit.clear_target()
	bandit.velocity = Vector3.ZERO
	# Stop combat attacks
	var combat := get_combat(bandit)
	if combat and combat.has_method("stop_combat"):
		combat.stop_combat()
	# Play stagger animation
	var anim := get_anim_player(bandit)
	if anim:
		# Use hit react as stagger for now
		var stagger_anim := &"npc_axe/standing_react_large_from_left"
		if anim.has_animation(stagger_anim):
			anim.play(stagger_anim, 0.1)


func exit(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	# Stumble backward
	var visual := get_visual_root(bandit)
	if visual:
		var back_dir := -visual.global_transform.basis.z
		back_dir.y = 0.0
		back_dir = back_dir.normalized()
		bandit.velocity = back_dir * 1.5 * (1.0 - _timer / STAGGER_DURATION)
	if _timer >= STAGGER_DURATION:
		# Player failed the combo timing — bandit recovers
		transition_to(&"alert")
