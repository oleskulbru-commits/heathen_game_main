shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Wind
uniform float wind_strength : hint_range(0.0, 2.0) = 0.4;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.5;
uniform float wind_scale : hint_range(0.001, 0.1) = 0.02;

// Color
uniform vec3 base_color : source_color = vec3(0.12, 0.24, 0.04);
uniform vec3 tip_color  : source_color = vec3(0.30, 0.50, 0.10);
uniform float color_variation : hint_range(0.0, 0.3) = 0.08;

// Shape
uniform float blade_taper : hint_range(0.0, 1.0) = 0.85;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.35;

// Distance fade
uniform float fade_start : hint_range(10.0, 500.0) = 100.0;
uniform float fade_end   : hint_range(20.0, 600.0) = 140.0;

varying float v_height;
varying float v_hash;

float quick_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// Per-instance hash from world position for variation
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_hash = quick_hash(world_pos.xz);

	// Normalised height within blade (0 = base, 1 = tip)
	v_height = clamp(VERTEX.y / max(0.01, length(vec3(MODEL_MATRIX[1][0], MODEL_MATRIX[1][1], MODEL_MATRIX[1][2]))), 0.0, 1.0);

	// Wind – only affects upper portion
	float wind_wave = sin(TIME * wind_speed + world_pos.x * wind_scale * 60.0 + world_pos.z * wind_scale * 45.0);
	wind_wave += sin(TIME * wind_speed * 0.7 + world_pos.z * wind_scale * 80.0) * 0.5;
	float sway = wind_wave * wind_strength * v_height * v_height;
	VERTEX.x += sway * 0.3;
	VERTEX.z += sway * 0.15;
}

void fragment() {
	// Blade shape: taper from full width at base to narrow at tip
	float u = UV.x * 2.0 - 1.0;  // -1 to 1
	float taper_width = mix(1.0, 1.0 - blade_taper, v_height);
	float blade_mask = 1.0 - smoothstep(taper_width * 0.45, taper_width * 0.5, abs(u));

	// Add slight serration for realism
	float serration = sin(v_height * 40.0 + v_hash * 20.0) * 0.02 * v_height;
	blade_mask += serration;

	// Alpha test
	if (blade_mask < alpha_cutoff) discard;

	// Color gradient base to tip with per-instance variation
	vec3 col = mix(base_color, tip_color, v_height);
	float variation = (v_hash - 0.5) * color_variation * 2.0;
	col += vec3(variation * 0.5, variation, variation * 0.3);

	// Subtle AO at base
	col *= mix(0.6, 1.0, smoothstep(0.0, 0.3, v_height));

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;

	// Subsurface-like backlight
	BACKLIGHT = vec3(0.3, 0.4, 0.15) * v_height;

	// Distance fade
	float cam_dist = length(VERTEX);
	ALPHA = blade_mask * (1.0 - smoothstep(fade_start, fade_end, cam_dist));
}
