extends Node
## Detects downed bandits within sight range and raises the alarm.
## Attach as a child of the bandit CharacterBody3D alongside BanditPerception.

@export var detection_range: float = 12.0
@export var check_interval: float = 1.0

var _timer: float = 0.0
var _bandit: CharacterBody3D
var _perception: Node


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	_perception = _bandit.get_node_or_null("BanditPerception")


func _physics_process(delta: float) -> void:
	if not _bandit or not _perception:
		return
	_timer += delta
	if _timer < check_interval:
		return
	_timer = 0.0

	for node in get_tree().get_nodes_in_group("bandit"):
		if node == _bandit:
			continue
		if not _is_downed(node):
			continue
		var dist := _bandit.global_position.distance_to(node.global_position)
		if dist > detection_range:
			continue
		# LOS check — can we see the body?
		var eyes := _bandit.global_position + Vector3(0.0, 1.5, 0.0)
		var body_pos: Vector3 = node.global_position + Vector3(0.0, 0.5, 0.0)
		var space := _bandit.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(eyes, body_pos)
		query.collision_mask = 1
		query.exclude = [_bandit.get_rid(), node.get_rid()]
		var result := space.intersect_ray(query)
		if result:
			continue
		# Body found — go to full alert
		if _perception.alert_level < 3:
			_perception.suspicion = 1.0
			_perception.alert_level = 3
			_perception.last_known_positions.append(node.global_position)
			_perception.alert_level_changed.emit(3)
			_perception.entered_combat.emit()
			_perception._call_nearby_bandits()
		return


func _is_downed(node: Node) -> bool:
	if node.has_method("is_dead") and node.is_dead():
		return true
	if "is_dead" in node and node.is_dead:
		return true
	if node.has_method("is_downed") and node.is_downed():
		return true
	var controller := node as CharacterBody3D
	if controller and controller.has_node("BanditPerception"):
		var perc := controller.get_node("BanditPerception")
		if "is_dead" in perc and perc.is_dead:
			return true
	return false
