shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, blend_mix;

uniform vec4 heart_color : source_color = vec4(0.85, 0.12, 0.1, 1.0);
uniform float pulse_speed : hint_range(0.5, 4.0) = 1.2;
uniform float pulse_strength : hint_range(0.0, 0.3) = 0.12;
uniform float alpha_mult : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Scale in local space first for pulsing
	float pulse = 1.0 + pulse_strength * sin(TIME * pulse_speed * TAU);
	VERTEX.xy *= pulse;
	// Camera-facing billboard: replace model rotation with camera axes
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	// Map UV [0,1] to centered coords, flip Y so heart points up
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y - 0.15; // shift center of heart up slightly
	p *= 1.3;           // scale to fill the quad

	// Parametric heart: (x^2 + y^2 - 1)^3 - x^2*y^3 < 0 means inside
	float x2 = p.x * p.x;
	float d = pow(x2 + p.y * p.y - 1.0, 3.0) - x2 * (p.y * p.y * p.y);

	// Smooth fill with anti-aliased edge
	float fw = fwidth(d) * 3.0;
	float heart_mask = 1.0 - smoothstep(-fw, fw, d);

	// Soft outer glow
	float glow = smoothstep(0.6, 0.0, d / 0.5) * 0.45 * (1.0 - heart_mask);

	vec3 col = heart_color.rgb;
	float a = (heart_mask + glow) * alpha_mult;

	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
