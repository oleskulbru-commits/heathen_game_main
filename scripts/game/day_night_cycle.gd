extends Node
## Continuous day/night cycle.  Rotates the sun DirectionalLight3D and
## interpolates lighting, sky, and fog properties every frame.

@export_range(0.0, 24.0) var time_of_day: float = 8.0   ## Start hour (0-24)
@export_range(1.0, 60.0) var day_length_minutes: float = 10.0  ## Real minutes per game day
@export var paused: bool = false

var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _env: Environment
var _sky: PhysicalSkyMaterial


func _ready() -> void:
	var root := get_parent()
	_sun = root.get_node("DirectionalLight3D")
	_fill = root.get_node("FillLight")
	_env = (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	_sky = _env.sky.sky_material as PhysicalSkyMaterial
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

	# ── Sun colour / energy ─────────────────────────────────────────
	if above:
		_sun.light_energy = lerpf(0.3, 1.0, h)
		_sun.light_indirect_energy = lerpf(1.0, 1.8, h)
		_sun.light_color = Color(1.0, 0.55, 0.25).lerp(Color(1.0, 0.97, 0.9), h)
	else:
		_sun.light_energy = lerpf(0.12, 0.02, h)
		_sun.light_indirect_energy = lerpf(0.4, 0.1, h)
		_sun.light_color = Color(0.35, 0.4, 0.65).lerp(Color(0.2, 0.25, 0.45), h)

	# ── Fill light ──────────────────────────────────────────────────
	if above:
		_fill.light_energy = lerpf(0.2, 0.5, h)
		_fill.light_color = Color(0.6, 0.65, 0.85).lerp(Color(0.75, 0.8, 0.95), h)
	else:
		_fill.light_energy = lerpf(0.08, 0.02, h)
		_fill.light_color = Color(0.25, 0.3, 0.5)

	# ── Sky material ────────────────────────────────────────────────
	_sky.energy_multiplier = lerpf(0.05, 1.0, smoothstep(-0.15, 0.2, elev))

	if above and h < 0.6:
		# Warm violet tint at sunrise / sunset
		_sky.rayleigh_color = Color(0.26, 0.41, 0.58).lerp(
			Color(0.5, 0.35, 0.5), 1.0 - h / 0.6)
	else:
		_sky.rayleigh_color = Color(0.26, 0.41, 0.58)

	_sky.ground_color = Color(0.15, 0.12, 0.06).lerp(
		Color(0.02, 0.02, 0.04), smoothstep(0.0, -0.2, elev))

	# ── Fog ─────────────────────────────────────────────────────────
	var day_fog := Color(0.7, 0.75, 0.85)
	var warm_fog := Color(0.85, 0.6, 0.4)
	var night_fog := Color(0.06, 0.08, 0.14)

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
	_env.ambient_light_energy = lerpf(0.25, 0.8, smoothstep(-0.15, 0.2, elev))

	if above:
		_env.glow_bloom = lerpf(0.12, 0.06, h)
		_env.glow_intensity = lerpf(0.5, 0.3, h)
	else:
		_env.glow_bloom = 0.05
		_env.glow_intensity = 0.25
