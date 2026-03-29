shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Colors
uniform vec3 moss_color_a : source_color = vec3(0.18, 0.35, 0.08);
uniform vec3 moss_color_b : source_color = vec3(0.25, 0.42, 0.15);
uniform vec3 lichen_color_a : source_color = vec3(0.50, 0.55, 0.32);
uniform vec3 lichen_color_b : source_color = vec3(0.60, 0.62, 0.40);
uniform float lichen_blend : hint_range(0.0, 1.0) = 0.3;

uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.2;
uniform float fade_start : hint_range(10.0, 500.0) = 70.0;
uniform float fade_end   : hint_range(20.0, 600.0) = 110.0;

varying float v_hash;

float quick_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = quick_hash(i);
	float b = quick_hash(i + vec2(1.0, 0.0));
	float c = quick_hash(i + vec2(0.0, 1.0));
	float d = quick_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_hash = quick_hash(world_pos.xz);
	// No wind — moss/lichen are ground-hugging
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;

	// Organic patch shape using layered noise
	float r = length(uv);
	float n1 = noise2d(UV * 8.0 + vec2(v_hash * 50.0));
	float n2 = noise2d(UV * 16.0 + vec2(v_hash * 30.0, 10.0));
	float edge = 0.6 + n1 * 0.25 + n2 * 0.1;

	float mask = 1.0 - smoothstep(edge - 0.12, edge, r);

	if (mask < alpha_cutoff) discard;

	// Determine moss vs lichen based on per-instance hash
	float is_lichen = step(1.0 - lichen_blend, v_hash);

	vec3 col_a, col_b;
	if (is_lichen > 0.5) {
		col_a = lichen_color_a;
		col_b = lichen_color_b;
	} else {
		col_a = moss_color_a;
		col_b = moss_color_b;
	}

	// Patchy color variation
	float color_noise = noise2d(UV * 12.0 + vec2(v_hash * 20.0));
	vec3 col = mix(col_a, col_b, color_noise);

	// Darken edges slightly
	col *= mix(0.7, 1.0, 1.0 - smoothstep(edge - 0.25, edge - 0.05, r));

	// Subtle moisture sheen for moss
	float moisture = (1.0 - is_lichen) * 0.15;

	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.6, moisture);
	SPECULAR = mix(0.05, 0.3, moisture);

	float cam_dist = length(VERTEX);
	ALPHA = mask * (1.0 - smoothstep(fade_start, fade_end, cam_dist));
}
