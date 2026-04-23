extends SpellBase
class_name SpellFull

const AnimationResolverUtil := preload("res://scripts/common/animation_resolver.gd")

enum FullPhase { NONE, TARGETING, CASTING, RECOVERY }
enum CastMode { NONE, PULSE, HEX }

@export var stamina_cost: float = 25.0
@export var cast_duration: float = 0.4
@export var recovery_duration: float = 0.16
@export var pulse_release_delay: float = 0.18
@export var hex_release_delay: float = 0.3
@export var pulse_range: float = 3.5
@export_range(1.0, 180.0) var pulse_spread_deg: float = 60.0
@export var max_hex_range: float = 15.0
@export var cast_locomotion_multiplier: float = 0.5
@export_flags_3d_physics var target_collision_mask: int = 3
@export var cast_anim: StringName = &"npc_axe/standing_melee_attack_backhand"
@export var cast_sound: AudioStream

var _phase: FullPhase = FullPhase.NONE
var _cast_mode: CastMode = CastMode.NONE
var _elapsed: float = 0.0
var _effect_fired: bool = false
var _target_enemy: CharacterBody3D
var _target_weapon = null
var _target_valid: bool = false
var _target_point: Vector3 = Vector3.ZERO
var _target_preview_root: Node3D
var _target_preview_mesh: MeshInstance3D
var _target_preview_material: StandardMaterial3D
var _hand_vfx: GPUParticles3D
var _mesh_root: Node3D
var _anim_player: AnimationPlayer
var _pulse_valid_targets: Array = []
var _pulse_invalid_targets: Array = []


func _init() -> void:
	spell_name = "Fúll"
	verb_name = "Fúll"
	description = "Panic pulse or focused iron-rot hex"
	slot_type = 0
	cooldown = 4.0
	hugr_cost = 0.2
	catalyst_name = "Iron filings + grave ash"


func is_active() -> bool:
	return _phase != FullPhase.NONE


func can_start_targeted(player: CharacterBody3D) -> bool:
	if _phase != FullPhase.NONE or not is_ready() or not player:
		return false
	if player.has_method("is_dead") and bool(player.is_dead()):
		return false
	if player.has_method("is_in_combat_mode") and bool(player.is_in_combat_mode()):
		return false
	return _can_pay_stamina(player)


func cast(player: CharacterBody3D) -> bool:
	if _phase != FullPhase.NONE or not is_ready() or not player:
		return false
	if player.has_method("is_dead") and bool(player.is_dead()):
		return false
	if not _can_pay_stamina(player):
		return false
	_cache_player_refs(player)
	_collect_pulse_targets(player)
	if not super.cast(player):
		return false
	_consume_stamina(player)
	_begin_cast(player, CastMode.PULSE)
	return true


func start_targeted(player: CharacterBody3D) -> bool:
	if not can_start_targeted(player):
		return false
	_cache_player_refs(player)
	_ensure_target_preview(player)
	_update_target_preview(player)
	_phase = FullPhase.TARGETING
	_cast_mode = CastMode.NONE
	_elapsed = 0.0
	return true


func confirm_targeted(player: CharacterBody3D) -> bool:
	if _phase != FullPhase.TARGETING:
		return false
	if not _target_weapon or not is_instance_valid(_target_weapon) or not _target_valid:
		if _target_weapon and is_instance_valid(_target_weapon):
			_target_weapon.play_iron_rot_fizzle()
		cancel(player)
		return false
	if not _can_pay_stamina(player):
		cancel(player)
		return false
	if not super.cast(player):
		cancel(player)
		return false
	_consume_stamina(player)
	_cleanup_target_preview()
	_begin_cast(player, CastMode.HEX)
	return true


func physics_update(player: CharacterBody3D, _delta: float) -> void:
	if _phase == FullPhase.NONE:
		return
	_elapsed += _delta
	match _phase:
		FullPhase.TARGETING:
			_tick_targeting(player)
		FullPhase.CASTING:
			_tick_casting(player)
		FullPhase.RECOVERY:
			_tick_recovery(player)


func cancel(player: CharacterBody3D) -> void:
	_cleanup_target_preview()
	_stop_hand_vfx()
	_clear_locomotion_override(player)
	_phase = FullPhase.NONE
	_cast_mode = CastMode.NONE
	_elapsed = 0.0
	_effect_fired = false
	_target_enemy = null
	_target_weapon = null
	_target_valid = false
	_target_point = Vector3.ZERO
	_pulse_valid_targets.clear()
	_pulse_invalid_targets.clear()


func _begin_cast(player: CharacterBody3D, cast_mode: CastMode) -> void:
	_phase = FullPhase.CASTING
	_cast_mode = cast_mode
	_elapsed = 0.0
	_effect_fired = false
	_apply_cast_animation(player)
	_apply_locomotion_override(player)
	_start_hand_vfx(player)
	_play_cast_sound(player)


func _tick_targeting(player: CharacterBody3D) -> void:
	if player.has_method("is_dead") and bool(player.is_dead()):
		cancel(player)
		return
	if not Input.is_action_pressed("focus"):
		cancel(player)
		return
	_update_target_preview(player)


func _tick_casting(player: CharacterBody3D) -> void:
	if player.has_method("is_dead") and bool(player.is_dead()):
		cancel(player)
		return
	var effect_delay := pulse_release_delay if _cast_mode == CastMode.PULSE else hex_release_delay
	if not _effect_fired and _elapsed >= effect_delay:
		_effect_fired = true
		if _cast_mode == CastMode.PULSE:
			_fire_pulse(player)
		else:
			_fire_hex(player)
	if _elapsed >= cast_duration:
		_phase = FullPhase.RECOVERY
		_elapsed = 0.0
		_clear_locomotion_override(player)
		_stop_hand_vfx()


func _tick_recovery(player: CharacterBody3D) -> void:
	if _elapsed >= recovery_duration:
		cancel(player)


func _fire_pulse(player: CharacterBody3D) -> void:
	for weapon in _pulse_valid_targets:
		if weapon and is_instance_valid(weapon):
			weapon.trigger_iron_rot(player.global_position)
	for weapon in _pulse_invalid_targets:
		if weapon and is_instance_valid(weapon):
			weapon.play_iron_rot_fizzle()
	_pulse_valid_targets.clear()
	_pulse_invalid_targets.clear()


func _fire_hex(player: CharacterBody3D) -> void:
	if _target_weapon and is_instance_valid(_target_weapon):
		if _target_valid:
			_target_weapon.trigger_iron_rot(player.global_position)
		else:
			_target_weapon.play_iron_rot_fizzle()
	_target_enemy = null
	_target_weapon = null
	_target_valid = false


func _collect_pulse_targets(player: CharacterBody3D) -> void:
	_pulse_valid_targets.clear()
	_pulse_invalid_targets.clear()
	var forward := _get_camera_forward_flat(player)
	if forward.length_squared() <= 0.0001:
		forward = -player.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
	var min_dot := cos(deg_to_rad(pulse_spread_deg * 0.5))
	for node in player.get_tree().get_nodes_in_group("bandit"):
		var enemy := node as CharacterBody3D
		if not enemy or not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and bool(enemy.is_dead()):
			continue
		var to_enemy := enemy.global_position - player.global_position
		to_enemy.y = 0.0
		var dist := to_enemy.length()
		if dist <= 0.01 or dist > pulse_range:
			continue
		if forward.dot(to_enemy / dist) < min_dot:
			continue
		var weapon = _get_weapon_component(enemy)
		if not weapon or not is_instance_valid(weapon) or not weapon.has_weapon:
			continue
		if weapon.is_metal:
			_pulse_valid_targets.append(weapon)
		else:
			_pulse_invalid_targets.append(weapon)


func _update_target_preview(player: CharacterBody3D) -> void:
	var ray_hit := _raycast_target(player)
	if ray_hit.is_empty():
		_target_enemy = null
		_target_weapon = null
		_target_valid = false
		_target_point = Vector3.ZERO
		_set_preview_visible(false)
		return
	var enemy := _find_enemy_from_collider(ray_hit.get("collider"))
	if not enemy:
		_target_enemy = null
		_target_weapon = null
		_target_valid = false
		_target_point = Vector3.ZERO
		_set_preview_visible(false)
		return
	var weapon = _get_weapon_component(enemy)
	if not weapon:
		_target_enemy = enemy
		_target_weapon = null
		_target_valid = false
		_target_point = enemy.global_position + Vector3(0.0, 1.1, 0.0)
		_update_preview_transform(Color(0.82, 0.14, 0.12, 0.95))
		return
	_target_enemy = enemy
	_target_weapon = weapon
	_target_valid = weapon.has_weapon and weapon.is_metal
	_target_point = weapon.global_position
	_update_preview_transform(Color(0.66, 0.28, 0.08, 0.95) if _target_valid else Color(0.82, 0.14, 0.12, 0.95))


func _raycast_target(player: CharacterBody3D) -> Dictionary:
	var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if not camera:
		return {}
	var origin := camera.global_position
	var end := origin + (-camera.global_transform.basis.z) * max_hex_range
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = target_collision_mask
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func _find_enemy_from_collider(collider: Variant) -> CharacterBody3D:
	var node := collider as Node
	while node:
		if node is CharacterBody3D and node.is_in_group("bandit"):
			return node as CharacterBody3D
		node = node.get_parent()
	return null


func _get_weapon_component(enemy: CharacterBody3D):
	if enemy.has_method("get_weapon_component"):
		var weapon = enemy.get_weapon_component()
		if weapon and "has_weapon" in weapon and weapon.has_method("trigger_iron_rot"):
			return weapon
	var combat := enemy.get_node_or_null("BanditCombat")
	if combat and combat.has_method("get_weapon_component"):
		var combat_weapon = combat.get_weapon_component()
		if combat_weapon and "has_weapon" in combat_weapon and combat_weapon.has_method("trigger_iron_rot"):
			return combat_weapon
	var weapon_node := enemy.find_child("Shortsword", true, false)
	if weapon_node and "has_weapon" in weapon_node and weapon_node.has_method("trigger_iron_rot"):
		return weapon_node
	return null


func _ensure_target_preview(player: CharacterBody3D) -> void:
	if _target_preview_root:
		return
	_target_preview_root = Node3D.new()
	_target_preview_root.name = "FullTargetPreview"
	_target_preview_root.top_level = true
	player.get_tree().current_scene.add_child(_target_preview_root)
	_target_preview_mesh = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.18
	mesh.bottom_radius = 0.18
	mesh.height = 0.03
	_target_preview_mesh.mesh = mesh
	_target_preview_material = StandardMaterial3D.new()
	_target_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_target_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_preview_material.albedo_color = Color(0.66, 0.28, 0.08, 0.95)
	_target_preview_material.emission_enabled = true
	_target_preview_material.emission = _target_preview_material.albedo_color
	_target_preview_material.emission_energy_multiplier = 0.9
	_target_preview_mesh.material_override = _target_preview_material
	_target_preview_root.add_child(_target_preview_mesh)


func _update_preview_transform(color: Color) -> void:
	if not _target_preview_root or not _target_preview_material:
		return
	_target_preview_root.global_position = _target_point + Vector3(0.0, 0.05, 0.0)
	_target_preview_root.global_rotation = Vector3.ZERO
	_target_preview_material.albedo_color = color
	_target_preview_material.emission = color
	_set_preview_visible(true)


func _set_preview_visible(visible: bool) -> void:
	if _target_preview_root:
		_target_preview_root.visible = visible


func _cleanup_target_preview() -> void:
	if _target_preview_root:
		_target_preview_root.queue_free()
	_target_preview_root = null
	_target_preview_mesh = null
	_target_preview_material = null


func _apply_cast_animation(player: CharacterBody3D) -> void:
	var xbot := player.get_node_or_null("xbot_root") as Node3D
	if not xbot or not xbot.has_method("play_action") or not _anim_player:
		return
	var resolved := AnimationResolverUtil.resolve(cast_anim, _anim_player)
	if resolved.is_empty() or not _anim_player.has_animation(resolved):
		return
	xbot.play_action(resolved, 0.1, 0.1)


func _start_hand_vfx(player: CharacterBody3D) -> void:
	_stop_hand_vfx()
	var hand_attachment := player.get_node_or_null("xbot_root/Armature/Skeleton3D/RightHandAttachment") as Node3D
	if not hand_attachment:
		return
	_hand_vfx = GPUParticles3D.new()
	_hand_vfx.one_shot = false
	_hand_vfx.amount = 14
	_hand_vfx.lifetime = 0.4
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.06, 0.06)
	_hand_vfx.draw_pass_1 = mesh
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0.0, 0.4, 0.0)
	material.spread = 35.0
	material.initial_velocity_min = 0.15
	material.initial_velocity_max = 0.45
	material.gravity = Vector3(0.0, 0.25, 0.0)
	material.scale_min = 0.03
	material.scale_max = 0.08
	material.color = Color(0.78, 0.31, 0.08, 0.65)
	_hand_vfx.process_material = material
	hand_attachment.add_child(_hand_vfx)
	_hand_vfx.emitting = true


func _stop_hand_vfx() -> void:
	if _hand_vfx:
		_hand_vfx.queue_free()
	_hand_vfx = null


func _play_cast_sound(player: CharacterBody3D) -> void:
	if not cast_sound:
		return
	var sound_player := AudioStreamPlayer3D.new()
	sound_player.stream = cast_sound
	sound_player.top_level = true
	player.get_tree().current_scene.add_child(sound_player)
	sound_player.global_position = player.global_position + Vector3(0.0, 1.2, 0.0)
	sound_player.finished.connect(sound_player.queue_free)
	sound_player.play()


func _cache_player_refs(player: CharacterBody3D) -> void:
	_mesh_root = player.get_node_or_null("xbot_root") as Node3D
	_anim_player = player.get_node_or_null("xbot_root/AnimationPlayer") as AnimationPlayer


func _apply_locomotion_override(player: CharacterBody3D) -> void:
	if player and player.has_method("set_external_locomotion_modifier"):
		player.set_external_locomotion_modifier(cast_locomotion_multiplier)


func _clear_locomotion_override(player: CharacterBody3D) -> void:
	if player and player.has_method("clear_external_locomotion_modifier"):
		player.clear_external_locomotion_modifier()


func _can_pay_stamina(player: CharacterBody3D) -> bool:
	return player and player.has_method("get_stamina") and float(player.get_stamina()) >= stamina_cost


func _consume_stamina(player: CharacterBody3D) -> void:
	if player and player.has_method("drain_stamina"):
		player.drain_stamina(stamina_cost)


func _get_camera_forward_flat(player: CharacterBody3D) -> Vector3:
	var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if camera:
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.0001:
			return forward.normalized()
	return Vector3.ZERO
