extends Node3D
class_name WeaponComponent

signal iron_rot_triggered(source_pos: Vector3)

@export var is_metal: bool = true
@export var iron_rot_noise_radius: float = 12.0
@export var rust_sound: AudioStream

var has_weapon: bool = true
var _hitbox: Area3D


func _ready() -> void:
	_hitbox = get_node_or_null("Hitbox") as Area3D
	if not has_weapon:
		_disable_weapon_function()


func get_hitbox() -> Area3D:
	return _hitbox


func trigger_iron_rot(source_pos: Vector3 = Vector3.INF) -> bool:
	if not is_metal:
		play_iron_rot_fizzle()
		return false
	if not has_weapon:
		return false
	has_weapon = false
	_disable_weapon_function()
	_spawn_rust_burst(false)
	_play_rust_audio()
	_emit_noise_disturbance()
	iron_rot_triggered.emit(source_pos)
	var owner_body := _find_owner_body()
	if owner_body:
		if owner_body.has_method("on_weapon_iron_rot"):
			owner_body.on_weapon_iron_rot(self, source_pos)
			return true
		var fsm := owner_body.get_node_or_null("BanditFSM")
		if fsm and fsm.has_method("on_disarmed"):
			fsm.on_disarmed()
	return true


func play_iron_rot_fizzle() -> void:
	_spawn_rust_burst(true)


func _disable_weapon_function() -> void:
	if _hitbox:
		_hitbox.monitoring = false
		_hitbox.collision_mask = 0
		var shape := _hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape:
			shape.disabled = true
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false


func _spawn_rust_burst(is_fizzle: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 14 if is_fizzle else 36
	particles.lifetime = 0.35 if is_fizzle else 0.8
	particles.draw_pass_1 = _create_rust_particle_mesh(is_fizzle)
	particles.process_material = _create_rust_particle_material(is_fizzle)
	particles.top_level = true
	get_tree().current_scene.add_child(particles)
	particles.global_position = global_position
	particles.finished.connect(particles.queue_free)
	particles.emitting = true


func _create_rust_particle_mesh(is_fizzle: bool) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * (0.05 if is_fizzle else 0.09)
	return mesh


func _create_rust_particle_material(is_fizzle: bool) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = 0.4 if is_fizzle else 1.2
	material.initial_velocity_max = 1.1 if is_fizzle else 2.8
	material.gravity = Vector3(0.0, -2.4, 0.0)
	material.damping_min = 1.5
	material.damping_max = 3.4
	material.scale_min = 0.04
	material.scale_max = 0.08 if is_fizzle else 0.16
	material.color = Color(0.75, 0.26, 0.08, 0.8) if is_fizzle else Color(0.62, 0.23, 0.06, 0.95)
	return material


func _play_rust_audio() -> void:
	if not rust_sound:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = rust_sound
	player.top_level = true
	get_tree().current_scene.add_child(player)
	player.global_position = global_position
	player.finished.connect(player.queue_free)
	player.play()


func _emit_noise_disturbance() -> void:
	for node in get_tree().get_nodes_in_group("bandit"):
		var bandit := node as CharacterBody3D
		if not bandit:
			continue
		if bandit.global_position.distance_to(global_position) > iron_rot_noise_radius:
			continue
		var brain := bandit.get_node_or_null("BanditBrain")
		if brain and brain.has_method("emit_heard_noise"):
			brain.emit_heard_noise(global_position)


func _find_owner_body() -> CharacterBody3D:
	var node: Node = self
	while node:
		node = node.get_parent()
		if node is CharacterBody3D:
			return node as CharacterBody3D
	return null