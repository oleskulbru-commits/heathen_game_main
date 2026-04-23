class_name DodgeData
extends Resource
## Data-driven definition for a dodge / dive move.

@export var distance: float = 3.4
@export_range(0.0, 1.0) var iframe_start_norm: float = 0.08
@export_range(0.0, 1.0) var iframe_end_norm: float = 0.72
@export_range(0.0, 1.0) var early_exit_norm: float = 0.7
@export var forward_anim: StringName = &""
@export var backward_anim: StringName = &""
@export var left_anim: StringName = &""
@export var right_anim: StringName = &""
