class_name HitReactSet
extends Resource
## Directional hit reaction animation set.

@export var from_left: StringName = &""
@export var from_right: StringName = &""
@export var from_front: StringName = &""   ## Gut / default
@export var block_react: StringName = &""


## Pick the best hit react animation based on the local-space hit direction.
func resolve(local_hit_pos: Vector3) -> StringName:
	if local_hit_pos == Vector3.INF:
		return from_front if not from_front.is_empty() else from_left
	if absf(local_hit_pos.x) > absf(local_hit_pos.z):
		return from_right if local_hit_pos.x >= 0.0 else from_left
	return from_front if not from_front.is_empty() else from_left
