class_name BaseCombatComponent
extends Node
## Shared melee combat foundation for player and NPC combatants.
## Owns attack state, weapon hitbox, hit window timing, and animation resolution.
## Subclasses add input routing (player) or AI decision-making (enemies).

const AnimationResolverUtil := preload("res://scripts/common/animation_resolver.gd")

enum AttackKind { NONE, LIGHT, HEAVY, KICK, BLOCK }

# ── Shared Exports ────────────────────────────────────────────────────────────

@export_group("Attacks")
@export var light_attack: AttackData
@export var heavy_attack: AttackData
@export var kick_attack: AttackData

@export_group("Hit Reacts")
@export var hit_reacts: HitReactSet

@export_group("Combat")
@export var engage_range: float = 3.5
@export var attack_angle_deg: float = 55.0
@export var target_collision_mask: int = 2

# ── Shared State ──────────────────────────────────────────────────────────────

var _owner_body: CharacterBody3D
var _anim_player: AnimationPlayer
## var _anim_tree: AnimationTree  # UNUSED
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


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_init_default_resources()
	_owner_body = get_parent() as CharacterBody3D
	if _owner_body:
		_setup_combat()


## Override to set default AttackData / HitReactSet when none are exported.
func _init_default_resources() -> void:
	pass


## Override to wire _anim_player, _weapon_hitbox, and subclass-specific refs.
func _setup_combat() -> void:
	pass


## Call from _setup_combat() after assigning _weapon_hitbox.
func _wire_weapon_hitbox() -> void:
	if _weapon_hitbox:
		_weapon_hit_shape = _weapon_hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if not _weapon_hitbox.body_entered.is_connected(_on_weapon_body_entered):
			_weapon_hitbox.body_entered.connect(_on_weapon_body_entered)
	_set_weapon_window(false)


# ── Query ─────────────────────────────────────────────────────────────────────

func _attack_for(kind: AttackKind) -> AttackData:
	match kind:
		AttackKind.LIGHT:
			return light_attack
		AttackKind.HEAVY:
			return heavy_attack
		AttackKind.KICK:
			return kick_attack
		_:
			return null


func get_current_attack_kind() -> AttackKind:
	return _current_attack


func is_busy() -> bool:
	return _current_attack != AttackKind.NONE or _react_lock_remaining > 0.0


func is_blocking() -> bool:
	return false


func is_combat_enabled() -> bool:
	return not _disabled


func set_combat_enabled(enabled: bool) -> void:
	if enabled:
		enable_combat()
	else:
		disable_combat()


func enable_combat() -> void:
	_disabled = false
	set_physics_process(true)


func disable_combat() -> void:
	stop_combat()


# ── Weapon Window ─────────────────────────────────────────────────────────────

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


# ── Hit Detection ─────────────────────────────────────────────────────────────

func _deal_weapon_overlap_hits() -> void:
	if not _weapon_hitbox:
		return
	var atk := _attack_for(_current_attack)
	for body in _weapon_hitbox.get_overlapping_bodies():
		_try_hit_target(body, atk.get_damage())


func _on_weapon_body_entered(body: Node) -> void:
	if not _attack_window_open:
		return
	var atk := _attack_for(_current_attack)
	_try_hit_target(body, atk.get_damage() if atk else 0.0)


## Override to apply damage and register the hit.
func _try_hit_target(_body: Node, _damage: float) -> void:
	pass


## Override to route weapon vs kick hit detection.
func _poll_attack_hits() -> void:
	pass


# ── Attack Lifecycle Helpers ──────────────────────────────────────────────────

## Resolve and validate an attack animation. Returns empty StringName on failure.
func _resolve_attack_anim(atk: AttackData) -> StringName:
	if not _anim_player or not atk:
		return &""
	var anim := AnimationResolverUtil.resolve(atk.animation, _anim_player)
	if anim.is_empty() or not _anim_player.has_animation(anim):
		return &""
	return anim


## Transition into attacking state. Call after subclass pre-attack setup.
func _enter_attack_state(kind: AttackKind, anim: StringName) -> void:
	_current_attack = kind
	_attack_elapsed = 0.0
	_attack_window_open = false
	_hit_targets.clear()
	_begin_action_lock()
	var anim_res := _anim_player.get_animation(anim)
	_attack_duration = maxf(anim_res.length if anim_res else 0.5, 0.1)


## Evaluate hit window timing and poll for hits. Call each _update_attack tick.
func _tick_attack_window() -> void:
	var atk := _attack_for(_current_attack)
	var start_t := atk.hit_window_start * _attack_duration
	var end_t := atk.hit_window_end * _attack_duration
	var should_open := _attack_elapsed >= start_t and _attack_elapsed <= end_t
	if should_open != _attack_window_open:
		_set_attack_window(should_open)
	if _attack_window_open:
		_poll_attack_hits()


## Clear attack state after a swing completes. Call at the start of subclass _finish_attack.
func _clear_attack_state() -> void:
	_set_attack_window(false)
	var atk := _attack_for(_current_attack)
	_cooldown_remaining = atk.cooldown if atk else 0.0
	_current_attack = AttackKind.NONE
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	_hit_targets.clear()


# ── Hit React Helper ─────────────────────────────────────────────────────────

## Resolve a directional hit-react animation from world hit position.
func _resolve_hit_react_anim(from_world_pos: Vector3) -> StringName:
	var local_pos := _owner_body.to_local(from_world_pos) if from_world_pos != Vector3.INF else Vector3.INF
	var raw_anim := hit_reacts.resolve(local_pos)
	return AnimationResolverUtil.resolve(raw_anim, _anim_player)


# ── Action Lock ───────────────────────────────────────────────────────────────

## Override with subclass-specific locking (e.g. AnimationTree toggle).
func _begin_action_lock() -> void:
	pass


## Override with subclass-specific unlocking. Call super() first.
func _finish_action_lock() -> void:
	_set_weapon_window(false)
	_react_lock_remaining = 0.0


# ── Stop ──────────────────────────────────────────────────────────────────────

func stop_combat() -> void:
	_disabled = true
	if _current_attack != AttackKind.NONE:
		_set_attack_window(false)
	_current_attack = AttackKind.NONE
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	_cooldown_remaining = 0.0
	_react_lock_remaining = 0.0
	_hit_targets.clear()
	_on_combat_stopped()
	_finish_action_lock()
	set_physics_process(false)


## Override to clear subclass-specific state during stop_combat.
func _on_combat_stopped() -> void:
	pass
