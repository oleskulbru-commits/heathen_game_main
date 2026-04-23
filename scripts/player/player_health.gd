class_name PlayerHealth
extends Node
## Manages player hit-points, stamina, and death animation resolution.
## Lives as a child node of the player CharacterBody3D.

const DeathAnimationSetResource := preload("res://scripts/common/death_animation_set.gd")
const AnimationResolverUtil := preload("res://scripts/common/animation_resolver.gd")

signal health_changed(current: float, maximum: float)
signal stamina_changed(current: float, maximum: float)
signal died(from_world_pos: Vector3)

@export var max_health: float = 100.0
@export var max_stamina: float = 100.0
@export var stamina_regen_rate: float = 15.0
@export var sprint_stamina_cost: float = 12.0
@export_group("Death")
@export var death_anims: DeathAnimationSetResource

var _health: float
var _stamina: float
var _is_dead: bool = false


func _ready() -> void:
	_health = max_health
	_stamina = max_stamina
	_init_default_death_anims()


func get_health() -> float:
	return _health


func get_stamina() -> float:
	return _stamina


func is_dead() -> bool:
	return _is_dead


func apply_damage(amount: float, from_world_pos: Vector3 = Vector3.INF) -> bool:
	## Apply raw HP reduction. Returns true if this killed the entity.
	if _is_dead or amount <= 0.0:
		return false
	_health = clampf(_health - amount, 0.0, max_health)
	health_changed.emit(_health, max_health)
	if _health <= 0.0:
		_is_dead = true
		died.emit(from_world_pos)
		return true
	return false


func heal(amount: float) -> void:
	if _is_dead or amount <= 0.0:
		return
	_health = clampf(_health + amount, 0.0, max_health)
	health_changed.emit(_health, max_health)


func drain_stamina(amount: float) -> void:
	if _is_dead or amount <= 0.0:
		return
	_stamina = clampf(_stamina - amount, 0.0, max_stamina)
	stamina_changed.emit(_stamina, max_stamina)


func drain_sprint(delta: float) -> bool:
	## Drain sprint stamina. Returns false if exhausted.
	_stamina = clampf(_stamina - sprint_stamina_cost * delta, 0.0, max_stamina)
	stamina_changed.emit(_stamina, max_stamina)
	return _stamina > 0.0


func regen_stamina(delta: float) -> void:
	if _stamina >= max_stamina:
		return
	_stamina = clampf(_stamina + stamina_regen_rate * delta, 0.0, max_stamina)
	stamina_changed.emit(_stamina, max_stamina)


func resolve_death_animation(from_world_pos: Vector3, anim_player: AnimationPlayer) -> StringName:
	if not anim_player:
		return &""
	var player := get_parent() as CharacterBody3D
	var local := player.to_local(from_world_pos) if player and from_world_pos != Vector3.INF else Vector3.INF
	if not death_anims:
		_init_default_death_anims()
	var raw := death_anims.resolve(local)
	var resolved := AnimationResolverUtil.resolve(raw, anim_player)
	if anim_player.has_animation(resolved):
		return resolved
	for candidate in [death_anims.from_front, death_anims.from_back, death_anims.from_left, death_anims.from_right]:
		var alt := AnimationResolverUtil.resolve(candidate, anim_player)
		if anim_player.has_animation(alt):
			return alt
	return resolved


func _init_default_death_anims() -> void:
	if not death_anims:
		death_anims = DeathAnimationSetResource.new()
		death_anims.from_front = &"PlayerDeaths/standing_death_backward_01"
		death_anims.from_back = &"PlayerDeaths/standing_death_forward_01"
		death_anims.from_left = &"PlayerDeaths/standing_death_left_01"
		death_anims.from_right = &"PlayerDeaths/standing_death_right_01"
		death_anims.from_left_alts = []
		death_anims.from_right_alts = [&"PlayerDeaths/standing_death_right_02"]
