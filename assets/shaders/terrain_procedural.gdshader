// Procedural Norwegian Terrain Shader for Terrain3D
// Realistic slope + elevation biome blending with noise-driven transitions
// Supports optional PBR texture overrides per biome layer
// Built on Terrain3D minimum.gdshader vertex pipeline

shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

// Defined Constants
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms
uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform uint _mouse_layer = 0x80000000u; // Layer 32
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1/_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1/1024
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;

// Public Uniforms
uniform bool flat_terrain_normals = false;

group_uniforms HeightZones;
uniform float valley_floor : hint_range(0.0, 50.0) = 5.0;
uniform float grass_end : hint_range(20.0, 200.0) = 80.0;
uniform float alpine_start : hint_range(20.0, 200.0) = 55.0;
uniform float tree_line : hint_range(50.0, 250.0) = 110.0;
uniform float snow_start : hint_range(80.0, 300.0) = 170.0;
uniform float snow_full : hint_range(100.0, 400.0) = 260.0;

group_uniforms SlopeThresholds;
uniform float grass_slope_max : hint_range(0.5, 1.0) = 0.82;
uniform float rock_slope_start : hint_range(0.3, 0.9) = 0.70;
uniform float cliff_slope : hint_range(0.1, 0.7) = 0.42;
uniform float snow_slope_min : hint_range(0.3, 0.9) = 0.70;

group_uniforms SurfaceColors;
uniform vec3 grass_dark : source_color = vec3(0.12, 0.22, 0.05);
uniform vec3 grass_light : source_color = vec3(0.25, 0.40, 0.12);
uniform vec3 alpine_color : source_color = vec3(0.28, 0.34, 0.14);
uniform vec3 dirt_color : source_color = vec3(0.35, 0.26, 0.14);
uniform vec3 rock_light_color : source_color = vec3(0.44, 0.42, 0.38);
uniform vec3 rock_dark_color : source_color = vec3(0.22, 0.21, 0.19);
uniform vec3 cliff_face_color : source_color = vec3(0.16, 0.15, 0.14);
uniform vec3 moss_tint : source_color = vec3(0.20, 0.30, 0.10);
uniform vec3 snow_surface : source_color = vec3(0.88, 0.90, 0.93);

group_uniforms Variation;
uniform float noise_scale : hint_range(0.001, 0.05) = 0.008;
uniform float height_noise_amp : hint_range(0.0, 50.0) = 15.0;
uniform float slope_noise_amp : hint_range(0.0, 0.3) = 0.12;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.25;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.50;
uniform float grass_moss_amount : hint_range(0.0, 1.0) = 0.35;
uniform float grass_dirt_spread : hint_range(0.0, 1.0) = 0.60;

group_uniforms GrassTextures;
uniform bool use_grass_textures = false;
uniform sampler2D grass_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_uv_scale : hint_range(0.01, 2.0) = 0.25;
uniform float grass_normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms DirtTextures;
uniform bool use_dirt_textures = false;
uniform sampler2D dirt_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_roughness_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float dirt_uv_scale : hint_range(0.01, 2.0) = 0.25;
uniform float dirt_normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms RockTextures;
uniform bool use_rock_textures = false;
uniform sampler2D rock_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_roughness_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_uv_scale : hint_range(0.01, 2.0) = 0.15;
uniform float rock_normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float rock_triplanar_sharpness : hint_range(1.0, 16.0) = 8.0;

group_uniforms SnowTextures;
uniform bool use_snow_textures = false;
uniform sampler2D snow_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_roughness_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float snow_uv_scale : hint_range(0.01, 2.0) = 0.20;
uniform float snow_normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms MossTextures;
uniform bool use_moss_textures = false;
uniform sampler2D moss_albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_roughness_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float moss_uv_scale : hint_range(0.01, 2.0) = 0.25;
uniform float moss_normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms DebugTools;
uniform bool debug_flat_albedo = false;

group_uniforms;

// Varyings & Types
// Some are required for editor functions
varying float v_vertex_xz_dist;
varying vec3 v_vertex;

////////////////////////
// Noise helpers
////////////////////////

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

float _fbm4(vec2 p) {
	float val = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 4; i++) {
		val += a * _gnoise(p);
		p = rot * p * 2.0;
		a *= 0.5;
	}
	return val;
}

////////////////////////
// Triplanar helpers
////////////////////////

vec3 _triplanar_weights(vec3 normal, float sharpness) {
	vec3 w = pow(abs(normal), vec3(sharpness));
	return w / (w.x + w.y + w.z + 1e-6);
}

vec4 _sample_triplanar(sampler2D tex, vec3 pos, float uv_sc, vec3 tri_w) {
	vec4 x_proj = texture(tex, pos.yz * uv_sc);
	vec4 y_proj = texture(tex, pos.xz * uv_sc);
	vec4 z_proj = texture(tex, pos.xy * uv_sc);
	return x_proj * tri_w.x + y_proj * tri_w.y + z_proj * tri_w.z;
}

////////////////////////
// Vertex
////////////////////////

ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv,_region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u ) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}

void vertex() {
	// Get vertex of flat plane in world coordinates and set world UV
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera distance to vertex on flat plane
	v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

	// Geomorph vertex, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	// For LOD0 morph from a regular grid to an alternating grid to align with LOD1+
	vec2 shift = (scale < _vertex_spacing + 1e-6) ? // LOD0 or not
		// Shift from regular to symetric
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))
			) :
		// Symetric shift
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	// UV coordinates in world space. Values are 0 to _region_size within regions
	UV = v_vertex.xz * _vertex_density;

	// UV coordinates in region space + texel offset. Values are 0 to 1 within regions
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// Discard vertices for Holes. 1 lookup
	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = bool(control >>2u & 0x1u);

	// Show holes to all cameras except mouse camera (on exactly 1 layer)
	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) &&
			(hole || (_background_mode == 0u && v_region.z < 0))) {
		v_vertex.x = 0. / 0.;
	} else {
		// Interpolate Geomorph Start & End, set height. 2 Lookups.
		ivec3 uv_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 uv_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, uv_a, 0).r, texelFetch(_height_maps, uv_b, 0).r, vertex_lerp);
		v_vertex.y = h;
	}

	// Convert model space to view space w/ skip_vertex_transform render mode
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

////////////////////////
// Fragment
////////////////////////

void fragment() {
	// Recover UVs
	vec2 uv = UV;

	// Lookup offsets, ID and blend weight
	const vec3 offsets = vec3(0, 1, 2);
	vec2 index_id = floor(uv);
	vec2 weight = fract(uv);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y, // 0
		weight.x * weight.y, // 1
		weight.x * invert.y, // 2
		invert.x * invert.y  // 3
	);

	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);
	float region_mip = log2(max(length(base_ddx.xz), length(base_ddy.xz)) * _vertex_density);
	bool bilerp = region_mip < 0.0;

	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy, FRAGMENT_PASS);
	index[1] = get_index_coord(index_id + offsets.yy, FRAGMENT_PASS);
	index[2] = get_index_coord(index_id + offsets.yx, FRAGMENT_PASS);
	index[3] = get_index_coord(index_id + offsets.xx, FRAGMENT_PASS);

	// Terrain normals
	vec3 index_normal[4];
	float h[4];
	float u = 0.0;
	float v = 0.0;

	h[3] = texelFetch(_height_maps, index[3], 0).r; // 0 (0,0)
	h[2] = texelFetch(_height_maps, index[2], 0).r; // 1 (1,0)
	h[0] = texelFetch(_height_maps, index[0], 0).r; // 2 (0,1)
	index_normal[3] = normalize(vec3(h[3] - h[2] + u, _vertex_spacing, h[3] - h[0] + v));

	vec3 w_normal = index_normal[3];

	if (bilerp) {
		h[1] = texelFetch(_height_maps, index[1], 0).r; // 3 (1,1)
		float h_4 = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, FRAGMENT_PASS), 0).r; // 4 (1,2)
		float h_5 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, FRAGMENT_PASS), 0).r; // 5 (2,1)
		float h_6 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, FRAGMENT_PASS), 0).r; // 6 (2,0)
		float h_7 = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, FRAGMENT_PASS), 0).r; // 7 (0,2)

		index_normal[0] = normalize(vec3(h[0] - h[1] + u, _vertex_spacing, h[0] - h_7 + v));
		index_normal[1] = normalize(vec3(h[1] - h_5 + u, _vertex_spacing, h[1] - h_4 + v));
		index_normal[2] = normalize(vec3(h[2] - h_6 + u, _vertex_spacing, h[2] - h[1] + v));

		w_normal =
			index_normal[0] * weights[0] +
			index_normal[1] * weights[1] +
			index_normal[2] * weights[2] +
			index_normal[3] * weights[3] ;
	}

	// Apply terrain normals
	vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(w_normal, w_tangent));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;

	if (flat_terrain_normals) {
		NORMAL = normalize(cross(dFdyCoarse(VERTEX),dFdxCoarse(VERTEX)));
		TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
		BINORMAL = normalize(cross(NORMAL, TANGENT));
	}

	// =================================================
	//  Procedural Biome Colouring
	// =================================================
	float slope = max(w_normal.y, 0.0);
	float height = v_vertex.y;
	vec2 wpos = v_vertex.xz;

	// Multi-scale noise
	float n_large  = _fbm4(wpos * noise_scale);
	float n_medium = _fbm4(wpos * noise_scale * 5.0);
	float n_detail = _gnoise(wpos * noise_scale * 20.0);
	float n_strata = _gnoise(vec2(height * 1.5, dot(wpos, vec2(0.08))));

	// Noise-perturbed thresholds
	float ph = height + n_large * height_noise_amp;
	float ps = slope  + n_medium * slope_noise_amp;

	// Height-zone factors
	float f_valley    = 1.0 - smoothstep(valley_floor, grass_end, ph);
	float f_alpine    = smoothstep(alpine_start, tree_line, ph)
	                  * (1.0 - smoothstep(tree_line, snow_start, ph));
	float f_subalpine = smoothstep(tree_line, snow_start, ph)
	                  * (1.0 - smoothstep(snow_start, snow_full, ph));
	float f_snow_zone = smoothstep(snow_start, snow_full, ph);

	// Slope-based surface type
	float f_grass_slope = smoothstep(rock_slope_start, grass_slope_max, ps);
	float f_cliff       = 1.0 - smoothstep(cliff_slope, rock_slope_start, ps);
	float f_snow_slope  = smoothstep(snow_slope_min - 0.05, snow_slope_min, ps);

	// Composite biome weights — only near-horizontal surfaces accumulate snow
	float w_snow  = f_snow_zone * f_snow_slope;
	w_snow *= smoothstep(0.55, 0.75, slope);
	// Grass fades out above tree line — flat alpine surfaces become rock
	float grass_altitude_fade = 1.0 - smoothstep(tree_line, snow_start, ph);
	float w_grass = f_grass_slope * grass_altitude_fade * (1.0 - w_snow);
	float w_rock  = max(1.0 - w_grass - w_snow, 0.0);

	// Shared factors
	// Dirt: noise-driven patches across all grass zones, stronger in valleys
	float dirt_valley_boost = mix(grass_dirt_spread, 1.0, f_valley);
	float f_dirt = smoothstep(0.3, 0.7, n_large + 0.2) * dirt_amount * dirt_valley_boost;
	// Moss patches in grass zones: separate noise channel from dirt
	float n_moss_mask = _fbm4(wpos * noise_scale * 3.5 + vec2(137.0, 281.0));
	float f_grass_moss = grass_moss_amount
		* smoothstep(0.05, 0.50, n_moss_mask * 0.5 + 0.5)
		* (1.0 - f_snow_zone)
		* (1.0 - smoothstep(tree_line, snow_start, ph)) // fade out above tree line
		* smoothstep(0.4, 0.65, slope); // ground moss on flattish terrain
	vec3 tri_w = _triplanar_weights(w_normal, rock_triplanar_sharpness);

	// =================================================
	//  PBR Texture Sampling (when enabled)
	// =================================================
	vec3 tex_grass_alb = vec3(0.0);
	vec3 tex_grass_nrm = vec3(0.5, 0.5, 1.0);
	float tex_grass_rgh = 0.9;
	vec3 tex_dirt_alb  = vec3(0.0);
	vec3 tex_dirt_nrm  = vec3(0.5, 0.5, 1.0);
	float tex_dirt_rgh  = 0.85;
	vec3 tex_rock_alb  = vec3(0.0);
	vec3 tex_rock_nrm  = vec3(0.5, 0.5, 1.0);
	float tex_rock_rgh  = 0.9;
	vec3 tex_snow_alb  = vec3(0.0);
	vec3 tex_snow_nrm  = vec3(0.5, 0.5, 1.0);
	float tex_snow_rgh  = 0.72;
	vec3 tex_moss_alb  = vec3(0.0);
	vec3 tex_moss_nrm  = vec3(0.5, 0.5, 1.0);
	float tex_moss_rgh  = 0.92;

	if (use_grass_textures) {
		vec2 guv = wpos * grass_uv_scale;
		tex_grass_alb = texture(grass_albedo_tex, guv).rgb;
		tex_grass_nrm = texture(grass_normal_tex, guv).xyz;
		tex_grass_rgh = texture(grass_roughness_tex, guv).r;
	}
	if (use_dirt_textures) {
		vec2 duv = wpos * dirt_uv_scale;
		tex_dirt_alb = texture(dirt_albedo_tex, duv).rgb;
		tex_dirt_nrm = texture(dirt_normal_tex, duv).xyz;
		tex_dirt_rgh = texture(dirt_roughness_tex, duv).r;
	}
	if (use_rock_textures) {
		tex_rock_alb = _sample_triplanar(rock_albedo_tex, v_vertex, rock_uv_scale, tri_w).rgb;
		tex_rock_nrm = _sample_triplanar(rock_normal_tex, v_vertex, rock_uv_scale, tri_w).xyz;
		tex_rock_rgh = _sample_triplanar(rock_roughness_tex, v_vertex, rock_uv_scale, tri_w).r;
	}
	if (use_snow_textures) {
		vec2 suv = wpos * snow_uv_scale;
		tex_snow_alb = texture(snow_albedo_tex, suv).rgb;
		tex_snow_nrm = texture(snow_normal_tex, suv).xyz;
		tex_snow_rgh = texture(snow_roughness_tex, suv).r;
	}
	if (use_moss_textures) {
		vec2 muv = wpos * moss_uv_scale;
		tex_moss_alb = texture(moss_albedo_tex, muv).rgb;
		tex_moss_nrm = texture(moss_normal_tex, muv).xyz;
		tex_moss_rgh = texture(moss_roughness_tex, muv).r;
	}

	// ---- GRASS surface ----
	vec3 c_grass = vec3(0.0);
	float r_grass = 0.9;
	vec3 n_grass = vec3(0.5, 0.5, 1.0);
	if (use_grass_textures) {
		c_grass = tex_grass_alb;
		n_grass = tex_grass_nrm;
		r_grass = tex_grass_rgh;
		// Alpine altitude tint
		c_grass = mix(c_grass, c_grass * (alpine_color / max(grass_light, vec3(0.01))),
			f_alpine + f_subalpine * 0.5);
		// Dirt patches in valleys
		if (use_dirt_textures) {
			c_grass = mix(c_grass, tex_dirt_alb, f_dirt);
			n_grass = mix(tex_grass_nrm, tex_dirt_nrm, f_dirt);
			r_grass = mix(tex_grass_rgh, tex_dirt_rgh, f_dirt);
		} else {
			c_grass = mix(c_grass, dirt_color, f_dirt);
		}
		// Shore dirt near water level
		float f_shore_dirt = (1.0 - smoothstep(0.0, valley_floor, height)) * f_grass_slope;
		if (use_dirt_textures) {
			c_grass = mix(c_grass, tex_dirt_alb, f_shore_dirt);
			n_grass = mix(n_grass, tex_dirt_nrm, f_shore_dirt);
			r_grass = mix(r_grass, tex_dirt_rgh, f_shore_dirt);
		} else {
			c_grass = mix(c_grass, dirt_color, f_shore_dirt);
		}
		// Moss patches in grass zones
		if (use_moss_textures) {
			c_grass = mix(c_grass, tex_moss_alb, f_grass_moss);
			n_grass = mix(n_grass, tex_moss_nrm, f_grass_moss);
			r_grass = mix(r_grass, tex_moss_rgh, f_grass_moss);
		} else {
			c_grass = mix(c_grass, moss_tint, f_grass_moss);
		}
	} else {
		c_grass = mix(grass_dark, grass_light, n_medium * 0.5 + 0.5);
		c_grass = mix(c_grass, alpine_color, f_alpine + f_subalpine * 0.5);
		c_grass = mix(c_grass, dirt_color, f_dirt);
		float f_shore_dirt = (1.0 - smoothstep(0.0, valley_floor, height)) * f_grass_slope;
		c_grass = mix(c_grass, dirt_color, f_shore_dirt);
		// Moss patches in grass zones (procedural)
		c_grass = mix(c_grass, moss_tint, f_grass_moss);
		c_grass *= 0.94 + 0.12 * (n_detail * 0.5 + 0.5);
		r_grass = mix(0.92, 0.98, n_detail * 0.5 + 0.5);
	}

	// ---- ROCK surface ----
	vec3 c_rock = vec3(0.0);
	float r_rock = 0.9;
	vec3 n_rock = vec3(0.5, 0.5, 1.0);
	float f_moss = moss_amount
		* smoothstep(cliff_slope, rock_slope_start, slope)
		* (1.0 - smoothstep(rock_slope_start, grass_slope_max, slope))
		* smoothstep(0.2, 0.6, n_medium * 0.5 + 0.5)
		* (1.0 - f_snow_zone)
		* (1.0 - smoothstep(tree_line, snow_start, ph)); // no moss on alpine rock
	if (use_rock_textures) {
		c_rock = tex_rock_alb;
		n_rock = tex_rock_nrm;
		r_rock = tex_rock_rgh;
		// Strata lines on cliffs
		c_rock += n_strata * 0.03 * f_cliff;
		c_rock += n_strata * 0.03 * f_cliff;

		// Moss on moderate slopes — use grass texture for vegetation creep onto rock
		if (use_grass_textures) {
			c_rock = mix(c_rock, tex_grass_alb, f_moss);
			n_rock = mix(n_rock, tex_grass_nrm, f_moss);
			r_rock = mix(r_rock, tex_grass_rgh, f_moss);
		} else {
			c_rock = mix(c_rock, moss_tint, f_moss);
		}
	} else {
		float rock_dark_fac = clamp((1.0 - slope) * 1.5 + n_medium * 0.3, 0.0, 1.0);
		c_rock = mix(rock_light_color, rock_dark_color, rock_dark_fac);
		c_rock = mix(c_rock, cliff_face_color, f_cliff);
		c_rock += n_strata * 0.04 * f_cliff;

		c_rock = mix(c_rock, mix(grass_dark, grass_light, 0.5), f_moss);
		c_rock *= 0.92 + 0.16 * (n_detail * 0.5 + 0.5);
		r_rock = mix(0.85, 0.95, n_medium * 0.5 + 0.5);
		r_rock = mix(r_rock, 0.82, f_cliff);
	}

	// ---- SNOW surface ----
	vec3 c_snow = vec3(0.0);
	float r_snow = 0.72;
	vec3 n_snow = vec3(0.5, 0.5, 1.0);
	if (use_snow_textures) {
		c_snow = tex_snow_alb;
		c_snow = mix(c_snow * vec3(0.85, 0.83, 0.80), c_snow,
			smoothstep(0.0, 0.3, w_snow));
		n_snow = tex_snow_nrm;
		r_snow = tex_snow_rgh;
	} else {
		c_snow = snow_surface * (0.95 + 0.1 * n_detail);
		c_snow = mix(c_snow * vec3(0.85, 0.83, 0.80), c_snow,
			smoothstep(0.0, 0.3, w_snow));
		r_snow = mix(0.65, 0.82, n_detail * 0.5 + 0.5);
	}

	// ---- Final colour blend ----
	vec3 albedo = c_grass * w_grass + c_rock * w_rock + c_snow * w_snow;

	// Wetness near water level
	float wetness = (1.0 - smoothstep(0.0, valley_floor * 0.6, height)) * 0.08;
	albedo *= 1.0 - wetness;

	float roughness = r_grass * w_grass + r_rock * w_rock + r_snow * w_snow - wetness;

	// ---- Blend normal maps when any textures enabled ----
	if (use_grass_textures || use_rock_textures || use_snow_textures || use_moss_textures) {
		vec3 blended_nm = n_grass * w_grass + n_rock * w_rock + n_snow * w_snow;
		float total_w = w_grass + w_rock + w_snow + 1e-6;
		float avg_str = (grass_normal_strength * w_grass
			+ rock_normal_strength * w_rock
			+ snow_normal_strength * w_snow) / total_w;
		// Use Godot's built-in normal map pipeline (same approach as Terrain3D main.glsl)
		NORMAL_MAP = blended_nm;
		NORMAL_MAP_DEPTH = avg_str;
	}

	// ---- Ambient occlusion approximation ----
	float ao = 1.0 - (1.0 - slope) * 0.25;
	ao *= 0.90 + 0.10 * smoothstep(0.0, 50.0, height);

	// Apply PBR
	ALBEDO = debug_flat_albedo ? vec3(0.3) : albedo;
	ROUGHNESS = clamp(roughness, 0.0, 1.0);
	AO = clamp(ao, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.5;
}
