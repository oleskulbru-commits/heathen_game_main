extends Area3D

@export var prompt_name := "The Quiet Spot"


func _ready() -> void:
	add_to_group("quiet_spot")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func get_prompt_name() -> String:
	return prompt_name


func _on_body_entered(body: Node) -> void:
	if body != null and body.has_method("set_near_quiet_spot"):
		body.set_near_quiet_spot(self)


func _on_body_exited(body: Node) -> void:
	if body != null and body.has_method("set_near_quiet_spot"):
		body.set_near_quiet_spot(null)