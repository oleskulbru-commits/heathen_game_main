shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

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
