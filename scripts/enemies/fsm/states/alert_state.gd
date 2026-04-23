extends BanditState
## AlertState — Active combat aggro.
## Paths aggressively toward the player, executes attacks when in range.
## Delegates pursuit to bandit_controller and attacks to bandit_combat.

const VISION_LOSS_GRACE := 2.5  ## Seconds without visual contact before de-escalating
var _vision_lost_timer: float = 0.0

func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = true
	_vision_lost_timer = 0.0
	# Enable combat module
	var combat := get_combat(bandit)
	if combat and combat.has_method("enable_combat"):
		combat.enable_combat()
	# Set combat speed
	if "_target_speed" in bandit:
		bandit._target_speed = 6.0
	# Ensure brain is at combat alert — only update position if we can actually see the player
	var brain := get_brain(bandit)
	if brain and brain.alert_level < 3:
		var has_visual: bool = brain.has_method("has_visual_contact") and bool(brain.has_visual_contact())
		if has_visual and brain.has_method("force_combat"):
			var player_pos: Vector3 = brain.get_player_position() if brain.has_method("get_player_position") else Vector3.INF
			brain.force_combat(player_pos)
		elif brain.has_method("force_combat"):
			# Escalate alert level without overwriting last-known position with omniscient data
			brain.suspicion = 1.0
			brain.alert_level = 3
			brain.alert_level_changed.emit(3)


func exit(_bandit: CharacterBody3D) -> void:
	pass


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	var brain := get_brain(bandit)
	if not brain:
		return
	# If alert level drops, de-escalate
	if brain.alert_level < 3:
		if brain.alert_level >= 1:
			transition_to(&"investigate")
		else:
			transition_to(&"patrol")
		return
	# Track vision loss — if we can't see the player, eventually de-escalate to investigate
	var has_visual: bool = brain.has_method("has_visual_contact") and bool(brain.has_visual_contact())
	if has_visual:
		_vision_lost_timer = 0.0
	else:
		_vision_lost_timer += delta
		if _vision_lost_timer >= VISION_LOSS_GRACE:
			transition_to(&"investigate")
