extends Node
## First-pass melee behavior for bandits.
## Owns attack selection, animation playback, hit windows, and weapon/kick hits.

const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")
const PlayerFinder := preload("res://scripts/common/player_finder.gd")

enum AttackKind { NONE, LIGHT, HEAVY, KICK }

@export_group("Animations")
@export var light_attack_anim: StringName = &"npc_axe/standing_melee_attack_horizontal"
@export var heavy_attack_anim: StringName = &"npc_axe/standing_melee_attack_360_high"
@export var kick_attack_anim: StringName = &"npc_axe/standing_melee_attack_kick_ver"
@export var hit_react_left_anim: StringName = &"npc_axe/standing_react_large_from_left"
@export var hit_react_right_anim: StringName = &"npc_axe/standing_react_large_from_right"
@export var combat_idle_anim: StringName = &"npc_axe/standing_idle"

@export_group("Combat Movement")
@export var combat_walk_forward_anim: StringName = &"npc_axe/standing_walk_forward"
@export var combat_walk_left_anim: StringName = &"npc_axe/standing_walk_left"
@export var combat_walk_right_anim: StringName = &"npc_axe/standing_walk_right"
@export var combat_walk_back_anim: StringName = &"npc_axe/standing_walk_back"

@export_group("Ranges")
@export var engage_range: float = 3.0
@export var light_range: float = 2.5
@export var heavy_range: float = 2.8
@export var kick_range: float = 1.6
@export var attack_angle_deg: float = 55.0

@export_group("Damage")
@export var light_damage: float = 14.0
@export var heavy_damage: float = 24.0
@export var kick_damage: float = 8.0

@export_group("Cadence")
@export var light_cooldown: float = 1.05
@export var heavy_cooldown: float = 1.65
@export var kick_cooldown: float = 1.25
@export var heavy_weight: float = 0.28
@export var kick_weight_close: float = 0.4

@export_group("Hit Windows")
@export_range(0.0, 1.0) var light_active_start_norm: float = 0.26
@export_range(0.0, 1.0) var light_active_end_norm: float = 0.48
@export_range(0.0, 1.0) var heavy_active_start_norm: float = 0.33
@export_range(0.0, 1.0) var heavy_active_end_norm: float = 0.62
@export_range(0.0, 1.0) var kick_active_start_norm: float = 0.28
@export_range(0.0, 1.0) var kick_active_end_norm: float = 0.5

@export_group("Hit Detection")
@export var target_collision_mask: int = 1

@export_group("Help Call")
@export var help_call_delay: float = 5.0

var _bandit: CharacterBody3D
var _brain: Node
var _player: CharacterBody3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _weapon_hitbox: Area3D
var _weapon_hit_shape: CollisionShape3D

var _current_attack: AttackKind = AttackKind.NONE
var _attack_elapsed: float = 0.0
var _attack_duration: float = 0.0
var _attack_window_open: bool = false
var _cooldown_remaining: float = 0.0
var _react_lock_remaining: float = 0.0
var _hit_targets: Array[Node] = []
var _disabled: bool = false
var _help_call_timer: float = 0.0
var _help_called: bool = false


func _ready() -> void:
	_bandit = get_parent() as CharacterBody3D
	if not _bandit:
		return
	_brain = _bandit.get_node_or_null("BanditBrain")
	_player = PlayerFinder.find(get_tree())
	var nodes := BanditShared.resolve_visual_nodes(_bandit)
	_anim_player = nodes["anim_player"]
	_anim_tree = nodes["anim_tree"]
	var sword := _bandit.find_child("Shortsword", true, false)
	if sword:
		_weapon_hitbox = sword.find_child("Hitbox", true, false) as Area3D
	if _weapon_hitbox:
		_weapon_hit_shape = _weapon_hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not _weapon_hitbox.body_entered.is_connected(_on_weapon_body_entered):
			_weapon_hitbox.body_entered.connect(_on_weapon_body_entered)
	_set_weapon_window(false)


func _physics_process(delta: float) -> void:
	if _disabled:
		return
	if not _bandit or not _brain or not _player:
		return
	if _bandit.has_method("is_dead") and bool(_bandit.is_dead()):
		return
	if _player.has_method("is_dead") and bool(_player.is_dead()):
		if _current_attack != AttackKind.NONE:
			_finish_attack()
		return

	# Help-call timer: accumulates while in combat, fires once.
	if _brain.alert_level >= 3 and not _help_called:
		_help_call_timer += delta
		if _help_call_timer >= help_call_delay:
			_help_called = true
			if _brain.has_signal("call_for_help"):
				_brain.call_for_help.emit(_bandit, _bandit.global_position)

	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)

	if _react_lock_remaining > 0.0:
		_react_lock_remaining = maxf(_react_lock_remaining - delta, 0.0)
		if _react_lock_remaining <= 0.0:
			_finish_action_lock()
		return

	if _current_attack != AttackKind.NONE:
		_update_attack(delta)
		return

	if _cooldown_remaining > 0.0:
		return
	var has_visual: bool = _brain.has_method("has_visual_contact") and bool(_brain.has_visual_contact())
	if _brain.alert_level < 3 and not has_visual:
		return

	var player_pos: Vector3 = _brain.get_player_position()
	if player_pos == Vector3.INF:
		return
	var to_player := player_pos - _bandit.global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > engage_range or dist <= 0.01:
		return
	if _bandit.has_method("look_toward"):
		_bandit.look_toward(player_pos)

	var attack := _choose_attack(dist)
	if attack != AttackKind.NONE:
		_start_attack(attack, player_pos)


func is_busy() -> bool:
	return _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0


func receive_hit(from_world_pos: Vector3 = Vector3.INF) -> void:
	if _disabled or (_bandit.has_method("is_dead") and bool(_bandit.is_dead())):
		return
	_help_call_timer = 0.0  # Reset: being pressured suppresses calling for help.
	if not _anim_player:
		return
	if _current_attack != AttackKind.NONE:
		_finish_attack()
	var anim := _resolve_hit_react(from_world_pos)
	if anim.is_empty() or not _anim_player.has_animation(anim):
		return
	_begin_action_lock()
	_anim_player.play(anim, 0.06)
	var anim_res := _anim_player.get_animation(anim)
	_react_lock_remaining = anim_res.length if anim_res else 0.45


func _choose_attack(distance: float) -> AttackKind:
	if distance <= kick_range and randf() < kick_weight_close:
		return AttackKind.KICK
	var can_light := distance <= light_range
	var can_heavy := distance <= heavy_range
	if can_light and can_heavy:
		return AttackKind.HEAVY if randf() < heavy_weight else AttackKind.LIGHT
	if can_light:
		return AttackKind.LIGHT
	if can_heavy:
		return AttackKind.HEAVY
	return AttackKind.NONE


func _start_attack(kind: AttackKind, player_pos: Vector3) -> void:
	if not _anim_player:
		return
	var anim := _get_attack_animation(kind)
	if anim.is_empty() or not _anim_player.has_animation(anim):
		push_warning("[BanditCombat] Missing attack animation '%s' on %s" % [anim, _bandit.name])
		return
	_current_attack = kind
	_attack_elapsed = 0.0
	_attack_window_open = false
	_hit_targets.clear()
	_begin_action_lock()
	if _bandit.has_method("clear_target"):
		_bandit.clear_target()
	if _bandit.has_method("look_toward"):
		_bandit.look_toward(player_pos)
	_anim_player.play(anim, 0.08)
	var anim_res := _anim_player.get_animation(anim)
	_attack_duration = maxf(anim_res.length if anim_res else 0.5, 0.1)


func _update_attack(delta: float) -> void:
	_attack_elapsed += delta
	var player_pos: Vector3 = _brain.get_player_position()
	if player_pos != Vector3.INF and _bandit.has_method("look_toward"):
		_bandit.look_toward(player_pos)

	var start_t := _get_attack_window_start(_current_attack) * _attack_duration
	var end_t := _get_attack_window_end(_current_attack) * _attack_duration
	var should_open := _attack_elapsed >= start_t and _attack_elapsed <= end_t
	if should_open != _attack_window_open:
		_set_attack_window(should_open)
	if _attack_window_open:
		_poll_attack_hits()

	if _attack_elapsed >= _attack_duration:
		_finish_attack()


func _finish_attack() -> void:
	_set_attack_window(false)
	_cooldown_remaining = _get_attack_cooldown(_current_attack)
	_current_attack = AttackKind.NONE
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	_hit_targets.clear()
	_finish_action_lock()


func _begin_action_lock() -> void:
	if _anim_tree:
		_anim_tree.active = false
	if _bandit.has_method("set_action_locked"):
		_bandit.set_action_locked(true)


func _finish_action_lock() -> void:
	_set_weapon_window(false)
	_react_lock_remaining = 0.0
	if _bandit.has_method("set_action_locked"):
		_bandit.set_action_locked(false)
	# In combat: pre-set Combat state BEFORE reactivating so the tree
	# doesn't flash the old state (Idle) for a frame.
	var in_combat: bool = _brain != null and _brain.alert_level >= 3
	if in_combat and _anim_tree:
		var playback: AnimationNodeStateMachinePlayback = _anim_tree["parameters/playback"]
		if playback:
			playback.start("Combat", true)
		_anim_tree.active = true
		return
	var is_moving_now := false
	if _bandit.has_method("is_moving_now"):
		is_moving_now = bool(_bandit.is_moving_now())
	if is_moving_now:
		if _anim_tree:
			_anim_tree.active = true
	elif _bandit.has_method("refresh_idle_animation"):
		_bandit.refresh_idle_animation()


func _set_attack_window(active: bool) -> void:
	_attack_window_open = active
	var use_weapon := _current_attack == AttackKind.LIGHT or _current_attack == AttackKind.HEAVY
	_set_weapon_window(active and use_weapon)


func _set_weapon_window(active: bool) -> void:
	if not _weapon_hitbox:
		return
	_weapon_hitbox.monitoring = active
	_weapon_hitbox.collision_mask = target_collision_mask if active else 0
	if _weapon_hit_shape:
		_weapon_hit_shape.disabled = not active


func _poll_attack_hits() -> void:
	match _current_attack:
		AttackKind.LIGHT, AttackKind.HEAVY:
			_deal_weapon_overlap_hits()
		AttackKind.KICK:
			_deal_kick_hit()


func _deal_weapon_overlap_hits() -> void:
	if not _weapon_hitbox:
		return
	for body in _weapon_hitbox.get_overlapping_bodies():
		_try_hit_target(body, _get_attack_damage(_current_attack))


func _deal_kick_hit() -> void:
	if not _player or _player in _hit_targets:
		return
	var to_player := _player.global_position - _bandit.global_position
	to_player.y = 0.0
	if to_player.length() > kick_range:
		return
	_try_hit_target(_player, kick_damage)


func _try_hit_target(body: Node, damage: float) -> void:
	if not body or body == _bandit or body in _hit_targets:
		return
	if body.has_method("is_dead") and bool(body.is_dead()):
		return
	if _player and body != _player:
		return
	if not body.has_method("take_damage"):
		return
	body.take_damage(damage, _bandit.global_position)
	_hit_targets.append(body)


func stop_combat() -> void:
	_disabled = true
	if _current_attack != AttackKind.NONE:
		_set_attack_window(false)
	_current_attack = AttackKind.NONE
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	_cooldown_remaining = 0.0
	_hit_targets.clear()
	_help_call_timer = 0.0
	_help_called = false
	_finish_action_lock()
	set_physics_process(false)


func _on_weapon_body_entered(body: Node) -> void:
	if not _attack_window_open:
		return
	_try_hit_target(body, _get_attack_damage(_current_attack))


func _is_facing_target(to_target: Vector3) -> bool:
	if to_target.length_squared() <= 0.0001:
		return true
	var forward := _bandit.global_transform.basis * Vector3.FORWARD
	var visual_root := _bandit.get_node_or_null("ybot_root") as Node3D
	if visual_root:
		forward = visual_root.global_transform.basis * Vector3.FORWARD
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return true
	var dir := to_target.normalized()
	return forward.normalized().dot(dir) >= cos(deg_to_rad(attack_angle_deg))


func _get_attack_animation(kind: AttackKind) -> StringName:
	match kind:
		AttackKind.LIGHT:
			return _resolve_animation_name(light_attack_anim)
		AttackKind.HEAVY:
			return _resolve_animation_name(heavy_attack_anim)
		AttackKind.KICK:
			return _resolve_animation_name(kick_attack_anim)
		_:
			return StringName()


func _resolve_hit_react(from_world_pos: Vector3) -> StringName:
	var anim := hit_react_left_anim
	if from_world_pos != Vector3.INF:
		var local := _bandit.to_local(from_world_pos)
		anim = hit_react_right_anim if local.x >= 0.0 else hit_react_left_anim
	return _resolve_animation_name(anim)


func _resolve_animation_name(raw_name: StringName) -> StringName:
	if not _anim_player:
		return raw_name
	var raw := str(raw_name)
	var candidates: Array[String] = [raw]
	if raw.contains("npc/axe/"):
		candidates.append(raw.replace("npc/axe/", "npc_axe/"))
	if raw.contains("/"):
		candidates.append(raw.replace("/", "_"))
	if raw.begins_with("npc_axe_"):
		candidates.append(raw.replace("npc_axe_", "npc_axe/"))
	if raw.contains(" "):
		candidates.append(raw.replace(" ", "_"))
	if raw.contains(" from ") or raw.contains(" left") or raw.contains(" right"):
		var normalized := raw.replace(" from ", "_from_")
		normalized = normalized.replace(" left", "_left")
		normalized = normalized.replace(" right", "_right")
		candidates.append(normalized)
		if normalized.begins_with("npc_axe_"):
			candidates.append(normalized.replace("npc_axe_", "npc_axe/"))
	for candidate in candidates:
		if _anim_player.has_animation(StringName(candidate)):
			return StringName(candidate)

	var target_key := _normalize_anim_key(raw)
	var best_suffix := StringName()
	for anim_name in _anim_player.get_animation_list():
		var anim_text := str(anim_name)
		var anim_key := _normalize_anim_key(anim_text)
		if anim_key == target_key:
			return anim_name
		if anim_key.ends_with(target_key) or target_key.ends_with(anim_key):
			best_suffix = anim_name
	if not best_suffix.is_empty():
		return best_suffix

	for anim_name in _anim_player.get_animation_list():
		var anim_key := _normalize_anim_key(str(anim_name))
		if target_key.contains("meleeattackhorizontal") and anim_key.contains("meleeattack") and anim_key.contains("horizontal"):
			return anim_name
		if target_key.contains("360high") and anim_key.contains("360"):
			return anim_name
		if target_key.contains("kick") and anim_key.contains("kick"):
			return anim_name
		if target_key.contains("reactlarge") and anim_key.contains("react") and anim_key.contains("large"):
			if target_key.contains("left") and anim_key.contains("left"):
				return anim_name
			if target_key.contains("right") and anim_key.contains("right"):
				return anim_name

	return StringName(candidates[-1])


func _normalize_anim_key(value: String) -> String:
	var lowered := value.to_lower()
	var result := ""
	for ch in lowered:
		if ch >= "a" and ch <= "z":
			result += ch
		elif ch >= "0" and ch <= "9":
			result += ch
	return result


func _get_attack_damage(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_damage
		AttackKind.HEAVY:
			return heavy_damage
		AttackKind.KICK:
			return kick_damage
		_:
			return 0.0


func _get_attack_cooldown(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_cooldown
		AttackKind.HEAVY:
			return heavy_cooldown
		AttackKind.KICK:
			return kick_cooldown
		_:
			return 0.0


func _get_attack_window_start(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_active_start_norm
		AttackKind.HEAVY:
			return heavy_active_start_norm
		AttackKind.KICK:
			return kick_active_start_norm
		_:
			return 0.0


func _get_attack_window_end(kind: AttackKind) -> float:
	match kind:
		AttackKind.LIGHT:
			return light_active_end_norm
		AttackKind.HEAVY:
			return heavy_active_end_norm
		AttackKind.KICK:
			return kick_active_end_norm
		_:
			return 0.0
