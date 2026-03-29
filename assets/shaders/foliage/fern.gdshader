shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

// Wind
uniform float wind_strength : hint_range(0.0, 2.0) = 0.35;
uniform float wind_speed : hint_range(0.0, 5.0) = 1.0;

// Colors
uniform vec3 stem_color   : source_color = vec3(0.15, 0.22, 0.06);
uniform vec3 frond_color_a : source_color = vec3(0.18, 0.40, 0.10);
uniform vec3 frond_color_b : source_color = vec3(0.25, 0.48, 0.12);

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

	// Ferns sway more at the tips
	float wind_wave = sin(TIME * wind_speed + world_pos.x * 1.5 + world_pos.z * 1.1);
	wind_wave += cos(TIME * wind_speed * 0.6 + world_pos.z * 2.0) * 0.4;
	float sway = wind_wave * wind_strength * v_height * v_height;
	VERTEX.x += sway * 0.2;
	VERTEX.z += sway * 0.1;

	// Curl tips downward (fern droop)
	VERTEX.y -= v_height * v_height * 0.15 * length(vec3(MODEL_MATRIX[1][0], MODEL_MATRIX[1][1], MODEL_MATRIX[1][2]));
}

void fragment() {
	vec2 uv = UV;
	float u_centered = uv.x * 2.0 - 1.0; // -1 to 1

	// Central stem (rachis)
	float stem_mask = 1.0 - smoothstep(0.03, 0.05, abs(u_centered));

	// Leaflets (pinnae) branching from stem
	// Repeating pairs along the height
	float leaf_freq = 12.0 + v_hash * 4.0;
	float leaf_phase = fract(v_height * leaf_freq);

	// Leaflets angle outward more toward base
	float leaflet_angle = mix(0.6, 0.3, v_height);
	float leaflet_len = mix(0.45, 0.15, v_height); // shorter at tip

	// Leaflet shape: elongated ovals on each side
	float side = sign(u_centered);
	float leaflet_u = abs(u_centered);
	float leaflet_mask = smoothstep(0.05, 0.08, leaflet_u) *
						 (1.0 - smoothstep(leaflet_len - 0.05, leaflet_len, leaflet_u));
	// Taper along each leaflet sub-segment
	float leaflet_v_shape = 1.0 - abs(leaf_phase * 2.0 - 1.0);
	leaflet_mask *= smoothstep(0.0, 0.3, leaflet_v_shape) * smoothstep(1.0, 0.5, leaflet_v_shape);

	float mask = max(stem_mask, leaflet_mask);

	// Taper entire frond toward tip
	mask *= smoothstep(1.0, 0.8, v_height);

	if (mask < alpha_cutoff) discard;

	// Color
	vec3 col = mix(stem_color, mix(frond_color_a, frond_color_b, v_hash), step(0.06, abs(u_centered)));

	// Darken at base for AO
	col *= mix(0.45, 1.0, smoothstep(0.0, 0.25, v_height));

	// Subtle vein darkening along leaflet center
	col *= mix(0.85, 1.0, abs(leaf_phase * 2.0 - 1.0));

	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.25, 0.35, 0.1) * v_height;

	float cam_dist = length(VERTEX);
	ALPHA = mask * (1.0 - smoothstep(fade_start, fade_end, cam_dist));
}
