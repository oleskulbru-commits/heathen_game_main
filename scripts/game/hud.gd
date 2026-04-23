extends CanvasLayer
## Raven Eye HUD — health/stamina bars + Thief-style light gem raven eye.

@onready var health_bar: TextureProgressBar = $Anchor/HealthBar
@onready var stamina_bar: TextureProgressBar = $Anchor/StaminaBar
@onready var raven_eye: TextureRect = $Anchor/RavenEye
@onready var iris: TextureRect = $Anchor/RavenEye/Iris
@onready var radial_menu: Control = $RadialMenu

var _health_tween: Tween
var _stamina_tween: Tween
var _eye_tween: Tween
var _iris_tween: Tween
var _light_probe: Node
var _player: Node

## HDR fiery orange — multiplies the brighter eye textures to a vivid glow
const EYE_LIT := Color(5.0, 2.5, 0.6, 1.0)
## No modulation — show raven eye gradients as-is
const EYE_DARK := Color(1.0, 1.0, 1.0, 1.0)
## Daytime — naturally lit with warm ambient light
const EYE_INACTIVE := Color(1.3, 1.2, 1.1, 1.0)


func _ready() -> void:
	_bind_player.call_deferred()


func _bind_player() -> void:
	var player := _find_player()
	if not player:
		await get_tree().process_frame
		player = _find_player()
		if not player:
			return
	if not player.is_node_ready():
		await player.ready
	_player = player
	if player.has_signal("health_changed") and not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal("stamina_changed") and not player.stamina_changed.is_connected(_on_stamina_changed):
		player.stamina_changed.connect(_on_stamina_changed)
	if player is ICombatTarget and player.has_method("get_max_health") and player.has_method("get_max_stamina"):
		_on_health_changed(player.get_health(), player.get_max_health())
		_on_stamina_changed(player.get_stamina(), player.get_max_stamina())

	_light_probe = player.get_node_or_null("LightProbe")
	if _light_probe and not _light_probe.visibility_changed.is_connected(_on_visibility_changed):
		_light_probe.visibility_changed.connect(_on_visibility_changed)

	var ability_system := player.get_node_or_null("AbilitySystem")
	if ability_system and radial_menu:
		ability_system._radial_menu = radial_menu
		ability_system._sync_radial_menu()


func _find_player() -> Node:
	var game := get_parent()
	var player := game.get_node_or_null("Characters/Player")
	if not player:
		player = game.get_node_or_null("Player")
	return player


func _on_health_changed(current: float, maximum: float) -> void:
	var ratio := current / maximum if maximum > 0.0 else 0.0
	if _health_tween:
		_health_tween.kill()
	_health_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_health_tween.tween_property(health_bar, "value", ratio * 100.0, 0.35)


func _on_stamina_changed(current: float, maximum: float) -> void:
	var ratio := current / maximum if maximum > 0.0 else 0.0
	if _stamina_tween:
		_stamina_tween.kill()
	_stamina_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_stamina_tween.tween_property(stamina_bar, "value", ratio * 100.0, 0.25)


func _on_visibility_changed(value: float) -> void:
	if not _light_probe:
		return

	var target_color: Color

	if _light_probe.is_daytime():
		target_color = EYE_INACTIVE
	elif _light_probe.is_hidden():
		# In darkness — show original raven eye design
		target_color = EYE_DARK
	else:
		# In light — lerp from original look to fiery orange glow
		var intensity := clampf(value / 0.5, 0.0, 1.0)
		target_color = EYE_DARK.lerp(EYE_LIT, intensity)

	if _eye_tween:
		_eye_tween.kill()
	if _iris_tween:
		_iris_tween.kill()
	# Sclera stays at base color, only subtle brightness shift
	var sclera_color: Color
	if _light_probe.is_daytime():
		sclera_color = EYE_INACTIVE
	else:
		sclera_color = EYE_DARK
	_eye_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_eye_tween.tween_property(raven_eye, "self_modulate", sclera_color, 0.4)
	# Iris (+ children pupil/highlight) reacts to light
	_iris_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_iris_tween.tween_property(iris, "modulate", target_color, 0.4)
