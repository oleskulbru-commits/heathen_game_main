extends BanditState
## FleeingState — Mara (Nightmare Dust) broke morale.
## Drops weapon, reverses pathfinding, sprints to safety.

var _timer: float = 0.0
var _flee_target: Vector3 = Vector3.INF

const FLEE_SPEED := 7.0
const MAX_FLEE_TIME := 12.0
const SAFE_ZONE_RADIUS := 3.0


func enter(bandit: CharacterBody3D) -> void:
	is_vulnerable = true
	_timer = 0.0
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(true)
	var combat := get_combat(bandit)
	if combat and combat.has_method("stop_combat"):
		combat.stop_combat()
	# Drop weapon
	var weapon := bandit.find_child("Shortsword", true, false)
	if not weapon:
		weapon = bandit.find_child("Axe", true, false)
	if weapon:
		weapon.queue_free()
	# Flee to home position (spawn point) or away from the player
	_flee_target = bandit.home_position if "home_position" in bandit else bandit.global_position + Vector3(0, 0, 30)
	if bandit.has_method("set_action_locked"):
		bandit.set_action_locked(false)  # Needs to be able to move
	if "_target_speed" in bandit:
		bandit._target_speed = FLEE_SPEED
	if bandit.has_method("set_target_position"):
		bandit.set_target_position(_flee_target)
	# Set emotional state on brain
	var brain := get_brain(bandit)
	if brain and brain.has_method("_set_emotion"):
		brain._set_emotion(brain.Emotion.TERRIFIED)
	# TODO: play terrified sprint animation


func exit(_bandit: CharacterBody3D) -> void:
	is_vulnerable = false


func physics_process_state(bandit: CharacterBody3D, delta: float) -> void:
	_timer += delta
	# Check if we reached safety
	if _flee_target != Vector3.INF:
		var dist := bandit.global_position.distance_to(_flee_target)
		if dist < SAFE_ZONE_RADIUS:
			# Reached safety — despawn or go idle
			_despawn(bandit)
			return
	if _timer >= MAX_FLEE_TIME:
		_despawn(bandit)


func _despawn(bandit: CharacterBody3D) -> void:
	bandit.velocity = Vector3.ZERO
	if bandit.has_method("clear_target"):
		bandit.clear_target()
	# Remove from combat groups, disable processing
	bandit.set_process(false)
	bandit.set_physics_process(false)
	bandit.visible = false
	bandit.collision_layer = 0
	bandit.collision_mask = 0
