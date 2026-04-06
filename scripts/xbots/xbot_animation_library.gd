extends Node3D
## Root script for the ybot/xbot visual model.
## Exposes animation_player and animation_tree references for controllers.

@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree") as AnimationTree