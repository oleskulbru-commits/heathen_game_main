shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Wind
uniform float wind_strength : hint_range(0.0, 2.0) = 0.25;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.2;

// Colors
uniform vec3 stem_color   : source_color = vec3(0.18, 0.32, 0.08);
uniform vec3 petal_color_a : source_color = vec3(0.85, 0.75, 0.2);
uniform vec3 petal_color_b : source_color = vec3(0.8, 0.35, 0.55);
uniform vec3 center_color  : source_color = vec3(0.35, 0.25, 0.05);

uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.3;
uniform float fade_start : hint_range(10.0, 500.0) = 80.0;
uniform float fade_end   : hint_range(20.0, 600.0) = 120.0;

varying float v_height;
varying float v_hash;

float quick_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_hash = quick_hash(world_pos.xz);
	v_height = clamp(VERTEX.y / max(0.01, length(vec3(MODEL_MATRIX[1][0], MODEL_MATRIX[1][1], MODEL_MATRIX[1][2]))), 0.0, 1.0);

	// Gentle sway
	float wind_wave = sin(TIME * wind_speed + world_pos.x * 1.2 + world_pos.z * 0.9);
	float sway = wind_wave * wind_strength * v_height * v_height;
	VERTEX.x += sway * 0.15;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0; // -1 to 1

	float mask = 0.0;

	if (v_height < 0.55) {
		// Stem region: thin vertical line
		float stem_width = 0.08;
		mask = 1.0 - smoothstep(stem_width * 0.8, stem_width, abs(uv.x));
	} else {
		// Flower head: radial petal pattern
		float flower_v = (v_height - 0.55) / 0.45; // 0-1 within flower region
		float r = length(uv);
		float angle = atan(uv.y, uv.x);

		// Petal lobes (5 petals)
		float petals = 5.0;
		float petal_shape = abs(cos(angle * petals * 0.5 + v_hash * 6.28));
		float petal_radius = 0.35 + petal_shape * 0.25;

		mask = 1.0 - smoothstep(petal_radius - 0.08, petal_radius, r);

		// Center disk
		float center_mask = 1.0 - smoothstep(0.1, 0.15, r);
		mask = max(mask, center_mask);
	}

	if (mask < alpha_cutoff) discard;

	// Color
	vec3 col;
	if (v_height < 0.55) {
		col = stem_color;
	} else {
		float r = length(uv);
		vec3 petal_col = mix(petal_color_a, petal_color_b, v_hash);
		col = mix(center_color, petal_col, smoothstep(0.08, 0.2, r));
	}

	// AO at base
	col *= mix(0.5, 1.0, smoothstep(0.0, 0.2, v_height));

	ALBEDO = col;
	ROUGHNESS = 0.75;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.2, 0.15, 0.05) * v_height;

	float cam_dist = length(VERTEX);
	ALPHA = mask * (1.0 - smoothstep(fade_start, fade_end, cam_dist));
}
