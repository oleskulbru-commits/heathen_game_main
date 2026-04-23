extends Node
## Continuous day/night cycle.  Rotates the sun DirectionalLight3D and
## interpolates lighting, sky, and fog properties every frame.
## Works with the custom sky_clouds.gdshader and the WeatherManager.

@export_range(0.0, 24.0) var time_of_day: float = 8.0   ## Start hour (0-24)
@export_range(1.0, 60.0) var day_length_minutes: float = 10.0  ## Real minutes per game day
@export var paused: bool = false

var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _weather: WeatherManager


func _ready() -> void:
	var root := get_parent()
	_sun = root.get_node("DirectionalLight3D")
	_fill = root.get_node("FillLight")
	_moon = root.get_node_or_null("MoonLight")
	if not _moon:
		_moon = DirectionalLight3D.new()
		_moon.name = "MoonLight"
		_moon.shadow_enabled = true
		_moon.shadow_blur = 3.0
		_moon.directional_shadow_max_distance = 200.0
		_moon.light_angular_distance = 0.3
		root.add_child.call_deferred(_moon)
	_env = (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	_sky_mat = _env.sky.sky_material as ShaderMaterial
	_weather = root.get_node_or_null("WeatherManager")
	_tick(time_of_day)


func _process(delta: float) -> void:
	if paused:
		return
	time_of_day = fmod(time_of_day + delta / (day_length_minutes * 60.0) * 24.0, 24.0)
	_tick(time_of_day)


func _tick(t: float) -> void:
	var sun_angle := ((t - 6.0) / 24.0) * TAU
	var elev := sin(sun_angle)                        # -1 nadir … +1 zenith
	var above := elev > 0.0
	var h := smoothstep(0.0, 0.25, absf(elev))       # 0 at horizon, 1 well up/down

	# ── Sun rotation (pitch only – existing yaw preserved) ──────────
	_sun.rotation.x = -sun_angle

	# ── Weather energy scales ───────────────────────────────────────
	var sun_scale := 1.0
	var ambient_scale := 1.0
	if _weather and _weather.current_state:
		if _weather.blend < 1.0:
			sun_scale = lerpf(_weather.current_state.sun_energy_scale,
				_weather.target_state.sun_energy_scale, _weather.blend)
			ambient_scale = lerpf(_weather.current_state.ambient_energy_scale,
				_weather.target_state.ambient_energy_scale, _weather.blend)
		else:
			sun_scale = _weather.target_state.sun_energy_scale
			ambient_scale = _weather.target_state.ambient_energy_scale

	# ── Sun colour / energy ─────────────────────────────────────────
	if above:
		_sun.light_energy = lerpf(0.3, 1.0, h) * sun_scale
		_sun.light_indirect_energy = lerpf(1.0, 1.8, h) * sun_scale
		_sun.light_color = Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.97, 0.9), h)
	else:
		_sun.light_energy = lerpf(0.12, 0.02, h) * sun_scale
		_sun.light_indirect_energy = lerpf(0.4, 0.1, h) * sun_scale
		_sun.light_color = Color(0.35, 0.4, 0.65).lerp(Color(0.2, 0.25, 0.45), h)

	# ── Fill light ──────────────────────────────────────────────────
	if above:
		_fill.light_energy = lerpf(0.2, 0.5, h)
		_fill.light_color = Color(0.6, 0.65, 0.85).lerp(Color(0.75, 0.8, 0.95), h)
	else:
		_fill.light_energy = lerpf(0.08, 0.04, h)
		_fill.light_color = Color(0.3, 0.35, 0.55)

	# ── Moonlight (opposite the sun) ────────────────────────────────
	var moon_angle := sun_angle + PI
	_moon.rotation.x = -moon_angle
	if above:
		# Moon barely visible during the day
		_moon.light_energy = 0.0
		_moon.visible = false
	else:
		_moon.visible = true
		_moon.light_color = Color(0.45, 0.5, 0.7)
		_moon.light_energy = lerpf(0.08, 0.18, h)
		_moon.light_indirect_energy = lerpf(0.2, 0.5, h)
		_moon.light_volumetric_fog_energy = 0.3

	# ── Sky shader ──────────────────────────────────────────────────
	var sky_energy := lerpf(0.12, 1.0, smoothstep(-0.15, 0.2, elev))
	_sky_mat.set_shader_parameter("energy_multiplier", sky_energy)

	var ray_col := Color(0.26, 0.41, 0.58)
	if above and h < 0.6:
		ray_col = ray_col.lerp(Color(0.5, 0.35, 0.5), 1.0 - h / 0.6)
	_sky_mat.set_shader_parameter("rayleigh_color", ray_col)

	var gc := Color(0.15, 0.12, 0.06).lerp(
		Color(0.02, 0.02, 0.04), smoothstep(0.0, -0.2, elev))
	_sky_mat.set_shader_parameter("ground_color", gc)

	# ── Fog ─────────────────────────────────────────────────────────
	var day_fog := Color(0.7, 0.75, 0.85)
	var night_fog := Color(0.06, 0.08, 0.14)
	if _weather and _weather.current_state:
		var ws: WeatherState
		if _weather.blend >= 1.0:
			ws = _weather.target_state
		else:
			ws = _weather.target_state  # WeatherManager already blends fog_density
		day_fog = ws.fog_color_day
		night_fog = ws.fog_color_night
	var warm_fog := Color(0.85, 0.6, 0.4)

	if above:
		var fc := warm_fog.lerp(day_fog, h)
		_env.fog_light_color = fc
		_env.fog_light_energy = lerpf(0.4, 0.7, h)
		_env.fog_sun_scatter = lerpf(0.45, 0.15, h)
		_env.volumetric_fog_albedo = fc
		_env.volumetric_fog_emission = fc * 0.4
		_env.volumetric_fog_emission_energy = lerpf(0.08, 0.04, h)
	else:
		_env.fog_light_color = night_fog
		_env.fog_light_energy = lerpf(0.15, 0.03, h)
		_env.fog_sun_scatter = 0.0
		_env.volumetric_fog_albedo = night_fog
		_env.volumetric_fog_emission = night_fog * 0.3
		_env.volumetric_fog_emission_energy = 0.02

	# ── Ambient & glow ──────────────────────────────────────────────
	_env.ambient_light_energy = lerpf(0.35, 0.8, smoothstep(-0.15, 0.2, elev)) * ambient_scale
	if not above:
		_env.ambient_light_color = Color(0.3, 0.35, 0.55)
	else:
		_env.ambient_light_color = Color(1, 1, 1)

	if above:
		_env.glow_bloom = lerpf(0.12, 0.06, h)
		_env.glow_intensity = lerpf(0.5, 0.3, h)
	else:
		_env.glow_bloom = 0.07
		_env.glow_intensity = 0.3
