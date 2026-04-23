extends BanditState
## InvestigateState — Suspicious, heard a noise or decoy.
## Draws weapon, hurries to the noise coordinate, sweeps vision cone.

var _investigate_pos: Vector3 = Vector3.INF
var _search_timer: float = 0.0

const SEARCH_DURATION := 6.0
const ARRIVE_RADIUS := 2.5


func set_investigate_position(pos: Vector3) -> void:
	_investigate_pos = pos


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = false
	_search_timer = 0.0
	if "_target_speed" in bandit:
		bandit._target_speed = 4.5  # Hurried walk
	if _investigate_pos != Vector3.INF and bandit.has_method("set_target_position"):
		bandit.set_target_position(_investigate_pos)


func exit(_bandit: CharacterBody3D) -> void:
	_investigate_pos = Vector3.INF
	_search_timer = 0.0


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	var brain := get_brain(bandit)
	if brain and brain.alert_level >= 3:
		transition_to(&"alert")
		return

	# Check if we've arrived at the noise source
	if _investigate_pos != Vector3.INF:
		var dist := bandit.global_position.distance_to(_investigate_pos)
		if dist < ARRIVE_RADIUS:
			_search_timer += delta
			if bandit.has_method("clear_target"):
				bandit.clear_target()
			# Look around while searching
			if bandit.has_method("look_toward"):
				# Sweep in a circle
				var sweep_angle := _search_timer * 1.2
				var sweep_dir := Vector3(sin(sweep_angle), 0.0, cos(sweep_angle)) * 3.0
				bandit.look_toward(bandit.global_position + sweep_dir)
	else:
		_search_timer += delta

	if _search_timer >= SEARCH_DURATION:
		transition_to(&"patrol")
