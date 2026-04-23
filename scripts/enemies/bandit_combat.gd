
extends BaseCombatComponent

## First-pass melee behavior for bandits.
## Owns attack selection, animation playback, hit windows, and weapon/kick hits.

const BanditShared := preload("res://scripts/enemies/bandit_shared.gd")
const PlayerFinder := preload("res://scripts/common/player_finder.gd")

@export_group("Animations")
@export var block_anim: StringName = &"npc_axe/standing_block_idle"
@export var dodge_anim: StringName = &"npc_axe/standing_react_large_from_left"  # TODO: replace with backstep anim
@export var combat_idle_anim: StringName = &"npc_axe/standing_idle"

@export_group("Playback")
@export var action_animation_speed_scale: float = 1.5

@export_group("Unarmed")
@export var unarmed_light_anim: StringName = &"npc_axe/standing_melee_attack_kick_ver"
@export var unarmed_kick_anim: StringName = &"npc_axe/standing_melee_attack_kick_ver"

@export_group("Combat Movement")
@export var combat_walk_forward_anim: StringName = &"npc_axe/standing_walk_forward"
@export var combat_walk_left_anim: StringName = &"npc_axe/standing_walk_left"
@export var combat_walk_right_anim: StringName = &"npc_axe/standing_walk_right"
@export var combat_walk_back_anim: StringName = &"npc_axe/standing_walk_back"

@export_group("Block")
@export var block_counter_delay: float = 0.15  ## Pause before counter-strike after absorbing Committed Thrust

@export_group("Anti-Spam")
@export var proximity_kick_time: float = 3.0  ## Seconds in personal space before kick triggers
@export var proximity_radius: float = 1.8     ## Personal space radius

@export_group("Reactive Defense")
@export var react_chance: float = 0.7           ## Chance to block/kick when player starts a swing
@export var react_delay_min: float = 0.08       ## Min reaction time (seconds)
@export var react_delay_max: float = 0.22       ## Max reaction time
@export var react_kick_chance: float = 0.2      ## Chance to kick instead of block (if close enough)
@export var reactive_block_duration: float = 1.0 ## How long a reactive block lasts
@export var post_attack_recovery: float = 0.35  ## Seconds after own attack before acting again

@export_group("Initiative")
@export var initiative_interval_min: float = 0.75 ## Min idle time before attacking on own
@export var initiative_interval_max: float = 1.6 ## Max idle time before attacking on own

@export_group("Help Call")
@export var help_call_delay: float = 5.0

var _bandit: CharacterBody3D  ## Alias for _owner_body
var _brain: Node
var _player: CharacterBody3D
var _anim_tree: AnimationTree
var _weapon_component = null
var _help_call_timer: float = 0.0
var _help_called: bool = false

# ── Block / Poise / Proximity tracking ────────────────────────────────────────
var _is_blocking: bool = false
var _has_poise: bool = false               ## True during heavy attack wind-up (absorbs light hits)
var _proximity_timer: float = 0.0          ## Time player has been in personal space
var _force_next_heavy: bool = false        ## After kick lands, guarantee follow-up heavy strike
var _block_counter_pending: float = -1.0   ## Countdown to counter-attack after block absorb
var _recovery_timer: float = 0.0           ## Post-attack recovery window

# ── Reactive defense ──────────────────────────────────────────────────────────
var _player_combat: Node = null
var _player_was_attacking: bool = false
var _react_pending: bool = false
var _react_timer: float = 0.0
var _react_action: int = 0                 ## 0=none, 1=block, 2=kick
var _reactive_block_remaining: float = 0.0
var _initiative_timer: float = 0.0


func _setup_combat() -> void:
	_bandit = _owner_body
	_brain = _bandit.get_node_or_null("BanditBrain")
	_player = PlayerFinder.find(_bandit.get_tree())
	var nodes := BanditShared.resolve_visual_nodes(_bandit)
	_anim_player = nodes["anim_player"]
	_anim_tree = nodes["anim_tree"]
	_weapon_component = _resolve_weapon_component()
	if _weapon_component:
		_weapon_hitbox = _weapon_component.get_hitbox()
	_wire_weapon_hitbox()
	target_collision_mask = 1
	_player_combat = _player.get_node_or_null("PlayerCombat") if _player else null
	_initiative_timer = randf_range(initiative_interval_min, initiative_interval_max)


func _init_default_resources() -> void:
	if not light_attack:
		light_attack = AttackData.new()
		light_attack.damage = 14.0
		light_attack.range_m = 3.0
		light_attack.cooldown = 0.4
		light_attack.animation = &"npc_axe/standing_melee_attack_horizontal"
		light_attack.hit_window_start = 0.26
		light_attack.hit_window_end = 0.48
	if not heavy_attack:
		heavy_attack = AttackData.new()
		heavy_attack.damage = 60.0
		heavy_attack.damage_max = 75.0
		heavy_attack.range_m = 3.0
		heavy_attack.cooldown = 0.6
		heavy_attack.animation = &"npc_axe/standing_melee_attack_360_high"
		heavy_attack.hit_window_start = 0.33
		heavy_attack.hit_window_end = 0.62
	if not kick_attack:
		kick_attack = AttackData.new()
		kick_attack.damage = 15.0
		kick_attack.range_m = 2.0
		kick_attack.cooldown = 0.5
		kick_attack.animation = &"npc_axe/standing_melee_attack_kick_ver"
		kick_attack.hit_window_start = 0.28
		kick_attack.hit_window_end = 0.5
	if not hit_reacts:
		hit_reacts = HitReactSet.new()
		hit_reacts.from_left = &"npc_axe/standing_react_large_from_left"
		hit_reacts.from_right = &"npc_axe/standing_react_large_from_right"
	if not unarmed_light_attack:
		unarmed_light_attack = AttackData.new()
		unarmed_light_attack.damage = 8.0
		unarmed_light_attack.range_m = 2.0
		unarmed_light_attack.cooldown = 0.45
		unarmed_light_attack.animation = unarmed_light_anim
		unarmed_light_attack.hit_window_start = 0.22
		unarmed_light_attack.hit_window_end = 0.45
	if not unarmed_kick_attack:
		unarmed_kick_attack = AttackData.new()
		unarmed_kick_attack.damage = 10.0
		unarmed_kick_attack.range_m = 2.0
		unarmed_kick_attack.cooldown = 0.7
		unarmed_kick_attack.animation = unarmed_kick_anim
		unarmed_kick_attack.hit_window_start = 0.25
		unarmed_kick_attack.hit_window_end = 0.5


@export var unarmed_light_attack: AttackData
@export var unarmed_kick_attack: AttackData


func get_weapon_component():
	return _weapon_component


func has_weapon() -> bool:
	return _weapon_component != null and bool(_weapon_component.get("has_weapon"))


func is_unarmed() -> bool:
	return not has_weapon()


func _attack_for(kind: AttackKind) -> AttackData:
	if is_unarmed():
		match kind:
			AttackKind.LIGHT, AttackKind.HEAVY:
				return unarmed_light_attack
			AttackKind.KICK:
				return unarmed_kick_attack
	return super._attack_for(kind)


func _physics_process(delta: float) -> void:
	if _disabled:
		return
	if not _bandit or not _brain or not _player:
		return
	if _bandit.is_dead():
		return
	if _player is ICombatTarget and bool(_player.is_dead()):
		if _current_attack != AttackKind.NONE:
			_finish_attack()
		return

	# ── Proximity timer: track how long the player lingers in personal space ──
	var to_player_vec := _player.global_position - _bandit.global_position
	to_player_vec.y = 0.0
	var player_dist := to_player_vec.length()
	if player_dist <= proximity_radius:
		_proximity_timer += delta
	else:
		_proximity_timer = maxf(_proximity_timer - delta * 2.0, 0.0)

	# ── Block counter-attack pending (short delay then auto-strike) ───────
	if _block_counter_pending >= 0.0:
		_block_counter_pending -= delta
		if _block_counter_pending <= 0.0:
			_block_counter_pending = -1.0
			_end_block()
			_start_attack(AttackKind.HEAVY, _player.global_position)
			return

	# ── Block update ──────────────────────────────────────────────────────
	if _is_blocking:
		_update_block(delta)
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

	# ── Post-attack recovery: can't guard yet ──
	if _recovery_timer > 0.0:
		_recovery_timer -= delta
		if _player and _bandit.has_method("look_toward"):
			_bandit.look_toward(_player.global_position)
		if _recovery_timer > 0.0:
			return

	# ── Reactive defense: detect player starting a swing ──────────────────
	var player_attacking_now := _is_player_attacking()
	if player_attacking_now and not _player_was_attacking and not _react_pending:
		if _brain.alert_level >= 3 and randf() < react_chance:
			var to_p := _player.global_position - _bandit.global_position
			to_p.y = 0.0
			var d := to_p.length()
			if d <= engage_range:
				_react_pending = true
				_react_timer = randf_range(react_delay_min, react_delay_max)
				if d <= kick_attack.range_m and randf() < react_kick_chance:
					_react_action = 2  # kick
				else:
					_react_action = 1  # block
	_player_was_attacking = player_attacking_now

	if _react_pending:
		_react_timer -= delta
		if _react_timer <= 0.0:
			_execute_reaction()
		elif _player and _bandit.has_method("look_toward"):
			_bandit.look_toward(_player.global_position)
		return

	# ── Initiative: attack on own terms ───────────────────────────────────
	if _brain.alert_level >= 3 and _cooldown_remaining <= 0.0:
		var has_visual: bool = _brain.has_method("has_visual_contact") and bool(_brain.has_visual_contact())
		if has_visual:
			var player_pos: Vector3 = _brain.get_player_position()
			if player_pos != Vector3.INF:
				var to_player := player_pos - _bandit.global_position
				to_player.y = 0.0
				var dist := to_player.length()
				if dist <= engage_range and dist > 0.01:
					if _bandit.has_method("look_toward"):
						_bandit.look_toward(player_pos)
					_initiative_timer -= delta
					if _initiative_timer <= 0.0:
						var attack := _choose_attack(dist)
						if attack != AttackKind.NONE:
							_start_attack(attack, player_pos)
							_initiative_timer = randf_range(initiative_interval_min, initiative_interval_max)
						else:
							_initiative_timer = 0.5
					return

	# ── Face player while idle in combat ──────────────────────────────────
	if _brain.alert_level >= 3 and _player and _bandit.has_method("look_toward"):
		_bandit.look_toward(_player.global_position)


func is_busy() -> bool:
	return _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0


func receive_hit(from_world_pos: Vector3 = Vector3.INF) -> void:
	if _disabled or _bandit.is_dead():
		return
	_help_call_timer = 0.0  # Reset: being pressured suppresses calling for help.

	# Blocking — handled by FSM event injectors (on_light_hit / on_heavy_hit).
	# receive_hit is for the *animation interrupt* path only.
	if _is_blocking:
		return  # Block reactions are triggered via on_block_light_hit / on_block_heavy_hit.

	# Poise — heavy attack wind-up absorbs light cuts without interrupting the swing.
	if _has_poise:
		return

	if not _anim_player:
		return
	if _current_attack != AttackKind.NONE:
		_finish_attack()
	var anim := _resolve_hit_react_anim(from_world_pos)
	if anim.is_empty() or not _anim_player.has_animation(anim):
		return
	_begin_action_lock()
	_anim_player.speed_scale = get_action_animation_speed_scale()
	_anim_player.play(anim, 0.06)
	var anim_res := _anim_player.get_animation(anim)
	_react_lock_remaining = (anim_res.length if anim_res else 0.45) / get_action_animation_speed_scale()


func _choose_attack(distance: float) -> AttackKind:
	if is_unarmed():
		if distance <= unarmed_kick_attack.range_m and _proximity_timer >= proximity_kick_time * 0.5:
			_proximity_timer = 0.0
			return AttackKind.KICK
		if distance <= unarmed_light_attack.range_m:
			return AttackKind.LIGHT
		return AttackKind.NONE
	# ── Anti-Spam Kick: player loitering in personal space too long ────────
	if _proximity_timer >= proximity_kick_time and distance <= kick_attack.range_m:
		_proximity_timer = 0.0
		return AttackKind.KICK

	# ── Forced heavy after kick knockdown ─────────────────────────────────
	if _force_next_heavy and distance <= heavy_attack.range_m:
		_force_next_heavy = false
		return AttackKind.HEAVY

	# ── Primary: THE Strike (wild cleave) ─────────────────────────────────
	if distance <= heavy_attack.range_m:
		# Mostly heavy — the bandit's bread and butter.
		# Occasional light for variety.
		if distance <= light_attack.range_m and randf() < 0.15:
			return AttackKind.LIGHT
		return AttackKind.HEAVY

	return AttackKind.NONE


func _start_attack(kind: AttackKind, player_pos: Vector3) -> void:
	# ── Block is a stance, not a strike ───────────────────────────────────
	if kind == AttackKind.BLOCK:
		_start_block()
		return
	var atk := _attack_for(kind)
	var anim := _resolve_attack_anim(atk)
	if anim.is_empty():
		push_warning("[BanditCombat] Missing attack animation on %s" % _bandit.name)
		return
	# Poise: heavy attacks have hyper-armor during wind-up
	_has_poise = (kind == AttackKind.HEAVY)
	_enter_attack_state(kind, anim)
	if _bandit.has_method("clear_target"):
		_bandit.clear_target()
	if _bandit.has_method("look_toward"):
		_bandit.look_toward(player_pos)
	_anim_player.speed_scale = get_action_animation_speed_scale()
	_anim_player.play(anim, 0.08)


func _update_attack(delta: float) -> void:
	_attack_elapsed += delta
	var player_pos: Vector3 = _brain.get_player_position()
	if player_pos != Vector3.INF and _bandit.has_method("look_toward"):
		_bandit.look_toward(player_pos)
	# Poise ends when the active hit window opens (wind-up phase is over)
	if _has_poise:
		var atk := _attack_for(_current_attack)
		if _attack_elapsed >= atk.hit_window_start * _attack_duration:
			_has_poise = false
	_tick_attack_window()
	if _attack_elapsed >= _attack_duration:
		_finish_attack()


func _finish_attack() -> void:
	_clear_attack_state()
	_has_poise = false
	_recovery_timer = post_attack_recovery
	_finish_action_lock()


func _begin_action_lock() -> void:
	if _anim_tree:
		_anim_tree.active = false
	if _bandit.has_method("set_action_locked"):
		_bandit.set_action_locked(true)


func _finish_action_lock() -> void:
	super._finish_action_lock()
	if _anim_player:
		_anim_player.speed_scale = 1.0
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


func _poll_attack_hits() -> void:
	if is_unarmed():
		_deal_kick_hit()
		return
	match _current_attack:
		AttackKind.LIGHT, AttackKind.HEAVY:
			_deal_targeted_weapon_hit()
			_deal_weapon_overlap_hits()
		AttackKind.KICK:
			_deal_kick_hit()


func _deal_targeted_weapon_hit() -> void:
	if not _player or _player in _hit_targets:
		return
	var attack := _attack_for(_current_attack)
	if not attack:
		return
	var to_player := _player.global_position - _bandit.global_position
	to_player.y = 0.0
	if to_player.length() > attack.range_m:
		return
	if not _is_facing_target(to_player):
		return
	_try_hit_target(_player, attack.get_damage())


func _deal_kick_hit() -> void:
	if not _player or _player in _hit_targets:
		return
	var attack := _attack_for(_current_attack)
	if not attack:
		return
	var to_player := _player.global_position - _bandit.global_position
	to_player.y = 0.0
	if to_player.length() > attack.range_m:
		return
	_try_hit_target(_player, attack.get_damage())


func _try_hit_target(body: Node, damage: float) -> void:
	if not body or body == _bandit or body in _hit_targets:
		return
	if body is ICombatTarget and bool(body.is_dead()):
		return
	if _player and body != _player:
		return
	if not (body is ICombatTarget):
		return
	body.take_damage(damage, _bandit.global_position)
	_hit_targets.append(body)
	# ── Kick special: knockdown + stamina wipe + guarantee follow-up heavy ──
	if _current_attack == AttackKind.KICK and body.has_method("on_kicked"):
		body.on_kicked(_bandit.global_position)
		if not is_unarmed():
			_force_next_heavy = true
			_cooldown_remaining = 0.0  # Strike immediately while she's getting up


func _on_combat_stopped() -> void:
	_help_call_timer = 0.0
	_help_called = false
	_is_blocking = false
	_reactive_block_remaining = 0.0
	_has_poise = false
	_block_counter_pending = -1.0
	_react_pending = false
	_react_action = 0
	_player_was_attacking = false
	_initiative_timer = 0.0


# ── Block system ─────────────────────────────────────────────────────────────
## The Desperate Brace: raises axe haft / bracers.
## Light slashes bounce off (player recoil). Committed Thrust absorbed → counter.

func _start_block() -> void:
	if is_unarmed():
		return
	_is_blocking = true
	_reactive_block_remaining = reactive_block_duration / get_action_animation_speed_scale()
	_begin_action_lock()
	var anim := AnimationResolver.resolve(block_anim, _anim_player)
	if _anim_player and not anim.is_empty() and _anim_player.has_animation(anim):
		_anim_player.speed_scale = get_action_animation_speed_scale()
		_anim_player.play(anim, 0.1)


func _update_block(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if _player and _bandit.has_method("look_toward"):
		_bandit.look_toward(_player.global_position)
	_reactive_block_remaining -= delta
	if _reactive_block_remaining <= 0.0:
		_end_block()


func _end_block() -> void:
	_is_blocking = false
	_reactive_block_remaining = 0.0
	_finish_action_lock()


func is_blocking() -> bool:
	return _is_blocking


func has_poise() -> bool:
	return _has_poise


func get_action_animation_speed_scale() -> float:
	return maxf(action_animation_speed_scale, 0.01)


func _is_player_attacking() -> bool:
	if not _player_combat or not _player_combat.has_method("get_current_attack_kind"):
		return false
	return int(_player_combat.get_current_attack_kind()) != 0


func _execute_reaction() -> void:
	_react_pending = false
	_react_timer = 0.0
	var act := _react_action
	_react_action = 0
	if act == 2 and _player:  # Kick
		_start_attack(AttackKind.KICK, _player.global_position)
	elif _player and not is_unarmed():  # Block
		_start_block()


func _resolve_weapon_component():
	var sword := _bandit.find_child("Shortsword", true, false)
	if sword and "has_weapon" in sword and sword.has_method("trigger_iron_rot"):
		return sword
	return null


func on_block_light_hit() -> void:
	## Player's light slash bounced off the block → trigger player recoil.
	if _player and _player.has_method("on_attack_blocked"):
		_player.on_attack_blocked()


func on_block_heavy_hit() -> void:
	## Committed Thrust absorbed by block → zero damage, counter-attack.
	if _player and _player.has_method("on_attack_blocked"):
		_player.on_attack_blocked()
	# Short delay, then devastating counter-strike
	_block_counter_pending = block_counter_delay


func register_light_hit_received() -> void:
	## Called by FSM when a light slash lands (not blocked). No-op with reactive defense.
	pass


func _is_facing_target(to_target: Vector3) -> bool:
	if to_target.length_squared() <= 0.0001:
		return true
	var forward := _bandit.global_transform.basis.z
	var visual_root := _bandit.get_node_or_null("ybot_root") as Node3D
	if visual_root:
		forward = visual_root.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		return true
	var dir := to_target.normalized()
	return forward.normalized().dot(dir) >= cos(deg_to_rad(attack_angle_deg))
