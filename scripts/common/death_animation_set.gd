class_name DeathAnimationSet
extends Resource
## Directional death animation set.

@export var from_front: StringName = &""
@export var from_back: StringName = &""
@export var from_left: StringName = &""
@export var from_right: StringName = &""
## Optional alternates that are randomly selected when available.
@export var from_left_alts: Array[StringName] = []
@export var from_right_alts: Array[StringName] = []


## Pick the best death animation based on the local-space hit direction.
## Returns the animation name (unresolved — caller should run through AnimationResolver).
func resolve(local_hit_pos: Vector3) -> StringName:
	if local_hit_pos == Vector3.INF:
		# Unknown direction — return first available
		for candidate in [from_front, from_back, from_left, from_right]:
			if not candidate.is_empty():
				return candidate
		return from_front
	if absf(local_hit_pos.x) > absf(local_hit_pos.z):
		if local_hit_pos.x >= 0.0:
			return _pick_with_alts(from_right, from_right_alts)
		return _pick_with_alts(from_left, from_left_alts)
	return from_front if local_hit_pos.z < 0.0 else from_back


func _pick_with_alts(primary: StringName, alts: Array[StringName]) -> StringName:
	if alts.is_empty():
		return primary
	var all: Array[StringName] = [primary]
	all.append_array(alts)
	return all[randi() % all.size()]
