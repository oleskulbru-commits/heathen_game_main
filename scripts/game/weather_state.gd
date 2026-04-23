class_name WeatherState
extends Resource
## Defines a single weather preset.  The WeatherManager interpolates between
## two of these when transitioning.

@export_group("Clouds")
@export_range(0.0, 1.0) var cloud_coverage: float = 0.45
@export_range(0.0, 2.0) var cloud_density: float = 1.0
@export_range(0.01, 0.5) var cloud_softness: float = 0.15
@export_range(0.0, 0.05) var cloud_speed: float = 0.005
@export var cloud_bright_color: Color = Color(1.0, 1.0, 1.0)
@export var cloud_shadow_color: Color = Color(0.4, 0.45, 0.55)

@export_group("Fog")
@export_range(0.0, 0.01) var fog_density: float = 0.0005
@export_range(0.0, 2.0) var fog_light_energy: float = 0.7
@export_range(0.0, 0.2) var volumetric_fog_density: float = 0.006
@export var fog_color_day: Color = Color(0.7, 0.75, 0.85)
@export var fog_color_night: Color = Color(0.06, 0.08, 0.14)

@export_group("Sky")
@export_range(0.0, 4.0) var sky_energy_multiplier: float = 1.0
@export_range(0.0, 10.0) var rayleigh_coefficient: float = 2.0
@export_range(0.0, 0.1) var mie_coefficient: float = 0.005
@export_range(0.0, 20.0) var turbidity: float = 4.0

@export_group("Light")
@export_range(0.0, 2.0) var sun_energy_scale: float = 1.0
@export_range(0.0, 2.0) var ambient_energy_scale: float = 1.0

@export_group("Transition")
@export_range(0.5, 60.0) var transition_duration: float = 10.0
