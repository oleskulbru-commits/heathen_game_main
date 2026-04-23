extends BanditState
## DodgeState — Sloppy backstep when the player's combo timing lapses.
## Panicked, off-balance scramble backward to create 2m of space.
## Transitions back to AlertState with weapon raised.

var _timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.BACK

const DODGE_DURATION := 0.7   ## Seconds for the backstep animation
const DODGE_DISTANCE := 2.0   ## Meters traveled backward
const DODGE_SPEED := DODGE_DISTANCE / DODGE_DURATION


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = false  # He's escaping — no free stabs
	_timer = 0.0
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(true)
	# Compute backward direction from visual root facing
	var visual := get_visual_root(bandit)
	if visual:
		_dodge_dir = -visual.global_transform.basis.z
	else:
		_dodge_dir = -bandit.global_transform.basis.z
	_dodge_dir.y = 0.0
	_dodge_dir = _dodge_dir.normalized()
	# Stop combat module from attacking during dodge
	var combat := get_combat(bandit)
	if combat and combat.has_method("stop_combat"):
		combat.stop_combat()
	# Play backstep animation
	var anim := get_anim_player(bandit)
	if anim:
		var dodge_anim := &"npc_axe/standing_react_large_from_left"  # TODO: replace with proper backstep
		if combat and "dodge_anim" in combat:
			dodge_anim = combat.dodge_anim
		if anim.has_animation(dodge_anim):
			anim.play(dodge_anim, 0.08)


func exit(bandit: CharacterBody3D) -> void:
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	# Scramble backward — decelerating
	var speed_factor := 1.0 - (_timer / DODGE_DURATION)
	bandit.velocity = _dodge_dir * DODGE_SPEED * maxf(speed_factor, 0.0)
	bandit.move_and_slide()
	if _timer >= DODGE_DURATION:
		bandit.velocity = Vector3.ZERO
		transition_to(&"alert")
