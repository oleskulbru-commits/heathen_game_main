class_name WeatherManager
extends Node
## Manages weather state transitions.  Sits as a sibling of DayNightCycle
## under the Lighting node and drives sky shader + environment fog parameters.
##
## Usage:
##   weather_manager.transition_to(overcast_state)
##   weather_manager.transition_to(fog_state)

signal weather_changed(new_state: WeatherState)

@export var default_state: WeatherState
@export var states: Array[WeatherState] = []

## If true, randomly picks a new state when the current transition finishes.
@export var auto_cycle: bool = false
@export_range(30.0, 600.0) var auto_min_hold: float = 60.0
@export_range(60.0, 900.0) var auto_max_hold: float = 180.0

var current_state: WeatherState
var target_state: WeatherState
var blend: float = 1.0          # 0 = fully current, 1 = fully target (done)

var _sky_mat: ShaderMaterial
var _env: Environment
var _transition_speed: float = 0.0
var _hold_timer: float = 0.0


func _ready() -> void:
	var root := get_parent()
	_env = (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	_sky_mat = _env.sky.sky_material as ShaderMaterial

	if default_state:
		current_state = default_state
		target_state = default_state
		blend = 1.0
		_apply(default_state)
	elif states.size() > 0:
		current_state = states[0]
		target_state = states[0]
		blend = 1.0
		_apply(states[0])

	if auto_cycle:
		_hold_timer = randf_range(auto_min_hold, auto_max_hold)


func _process(delta: float) -> void:
	if blend < 1.0:
		blend = minf(blend + _transition_speed * delta, 1.0)
		_apply_blend(current_state, target_state, blend)
		if blend >= 1.0:
			current_state = target_state
			weather_changed.emit(current_state)
			if auto_cycle:
				_hold_timer = randf_range(auto_min_hold, auto_max_hold)
	elif auto_cycle:
		_hold_timer -= delta
		if _hold_timer <= 0.0:
			_pick_random_state()


func transition_to(state: WeatherState) -> void:
	if state == target_state:
		return
	current_state = _snapshot()
	target_state = state
	blend = 0.0
	_transition_speed = 1.0 / state.transition_duration


## Get current effective value for a property (respects mid-transition blending).
func get_effective_cloud_coverage() -> float:
	if blend >= 1.0:
		return target_state.cloud_coverage
	return lerpf(current_state.cloud_coverage, target_state.cloud_coverage, blend)


func get_effective_fog_density() -> float:
	if blend >= 1.0:
		return target_state.fog_density
	return lerpf(current_state.fog_density, target_state.fog_density, blend)


# ── Internals ───────────────────────────────────────────────────────

func _apply(s: WeatherState) -> void:
	# Sky shader params
	_sky_mat.set_shader_parameter("cloud_coverage", s.cloud_coverage)
	_sky_mat.set_shader_parameter("cloud_density", s.cloud_density)
	_sky_mat.set_shader_parameter("cloud_softness", s.cloud_softness)
	_sky_mat.set_shader_parameter("cloud_speed", s.cloud_speed)
	_sky_mat.set_shader_parameter("cloud_bright_color", s.cloud_bright_color)
	_sky_mat.set_shader_parameter("cloud_shadow_color", s.cloud_shadow_color)
	_sky_mat.set_shader_parameter("rayleigh_coefficient", s.rayleigh_coefficient)
	_sky_mat.set_shader_parameter("mie_coefficient", s.mie_coefficient)
	_sky_mat.set_shader_parameter("turbidity", s.turbidity)

	# Environment fog
	_env.fog_density = s.fog_density
	_env.fog_light_energy = s.fog_light_energy
	_env.volumetric_fog_density = s.volumetric_fog_density


func _apply_blend(a: WeatherState, b: WeatherState, t: float) -> void:
	_sky_mat.set_shader_parameter("cloud_coverage", lerpf(a.cloud_coverage, b.cloud_coverage, t))
	_sky_mat.set_shader_parameter("cloud_density", lerpf(a.cloud_density, b.cloud_density, t))
	_sky_mat.set_shader_parameter("cloud_softness", lerpf(a.cloud_softness, b.cloud_softness, t))
	_sky_mat.set_shader_parameter("cloud_speed", lerpf(a.cloud_speed, b.cloud_speed, t))
	_sky_mat.set_shader_parameter("cloud_bright_color",
		a.cloud_bright_color.lerp(b.cloud_bright_color, t))
	_sky_mat.set_shader_parameter("cloud_shadow_color",
		a.cloud_shadow_color.lerp(b.cloud_shadow_color, t))
	_sky_mat.set_shader_parameter("rayleigh_coefficient",
		lerpf(a.rayleigh_coefficient, b.rayleigh_coefficient, t))
	_sky_mat.set_shader_parameter("mie_coefficient",
		lerpf(a.mie_coefficient, b.mie_coefficient, t))
	_sky_mat.set_shader_parameter("turbidity", lerpf(a.turbidity, b.turbidity, t))

	_env.fog_density = lerpf(a.fog_density, b.fog_density, t)
	_env.fog_light_energy = lerpf(a.fog_light_energy, b.fog_light_energy, t)
	_env.volumetric_fog_density = lerpf(a.volumetric_fog_density, b.volumetric_fog_density, t)


func _snapshot() -> WeatherState:
	## Creates a transient state from whatever is currently applied,
	## so mid-transition interruptions blend smoothly.
	var snap := WeatherState.new()
	snap.cloud_coverage = _sky_mat.get_shader_parameter("cloud_coverage")
	snap.cloud_density = _sky_mat.get_shader_parameter("cloud_density")
	snap.cloud_softness = _sky_mat.get_shader_parameter("cloud_softness")
	snap.cloud_speed = _sky_mat.get_shader_parameter("cloud_speed")
	snap.cloud_bright_color = _sky_mat.get_shader_parameter("cloud_bright_color")
	snap.cloud_shadow_color = _sky_mat.get_shader_parameter("cloud_shadow_color")
	snap.rayleigh_coefficient = _sky_mat.get_shader_parameter("rayleigh_coefficient")
	snap.mie_coefficient = _sky_mat.get_shader_parameter("mie_coefficient")
	snap.turbidity = _sky_mat.get_shader_parameter("turbidity")
	snap.fog_density = _env.fog_density
	snap.fog_light_energy = _env.fog_light_energy
	snap.volumetric_fog_density = _env.volumetric_fog_density
	snap.sun_energy_scale = current_state.sun_energy_scale if current_state else 1.0
	snap.ambient_energy_scale = current_state.ambient_energy_scale if current_state else 1.0
	snap.sky_energy_multiplier = current_state.sky_energy_multiplier if current_state else 1.0
	return snap


func _pick_random_state() -> void:
	if states.size() < 2:
		return
	var candidates := states.filter(func(s): return s != current_state)
	if candidates.size() > 0:
		transition_to(candidates.pick_random())
