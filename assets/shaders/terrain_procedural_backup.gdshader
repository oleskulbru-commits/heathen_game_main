// Procedural Norwegian Terrain Shader for Terrain3D
// Realistic slope + elevation biome blending with noise-driven transitions
// Vertex pipeline from Terrain3D minimum.gdshader

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;

// -----------------------------------------------
// Constants
// -----------------------------------------------
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	#define fma(a, b, c) ((a) * (b) + (c))
	#define dFdxCoarse(a) dFdx(a)
	#define dFdyCoarse(a) dFdy(a)
#endif

// -----------------------------------------------
// Private uniforms (managed by Terrain3D engine)
// -----------------------------------------------
uniform vec3 _camera_pos = vec3(0.0);
uniform float _mesh_size = 48.0;
uniform uint _background_mode = 1u;
uniform uint _mouse_layer = 0x80000000u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0;
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625;
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;

// -----------------------------------------------
// Public uniforms — Height Zones (game units)
// -----------------------------------------------
group_uniforms HeightZones;
uniform float valley_floor : hint_range(0.0, 50.0) = 5.0;
uniform float grass_end : hint_range(20.0, 200.0) = 80.0;
uniform float alpine_start : hint_range(20.0, 200.0) = 55.0;
uniform float tree_line : hint_range(50.0, 250.0) = 110.0;
uniform float snow_start : hint_range(80.0, 300.0) = 150.0;
uniform float snow_full : hint_range(100.0, 400.0) = 220.0;

// -----------------------------------------------
// Public uniforms — Slope Thresholds
// normal.y: 1.0 = flat ground, 0.0 = vertical cliff
// -----------------------------------------------
group_uniforms SlopeThresholds;
uniform float grass_slope_max : hint_range(0.5, 1.0) = 0.82;
uniform float rock_slope_start : hint_range(0.3, 0.9) = 0.70;
uniform float cliff_slope : hint_range(0.1, 0.7) = 0.42;
uniform float snow_slope_min : hint_range(0.3, 0.9) = 0.55;

// -----------------------------------------------
// Public uniforms — Surface Colours
// -----------------------------------------------
group_uniforms SurfaceColors;
uniform vec3 grass_dark : source_color = vec3(0.14, 0.26, 0.04);
uniform vec3 grass_light : source_color = vec3(0.28, 0.46, 0.10);
uniform vec3 alpine_color : source_color = vec3(0.32, 0.40, 0.14);
uniform vec3 dirt_color : source_color = vec3(0.42, 0.30, 0.14);
uniform vec3 rock_light_color : source_color = vec3(0.48, 0.46, 0.42);
uniform vec3 rock_dark_color : source_color = vec3(0.24, 0.23, 0.21);
uniform vec3 cliff_face_color : source_color = vec3(0.18, 0.17, 0.16);
uniform vec3 moss_tint : source_color = vec3(0.26, 0.32, 0.14);
uniform vec3 snow_surface : source_color = vec3(0.90, 0.92, 0.95);
uniform vec3 scree_surface : source_color = vec3(0.40, 0.38, 0.34);
uniform vec3 gravel_surface : source_color = vec3(0.36, 0.33, 0.28);

// -----------------------------------------------
// Public uniforms — Variation & Noise
// -----------------------------------------------
group_uniforms Variation;
uniform float noise_scale : hint_range(0.001, 0.05) = 0.008;
uniform float height_noise_amp : hint_range(0.0, 50.0) = 15.0;
uniform float slope_noise_amp : hint_range(0.0, 0.3) = 0.12;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.15;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.30;
group_uniforms;

// -----------------------------------------------
// Varyings
// -----------------------------------------------
varying float v_vertex_xz_dist;
varying vec3 v_vertex;

// ==============================================
// Terrain3D vertex pipeline (minimum.gdshader)
// ==============================================

ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv, _region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor(r_uv * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = _region_map[pos.y * _region_map_size + pos.x] * bounds - 1;
		}
	}
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
}

void vertex() {
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95,
		(v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	vec2 shift = (scale < _vertex_spacing + 1e-6) ?
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))) :
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	UV = v_vertex.xz * _vertex_density;
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = bool(control >> 2u & 0x1u);

	if (!(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && v_region.z < 0))) {
		v_vertex.x = 0.0 / 0.0;
	} else {
		ivec3 uv_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 uv_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, uv_a, 0).r,
			texelFetch(_height_maps, uv_b, 0).r, vertex_lerp);
		v_vertex.y = h;
	}

	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

// ==============================================
// Procedural noise (sin-free hash approach)
// ==============================================

vec2 _hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float _gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(dot(_hash22(i), f),
			dot(_hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(_hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
			dot(_hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
		u.y);
}

// Fractal Brownian Motion — 4 octaves with domain rotation
float _fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		v += a * _gnoise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return v;
}

// ==============================================
// Fragment — procedural biome shading
// ==============================================

void fragment() {
	// --- Terrain normal computation (from minimum.gdshader) ---
	vec2 uv = UV;
	const vec3 offsets = vec3(0, 1, 2);
	vec2 index_id = floor(uv);
	vec2 wt = fract(uv);
	vec2 iwt = 1.0 - wt;
	vec4 weights = vec4(iwt.x * wt.y, wt.x * wt.y, wt.x * iwt.y, iwt.x * iwt.y);

	bool bilerp = log2(max(
		length(dFdxCoarse(v_vertex).xz),
		length(dFdyCoarse(v_vertex).xz)) * _vertex_density) < 0.0;

	ivec3 idx[4];
	idx[0] = get_index_coord(index_id + offsets.xy, FRAGMENT_PASS);
	idx[1] = get_index_coord(index_id + offsets.yy, FRAGMENT_PASS);
	idx[2] = get_index_coord(index_id + offsets.yx, FRAGMENT_PASS);
	idx[3] = get_index_coord(index_id + offsets.xx, FRAGMENT_PASS);

	float ht0 = texelFetch(_height_maps, idx[0], 0).r;
	float ht2 = texelFetch(_height_maps, idx[2], 0).r;
	float ht3 = texelFetch(_height_maps, idx[3], 0).r;
	vec3 inorm3 = normalize(vec3(ht3 - ht2, _vertex_spacing, ht3 - ht0));
	vec3 w_normal = inorm3;

	if (bilerp) {
		float ht1 = texelFetch(_height_maps, idx[1], 0).r;
		float ht4 = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, FRAGMENT_PASS), 0).r;
		float ht5 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, FRAGMENT_PASS), 0).r;
		float ht6 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, FRAGMENT_PASS), 0).r;
		float ht7 = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, FRAGMENT_PASS), 0).r;
		vec3 inorm0 = normalize(vec3(ht0 - ht1, _vertex_spacing, ht0 - ht7));
		vec3 inorm1 = normalize(vec3(ht1 - ht5, _vertex_spacing, ht1 - ht4));
		vec3 inorm2 = normalize(vec3(ht2 - ht6, _vertex_spacing, ht2 - ht1));
		w_normal = inorm0 * weights.x + inorm1 * weights.y
			 + inorm2 * weights.z + inorm3 * weights.w;
	}

	// Tangent frame for correct lighting
	vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(w_normal, w_tangent));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;

	// =================================================
	//  Procedural Biome Colouring
	// =================================================
	float slope = max(w_normal.y, 0.0);   // 1 = flat, 0 = vertical
	float height = v_vertex.y;
	vec2 wpos = v_vertex.xz;

	// --- Multi-scale noise ---
	float n_large  = _fbm4(wpos * noise_scale);            // Landscape-scale patches
	float n_medium = _fbm4(wpos * noise_scale * 5.0);      // Medium detail
	float n_detail = _gnoise(wpos * noise_scale * 20.0);   // Fine texture
	float n_strata = _gnoise(vec2(height * 1.5,
		dot(wpos, vec2(0.08))));                            // Rock striations

	// Noise-perturbed thresholds for organic zone boundaries
	float ph = height + n_large * height_noise_amp;
	float ps = slope  + n_medium * slope_noise_amp;

	// --- Height-zone factors ---
	float f_valley    = 1.0 - smoothstep(valley_floor, grass_end, ph);
	float f_alpine    = smoothstep(alpine_start, tree_line, ph)
	                  * (1.0 - smoothstep(tree_line, snow_start, ph));
	float f_subalpine = smoothstep(tree_line, snow_start, ph)
	                  * (1.0 - smoothstep(snow_start, snow_full, ph));
	float f_snow_zone = smoothstep(snow_start, snow_full, ph);

	// --- Slope-based surface type ---
	float f_grass_slope = smoothstep(rock_slope_start, grass_slope_max, ps);
	float f_cliff       = 1.0 - smoothstep(cliff_slope, rock_slope_start, ps);
	float f_snow_slope  = smoothstep(cliff_slope, snow_slope_min, ps);

	// --- Composite biome weights ---
	float w_snow  = f_snow_zone * f_snow_slope;
	float w_grass = f_grass_slope * (1.0 - w_snow);
	float w_rock  = max(1.0 - w_grass - w_snow, 0.0);

	// ---- GRASS surface ----
	vec3 c_grass = mix(grass_dark, grass_light, n_medium * 0.5 + 0.5);
	// Alpine tint at higher elevations
	c_grass = mix(c_grass, alpine_color, f_alpine + f_subalpine * 0.5);
	// Dirt patches in valley areas
	float f_dirt = smoothstep(0.3, 0.7, n_large + 0.2) * dirt_amount * f_valley;
	c_grass = mix(c_grass, dirt_color, f_dirt);
	// Gravel near streams (very low elevation)
	float f_gravel = (1.0 - smoothstep(0.0, valley_floor, height)) * f_grass_slope;
	c_grass = mix(c_grass, gravel_surface, f_gravel);
	// Micro-variation
	c_grass *= 0.9 + 0.2 * (n_detail * 0.5 + 0.5);

	// ---- ROCK surface ----
	float rock_dark_fac = clamp((1.0 - slope) * 1.5 + n_medium * 0.3, 0.0, 1.0);
	vec3 c_rock = mix(rock_light_color, rock_dark_color, rock_dark_fac);
	// Cliff colouring for very steep faces
	c_rock = mix(c_rock, cliff_face_color, f_cliff);
	// Horizontal striations on steep rock
	c_rock += n_strata * 0.04 * f_cliff;
	// Scree at high-elevation moderate slopes
	c_rock = mix(c_rock, scree_surface + n_detail * 0.05,
		f_subalpine * (1.0 - f_cliff));
	// Moss / lichen on moderate-slope rock (not cliff-steep, not grass-flat)
	float f_moss = moss_amount
		* smoothstep(cliff_slope, rock_slope_start, slope)
		* (1.0 - smoothstep(rock_slope_start, grass_slope_max, slope))
		* smoothstep(0.2, 0.6, n_medium * 0.5 + 0.5)
		* (1.0 - f_snow_zone);
	c_rock = mix(c_rock, moss_tint, f_moss);
	// Micro-variation
	c_rock *= 0.92 + 0.16 * (n_detail * 0.5 + 0.5);

	// ---- SNOW surface ----
	vec3 c_snow = snow_surface * (0.95 + 0.1 * n_detail);
	// Dirty snow at transition edges
	c_snow = mix(c_snow * vec3(0.85, 0.83, 0.80), c_snow,
		smoothstep(0.0, 0.3, w_snow));

	// ---- Final colour blend ----
	vec3 albedo = c_grass * w_grass + c_rock * w_rock + c_snow * w_snow;

	// Wetness near water level — darker, glossier
	float wetness = (1.0 - smoothstep(0.0, valley_floor * 0.6, height)) * 0.15;
	albedo *= 1.0 - wetness;

	// ---- Roughness per biome ----
	float r_grass = mix(0.88, 0.95, n_detail * 0.5 + 0.5);
	float r_rock  = mix(0.65, 0.80, n_medium * 0.5 + 0.5);
	r_rock = mix(r_rock, 0.55, f_cliff);   // Wet cliff faces
	float r_snow  = mix(0.35, 0.55, n_detail * 0.5 + 0.5);
	float roughness = r_grass * w_grass + r_rock * w_rock + r_snow * w_snow
		- wetness;

	// ---- Ambient occlusion approximation ----
	float ao = 1.0 - (1.0 - slope) * 0.15;          // Crevices are darker
	ao *= 0.85 + 0.15 * smoothstep(0.0, 50.0, height); // Valley floors darker

	// ---- Output ----
	ALBEDO = albedo;
	ROUGHNESS = clamp(roughness, 0.0, 1.0);
	AO = clamp(ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.5;
}
