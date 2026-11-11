shader_type spatial;
// Velicia terrain: blends grass, dirt, rock, sand and snow by per-vertex
// weights (COLOR.r dirt, .g rock, .b sand, .a snow; grass is the remainder).
// Rock uses triplanar projection so cliffs don't stretch. A second texture
// scale and a macro noise hide tiling at distance. Works in Compatibility.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;

uniform float ground_tile = 0.22;
uniform float rock_tile = 0.09;
uniform float macro_strength = 0.22;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy * scale).rgb * w.x
		+ texture(tex, p.xz * scale).rgb * w.y
		+ texture(tex, p.xy * scale).rgb * w.z;
}

void fragment() {
	vec2 uv = world_pos.xz * ground_tile;
	vec2 uv_far = world_pos.xz * ground_tile * 0.23 + vec2(0.37, 0.11);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float far_mix = smoothstep(15.0, 60.0, dist);

	vec3 grass = mix(texture(grass_albedo, uv).rgb, texture(grass_albedo, uv_far).rgb, 0.35 + far_mix * 0.4);
	vec3 dirt = mix(texture(dirt_albedo, uv).rgb, texture(dirt_albedo, uv_far).rgb, 0.3 + far_mix * 0.4);
	vec3 rock = triplanar(rock_albedo, world_pos, world_normal, rock_tile);
	vec3 sand = texture(sand_albedo, uv).rgb;
	vec3 snow = texture(snow_albedo, uv).rgb;

	vec3 gn = texture(grass_normal, uv).rgb;
	vec3 dn = texture(dirt_normal, uv).rgb;
	vec3 rn = texture(rock_normal, world_pos.xz * rock_tile).rgb;

	// Height-aware weights give natural, irregular borders between materials.
	float w_dirt = COLOR.r;
	float w_rock = COLOR.g;
	float w_sand = COLOR.b;
	float w_snow = COLOR.a;
	float detail = texture(macro_noise, world_pos.xz * 0.05).g;
	w_dirt = smoothstep(0.0, 1.0, clamp(w_dirt + (dot(dirt, vec3(0.33)) - 0.3) * 0.8 + (detail - 0.5) * 0.4, 0.0, 1.0));
	w_rock = smoothstep(0.0, 1.0, clamp(w_rock + (dot(rock, vec3(0.33)) - 0.4) * 0.6, 0.0, 1.0));
	float w_grass = max(0.0, 1.0 - w_dirt - w_rock - w_sand - w_snow);
	float total = w_grass + w_dirt + w_rock + w_sand + w_snow + 0.0001;

	vec3 albedo = (grass * w_grass + dirt * w_dirt + rock * w_rock + sand * w_sand + snow * w_snow) / total;
	vec3 nmap = (gn * w_grass + dn * (w_dirt + w_sand) + rn * w_rock + vec3(0.5, 0.5, 1.0) * w_snow) / total;

	float macro = texture(macro_noise, world_pos.xz * 0.006).r;
	albedo *= mix(1.0 - macro_strength, 1.0 + macro_strength * 0.6, macro);

	ALBEDO = albedo;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = mix(1.2, 0.4, far_mix);
	ROUGHNESS = mix(0.92, 0.7, w_snow) - w_rock * 0.08;
	SPECULAR = 0.3;
}
