shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Wind
uniform float wind_strength : hint_range(0.0, 2.0) = 0.15;
uniform float wind_speed : hint_range(0.0, 5.0) = 0.7;

// Colors
uniform vec3 leaf_color_a : source_color = vec3(0.12, 0.28, 0.15);
uniform vec3 leaf_color_b : source_color = vec3(0.18, 0.35, 0.12);
uniform vec3 berry_color  : source_color = vec3(0.15, 0.08, 0.25);
uniform float berry_amount : hint_range(0.0, 1.0) = 0.15;

uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.25;
uniform float fade_start : hint_range(10.0, 500.0) = 85.0;
uniform float fade_end   : hint_range(20.0, 600.0) = 125.0;

varying float v_height;
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
	v_height = clamp(VERTEX.y / max(0.01, length(vec3(MODEL_MATRIX[1][0], MODEL_MATRIX[1][1], MODEL_MATRIX[1][2]))), 0.0, 1.0);

	float wind_wave = sin(TIME * wind_speed + world_pos.x * 0.6 + world_pos.z * 0.8);
	float sway = wind_wave * wind_strength * v_height;
	VERTEX.x += sway * 0.08;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);

	// Rounded bush shape with noisy clumps
	float n = noise2d(UV * 10.0 + vec2(v_hash * 40.0));
	float n2 = noise2d(UV * 20.0 + vec2(v_hash * 25.0, 5.0));
	float edge = 0.5 + n * 0.2 + n2 * 0.08;

	// Taper top to rounded dome
	edge -= v_height * 0.15;

	float mask = 1.0 - smoothstep(edge - 0.1, edge, r);

	// Internal leaf cluster gaps for depth
	float gap = noise2d(UV * 30.0 + vec2(v_hash * 60.0));
	mask *= smoothstep(0.15, 0.25, gap);

	if (mask < alpha_cutoff) discard;

	// Color — leaf variation
	float color_noise = noise2d(UV * 14.0 + vec2(v_hash * 15.0));
	vec3 col = mix(leaf_color_a, leaf_color_b, color_noise);

	// Berry dots
	float berry_noise = noise2d(UV * 35.0 + vec2(v_hash * 80.0));
	float berry_mask = step(1.0 - berry_amount, berry_noise) * step(0.3, v_height);
	col = mix(col, berry_color, berry_mask * 0.9);

	// AO at base
	col *= mix(0.35, 1.0, smoothstep(0.0, 0.3, v_height));

	// Light variation across surface
	col *= 0.85 + n * 0.3;

	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.12;
	BACKLIGHT = vec3(0.12, 0.18, 0.06) * v_height;

	float cam_dist = length(VERTEX);
	ALPHA = mask * (1.0 - smoothstep(fade_start, fade_end, cam_dist));
}
