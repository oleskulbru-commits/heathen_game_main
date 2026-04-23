extends BanditState
## LostTargetState — The baffled window after Hrafn teleport.
## Target vanished. Bandit plays a confused looking animation while scanning.
## Completely vulnerable during the looking animation. When it ends, bandit
## turns toward the player's last known position and re-engages.

var _timer: float = 0.0
var _looking_anim_playing: bool = false
var _looking_anim_duration: float = 0.0

const BAFFLED_DURATION := 2.5
const PRIMARY_LOOKING_ANIM: StringName = &"npc_axe/standing_idle_looking_ver_002"
const LOOKING_ANIM_FALLBACKS: Array[StringName] = [
	&"npc_axe/standing_idle_looking_ver_001",
	&"npc_axe/standing_idle_looking_ver",
]


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = true
	_timer = 0.0
	_looking_anim_playing = false
	_looking_anim_duration = 0.0
	# Lock movement — bandit cannot chase
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(true)
	if bandit.has_method("clear_look_toward"):
		bandit.clear_look_toward()
	if bandit.has_method("clear_target"):
		bandit.clear_target()
	bandit.velocity = Vector3.ZERO
	# Stop any in-progress attack
	var combat := get_combat(bandit)
	if combat and combat.has_method("stop_combat"):
		combat.stop_combat()
	# Play a looking/scanning animation
	var anim_player := _get_anim_player(bandit)
	if anim_player:
		var anim_name: StringName = PRIMARY_LOOKING_ANIM
		if not anim_player.has_animation(anim_name):
			for fallback in LOOKING_ANIM_FALLBACKS:
				if anim_player.has_animation(fallback):
					anim_name = fallback
					break
		if anim_player.has_animation(anim_name):
			anim_player.play(anim_name, 0.15)
			var anim_res := anim_player.get_animation(anim_name)
			_looking_anim_duration = anim_res.length if anim_res else 1.5
			_looking_anim_playing = true


func exit(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta

	# While looking animation is playing, bandit is frozen and vulnerable
	if _looking_anim_playing:
		if _timer >= _looking_anim_duration:
			_looking_anim_playing = false
			is_vulnerable = false
			# Now turn toward the player's last known position
			var brain := get_brain(bandit)
			if brain and brain.has_method("get_player_position"):
				var player_pos: Vector3 = brain.get_player_position()
				if player_pos != Vector3.INF and bandit.has_method("look_toward"):
					bandit.look_toward(player_pos)
		return

	# Post-look: slowly turn, then transition
	var visual := get_visual_root(bandit)
	if visual:
		var turn_speed := 1.5
		visual.rotation.y += turn_speed * delta

	if _timer >= BAFFLED_DURATION:
		var brain := get_brain(bandit)
		if brain and brain.has_method("has_visual_contact") and brain.has_visual_contact():
			transition_to(&"alert")
		else:
			transition_to(&"investigate")


func _get_anim_player(bandit: CharacterBody3D) -> AnimationPlayer:
	var visual := get_visual_root(bandit)
	if not visual:
		return null
	return visual.get_node_or_null("AnimationPlayer") as AnimationPlayer
