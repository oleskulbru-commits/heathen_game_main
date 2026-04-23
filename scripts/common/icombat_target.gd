class_name ICombatTarget
extends CharacterBody3D
## Shared combat-target contract for actors that can take damage and be queried
## by combat, HUD, and AI systems. Concrete controllers override these stubs.


func is_dead() -> bool:
	return false


func take_damage(_amount: float, _from_world_pos: Vector3 = Vector3.INF) -> void:
	pass


func get_health() -> float:
	return 0.0


func get_stamina() -> float:
	return 0.0


func heal(_amount: float) -> void:
	pass


func drain_stamina(_amount: float) -> void:
	pass
