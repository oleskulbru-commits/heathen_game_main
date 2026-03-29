shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Wind
uniform float wind_strength : hint_range(0.0, 2.0) = 0.2;
uniform float wind_speed : hint_range(0.0, 5.0) = 0.8;

// Colors
uniform vec3 inner_color  : source_color = vec3(0.12, 0.18, 0.08);
uniform vec3 outer_color  : source_color = vec3(0.42, 0.18, 0.42);
uniform vec3 flower_tint  : source_color = vec3(0.55, 0.25, 0.55);
uniform float color_variation : hint_range(0.0, 0.2) = 0.06;

uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.25;
uniform float fade_start : hint_range(10.0, 500.0) = 90.0;
uniform float fade_end   : hint_range(20.0, 600.0) = 130.0;

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

	float wind_wave = sin(TIME * wind_speed + world_pos.x * 0.8 + world_pos.z * 0.6);
	float sway = wind_wave * wind_strength * v_height;
	VERTEX.x += sway * 0.1;
	VERTEX.z += sway * 0.08;
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;

	// Bushy rounded shape with noisy edge
	float r = length(uv);
	float angle = atan(uv.y, uv.x);

	// Irregular bush silhouette using noise
	float edge_noise = noise2d(vec2(angle * 3.0 + v_hash * 10.0, v_height * 4.0)) * 0.3;
	float bush_radius = 0.55 + edge_noise - v_height * 0.15;

	float mask = 1.0 - smoothstep(bush_radius - 0.1, bush_radius, r);

	// Small flower dots scattered on upper half
	float flower_mask = 0.0;
	if (v_height > 0.4) {
		float fn = noise2d(UV * 25.0 + vec2(v_hash * 100.0));
		flower_mask = step(0.72, fn) * mask;
	}

	if (mask < alpha_cutoff) discard;

	// Color
	vec3 col = mix(inner_color, outer_color, smoothstep(0.0, 0.7, r));
	col += (v_hash - 0.5) * color_variation;

	// Mix in flower color for flower dots
	col = mix(col, flower_tint, flower_mask * 0.8);

	// AO darkening at base
	col *= mix(0.4, 1.0, smoothstep(0.0, 0.35, v_height));

	ALBEDO = col;
	ROUGHNESS = 0.88;
	SPECULAR = 0.1;
	BACKLIGHT = vec3(0.15, 0.10, 0.15) * v_height;

	float cam_dist = length(VERTEX);
	ALPHA = mask * (1.0 - smoothstep(fade_start, fade_end, cam_dist));
}
