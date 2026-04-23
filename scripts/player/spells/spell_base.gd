extends Resource
class_name SpellBase
## Base resource for all Taufr spells and Alchemies.
## Subclass this to create specific spell behaviors.

## Display info
@export var spell_name: String = "Empty"
@export var verb_name: String = "Empty"  ## Short name used during prototyping
@export var description: String = ""
@export var slot_type: int = 0  ## 0 = Taufr (spell), 1 = Alchemy (gadget)

## Catalyst / ammo
@export var catalyst_name: String = ""
@export var infinite_uses: bool = true  ## Prototype: always true
@export var uses_remaining: int = -1

## Cooldown
@export var cooldown: float = 0.5
var _cooldown_remaining: float = 0.0

## Hugr cost — how much panic this spell generates (0.0 – 1.0)
@export var hugr_cost: float = 0.1


func is_ready() -> bool:
	return _cooldown_remaining <= 0.0 and (infinite_uses or uses_remaining > 0)


func update(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta


## Override in subclasses. Return true if cast succeeded.
func cast(_player: CharacterBody3D) -> bool:
	if not is_ready():
		return false
	_cooldown_remaining = cooldown
	if not infinite_uses:
		uses_remaining -= 1
	return true


## Called every physics frame while the spell effect is active.
## Override for continuous spells (dash movement, sustained effects).
func physics_update(_player: CharacterBody3D, _delta: float) -> void:
	pass


func can_start_sustained(_player: CharacterBody3D) -> bool:
	return false


func start_sustained(_player: CharacterBody3D) -> bool:
	return false


func can_start_targeted(_player: CharacterBody3D) -> bool:
	return false


func start_targeted(_player: CharacterBody3D) -> bool:
	return false


func confirm_targeted(_player: CharacterBody3D) -> bool:
	return false


## Whether this spell is currently performing an action that locks the player.
func is_active() -> bool:
	return false


## Clean up when spell is interrupted or slot is changed.
func cancel(_player: CharacterBody3D) -> void:
	pass
