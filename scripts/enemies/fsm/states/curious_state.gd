extends BanditState
## CuriousState — Lured by Gull-Epli (fool's gold).
## Calmly walks to the shiny object and picks it up. Weapon remains sheathed.
## Back is exposed during the pickup animation.

var _lure_position: Vector3 = Vector3.INF
var _arrived: bool = false
var _pickup_timer: float = 0.0

const PICKUP_DURATION := 2.5  ## Seconds to play pickup animation
const ARRIVE_RADIUS := 1.5


func set_lure_position(pos: Vector3) -> void:
	_lure_position = pos


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	_arrived = false
	_pickup_timer = 0.0
	if _lure_position != Vector3.INF and bandit.has_method("set_target_position"):
		bandit.set_target_position(_lure_position)
		if "_target_speed" in bandit:
			bandit._target_speed = 2.5  # Calm walk


func exit(_bandit: CharacterBody3D) -> void:
	_lure_position = Vector3.INF
	_arrived = false
	_pickup_timer = 0.0


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	var brain := get_brain(bandit)
	if brain and brain.alert_level >= 3:
		transition_to(&"alert")
		return

	if not _arrived:
		if _lure_position == Vector3.INF:
			transition_to(&"patrol")
			return
		var dist := bandit.global_position.distance_to(_lure_position)
		if dist < ARRIVE_RADIUS:
			_arrived = true
			if bandit.has_method("clear_target"):
				bandit.clear_target()
			# TODO: play pickup animation
	else:
		_pickup_timer += delta
		if _pickup_timer >= PICKUP_DURATION:
			transition_to(&"patrol")
