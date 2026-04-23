shader_type sky;
render_mode use_debanding;

// ── Physical sky approximation ─────────────────────────────────────
uniform vec3 rayleigh_color : source_color = vec3(0.26, 0.41, 0.58);
uniform float rayleigh_coefficient : hint_range(0.0, 10.0) = 2.0;
uniform vec3 mie_color : source_color = vec3(0.69, 0.73, 0.73);
uniform float mie_coefficient : hint_range(0.0, 0.1) = 0.005;
uniform float mie_eccentricity : hint_range(-1.0, 1.0) = 0.8;
uniform float turbidity : hint_range(0.0, 20.0) = 4.0;
uniform float sun_disk_scale : hint_range(0.0, 2.0) = 1.0;
uniform float energy_multiplier : hint_range(0.0, 4.0) = 1.0;
uniform vec3 ground_color : source_color = vec3(0.1, 0.07, 0.034);
uniform float night_sky_brightness : hint_range(0.0, 0.2) = 0.02;

// ── Cloud parameters ───────────────────────────────────────────────
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_density : hint_range(0.0, 2.0) = 1.0;
uniform float cloud_softness : hint_range(0.01, 0.5) = 0.15;
uniform float cloud_speed : hint_range(0.0, 0.05) = 0.005;
uniform float cloud_height : hint_range(0.02, 0.6) = 0.15;
uniform vec3 cloud_bright_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow_color : source_color = vec3(0.4, 0.45, 0.55);
uniform float cloud_wind_angle : hint_range(0.0, 6.2832) = 0.5;

// ── Hash / noise helpers ───────────────────────────────────────────
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f); // smoothstep
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	float freq = 1.0;
	for (int i = 0; i < 5; i++) {
		value += amp * value_noise(p * freq);
		freq *= 2.0;
		amp *= 0.5;
	}
	return value;
}

// ── Rayleigh / Mie phase functions ─────────────────────────────────
float rayleigh_phase(float cos_theta) {
	return 0.75 * (1.0 + cos_theta * cos_theta);
}

float mie_phase(float cos_theta, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5));
}

void sky() {
	vec3 dir = EYEDIR;
	float elevation = dir.y;
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sun_elev = sun_dir.y;
	float cos_theta = dot(dir, sun_dir);

	// ── Ground ─────────────────────────────────────────────────────
	if (elevation < 0.0) {
		COLOR = ground_color * energy_multiplier;
		return;
	}

	// ── Atmospheric scattering (simplified) ────────────────────────
	float zenith = max(elevation, 0.001);
	float sun_zenith = max(sun_elev, -0.15);

	// Optical depth approximation
	float rayleigh_depth = exp(-zenith * 4.0) / zenith;
	float mie_depth = exp(-zenith * 1.2) / zenith;

	vec3 rayleigh_scatter = rayleigh_color * rayleigh_coefficient * rayleigh_phase(cos_theta) * rayleigh_depth;
	vec3 mie_scatter = mie_color * mie_coefficient * turbidity * mie_phase(cos_theta, mie_eccentricity) * mie_depth;

	// Sun illumination factor
	float sun_factor = smoothstep(-0.15, 0.2, sun_zenith);

	vec3 sky_col = (rayleigh_scatter + mie_scatter) * sun_factor;

	// ── Sun disk ───────────────────────────────────────────────────
	float sun_angular = acos(clamp(cos_theta, -1.0, 1.0));
	float sun_radius = 0.0087 * sun_disk_scale; // ~0.5 degrees
	float sun_disk = smoothstep(sun_radius, sun_radius * 0.5, sun_angular);
	sky_col += vec3(1.0, 0.95, 0.85) * sun_disk * 40.0 * sun_factor;

	// ── Night sky base ─────────────────────────────────────────────
	float night = smoothstep(0.0, -0.2, sun_elev);
	sky_col += vec3(0.05, 0.08, 0.18) * night_sky_brightness * night * (0.5 + 0.5 * elevation);

	// ── Horizon glow at sunset/sunrise ─────────────────────────────
	float horizon_band = exp(-abs(elevation) * 8.0);
	float sunset_factor = smoothstep(-0.1, 0.0, sun_elev) * smoothstep(0.25, 0.0, sun_elev);
	sky_col += vec3(0.8, 0.35, 0.1) * horizon_band * sunset_factor * 0.6;

	// ── Clouds ─────────────────────────────────────────────────────
	if (elevation > 0.001 && cloud_coverage > 0.001) {
		// Project onto a flat plane at cloud_height
		vec2 cloud_uv = dir.xz / (elevation + cloud_height);
		// Wind direction
		float ca = cos(cloud_wind_angle);
		float sa = sin(cloud_wind_angle);
		vec2 wind = vec2(ca, sa) * TIME * cloud_speed;
		cloud_uv += wind;

		// Multi-octave noise
		float n = fbm(cloud_uv * 3.0);
		float n2 = fbm(cloud_uv * 7.0 + vec2(5.3, 1.7));
		float cloud_shape = n * 0.7 + n2 * 0.3;

		// Coverage threshold
		float threshold = 1.0 - cloud_coverage;
		float cloud = smoothstep(threshold, threshold + cloud_softness, cloud_shape);
		cloud *= cloud_density;
		cloud = clamp(cloud, 0.0, 1.0);

		// Cloud lighting - brighter on the sun-facing side
		float cloud_light = smoothstep(-0.1, 0.5, sun_elev) * (0.5 + 0.5 * smoothstep(-0.2, 0.6, cos_theta));
		vec3 cloud_col = mix(cloud_shadow_color, cloud_bright_color, cloud_light);

		// Darken clouds at night
		cloud_col *= mix(0.08, 1.0, smoothstep(-0.15, 0.1, sun_elev));

		// Fade clouds near horizon to avoid hard cutoff
		float horizon_fade = smoothstep(0.0, 0.08, elevation);
		cloud *= horizon_fade;

		sky_col = mix(sky_col, cloud_col, cloud);
	}

	COLOR = sky_col * energy_multiplier;
}
