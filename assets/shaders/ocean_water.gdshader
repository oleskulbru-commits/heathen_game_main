shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ── Gerstner Waves ──
group_uniforms waves;
uniform float wave_amplitude : hint_range(0.0, 10.0) = 2.5;
uniform float wave_wavelength : hint_range(50.0, 500.0) = 300.0;
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.78;
uniform float wave_speed : hint_range(0.0, 5.0) = 1.0;
uniform vec2 wind_direction = vec2(0.8, 0.6);

// ── Water Tint ──
group_uniforms color;
uniform vec4 water_tint : source_color = vec4(0.02, 0.06, 0.10, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.3;

// ── Surface ──
group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.01;
uniform float normal_strength : hint_range(0.0, 3.0) = 0.4;
uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_map_scale : hint_range(0.001, 0.1) = 0.02;
uniform float normal_map_speed : hint_range(0.0, 1.0) = 0.015;

// Gerstner wave with deep-water dispersion (GPU Gems Ch.1)
vec3 _gerstner(vec2 pos, float time, vec2 dir, float wavelength, float amp, float steep,
               inout vec3 tangent, inout vec3 binormal) {
	float w = 6.2831853 / wavelength;
	float phase = sqrt(9.8 * w) * time;
	float q = steep / (w * amp * 6.0 + 0.001);
	float f = w * dot(dir, pos) + phase;
	float s = sin(f);
	float c = cos(f);
	float wa = w * amp;
	tangent += vec3(-q * dir.x * dir.x * wa * s,
	                 dir.x * wa * c,
	                -q * dir.x * dir.y * wa * s);
	binormal += vec3(-q * dir.x * dir.y * wa * s,
	                  dir.y * wa * c,
	                 -q * dir.y * dir.y * wa * s);
	return vec3(q * amp * dir.x * c, amp * s, q * amp * dir.y * c);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 pos = wp.xz;
	float t = TIME * wave_speed;

	vec3 tang = vec3(1.0, 0.0, 0.0);
	vec3 bino = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);

	vec2 d1 = normalize(wind_direction);
	vec2 d2 = normalize(d1 + vec2(-d1.y, d1.x) * 0.7);
	vec2 d3 = normalize(d1 * 0.3 + vec2(d1.y, -d1.x));
	vec2 d4 = normalize(-d1 + vec2(0.4, 0.7));
	vec2 d5 = normalize(d1 * 0.6 + vec2(-d1.y, d1.x) * 0.4);
	vec2 d6 = normalize(vec2(d1.y, -d1.x) * 0.8 + d1 * 0.2);

	// Primary swell
	disp += _gerstner(pos, t, d1, wave_wavelength,
		wave_amplitude, wave_steepness, tang, bino);
	// Secondary swell
	disp += _gerstner(pos, t, d2, wave_wavelength * 0.55,
		wave_amplitude * 0.55, wave_steepness, tang, bino);
	// Cross-chop
	disp += _gerstner(pos, t, d3, wave_wavelength * 0.32,
		wave_amplitude * 0.35, wave_steepness, tang, bino);
	// Counter-swell
	disp += _gerstner(pos, t, d4, wave_wavelength * 0.40,
		wave_amplitude * 0.22, wave_steepness * 0.9, tang, bino);
	// Short chop A
	disp += _gerstner(pos, t, d5, wave_wavelength * 0.18,
		wave_amplitude * 0.18, wave_steepness * 0.85, tang, bino);
	// Short chop B
	disp += _gerstner(pos, t, d6, wave_wavelength * 0.12,
		wave_amplitude * 0.12, wave_steepness * 0.75, tang, bino);

	VERTEX += disp;
	NORMAL = normalize(cross(bino, tang));
	TANGENT = normalize(tang);
	BINORMAL = normalize(bino);
}

void fragment() {
	// ── Scrolling dual-layer normal maps for subtle ripple ──
	vec2 world_uv = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz * normal_map_scale;
	float t = TIME * normal_map_speed;
	vec3 n1 = texture(normal_map_a, world_uv + vec2(t * 0.8, t * 0.4)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_map_b, world_uv * 0.7 + vec2(-t * 0.3, t * 0.6)).rgb * 2.0 - 1.0;
	vec3 detail_normal = normalize(vec3(
		(n1.x + n2.x) * normal_strength,
		(n1.y + n2.y) * normal_strength,
		n1.z + n2.z
	));

	NORMAL_MAP = detail_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;

	// Pure mirror surface with a dark water tint
	ALBEDO = water_tint.rgb * tint_strength;
	METALLIC = 1.0;
	ROUGHNESS = roughness;
	SPECULAR = 1.0;
}
