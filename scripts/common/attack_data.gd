class_name AttackData
extends Resource
## Data-driven definition for a single attack type.
## Shared between player and bandit combat components.

@export var damage: float = 15.0
@export var damage_max: float = -1.0  ## If > 0, damage is randomized between damage..damage_max
@export var range_m: float = 2.5
@export var cooldown: float = 0.3
@export var stamina_cost: float = 8.0
@export var animation: StringName = &""
@export_range(0.0, 1.0) var hit_window_start: float = 0.25
@export_range(0.0, 1.0) var hit_window_end: float = 0.50
@export_range(0.0, 1.0) var early_exit_norm: float = 0.65


func get_damage() -> float:
	if damage_max > 0.0:
		return randf_range(damage, damage_max)
	return damage
