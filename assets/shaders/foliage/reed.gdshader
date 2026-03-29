shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Wind
uniform float wind_strength : hint_range(0.0, 2.0) = 0.5;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.8;

// Colors
uniform vec3 base_color : source_color = vec3(0.35, 0.38, 0.12);
uniform vec3 tip_color  : source_color = vec3(0.55, 0.52, 0.25);
uniform vec3 seed_color : source_color = vec3(0.45, 0.35, 0.18);

uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.3;
uniform float fade_start : hint_range(10.0, 500.0) = 90.0;
uniform float fade_end   : hint_range(20.0, 600.0) = 130.0;

varying float v_height;
varying float v_hash;

float quick_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_hash = quick_hash(world_pos.xz);
	float scale_y = length(vec3(MODEL_MATRIX[1][0], MODEL_MATRIX[1][1], MODEL_MATRIX[1][2]));
	v_height = clamp(VERTEX.y / max(0.01, scale_y), 0.0, 1.0);

	// Strong swaying at top — reeds are tall and flexible
	float wind_wave = sin(TIME * wind_speed + world_pos.x * 0.9 + world_pos.z * 1.3);
	wind_wave += sin(TIME * wind_speed * 1.3 + world_pos.x * 2.0) * 0.3;
	float sway = wind_wave * wind_strength * v_height * v_height;
	VERTEX.x += sway * 0.25;
	VERTEX.z += sway * 0.12;
}

void fragment() {
	float u = UV.x * 2.0 - 1.0; // -1 to 1

	// Reed stalk: thin with slight taper
	float stalk_width = mix(0.1, 0.04, v_height);
	float stalk_mask = 1.0 - smoothstep(stalk_width * 0.7, stalk_width, abs(u));

	// Seed head at top (cattail-like bulge)
	float seed_mask = 0.0;
	if (v_height > 0.7 && v_height < 0.92) {
		float seed_v = (v_height - 0.7) / 0.22;
		float seed_width = 0.18 * sin(seed_v * 3.14159);
		seed_mask = 1.0 - smoothstep(seed_width - 0.03, seed_width, abs(u));
	}

	float mask = max(stalk_mask, seed_mask);

	if (mask < alpha_cutoff) discard;

	// Color
	vec3 col;
	if (seed_mask > stalk_mask) {
		col = seed_color;
	} else {
		col = mix(base_color, tip_color, v_height);
	}

	// Per-instance variation
	col += (v_hash - 0.5) * 0.06;

	// AO at base
	col *= mix(0.5, 1.0, smoothstep(0.0, 0.15, v_height));

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.2, 0.2, 0.08) * v_height;

	float cam_dist = length(VERTEX);
	ALPHA = mask * (1.0 - smoothstep(fade_start, fade_end, cam_dist));
}
