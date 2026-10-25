shader_type spatial;
// Lake and pond surface: two scrolling normal layers, gentle vertex waves,
// fresnel-based opacity and colour, bright specular sun glints.

render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.05, 0.18, 0.24);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.38, 0.42);
uniform vec3 sky_color : source_color = vec3(0.55, 0.68, 0.8);
uniform float wave_height = 0.06;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 0.35 + TIME * 1.1) * wave_height + cos(world_pos.z * 0.29 + TIME * 0.9) * wave_height;
}

void fragment() {
	vec2 uv1 = world_pos.xz * 0.06 + vec2(TIME * 0.012, TIME * 0.007);
	vec2 uv2 = world_pos.xz * 0.11 - vec2(TIME * 0.009, TIME * -0.013);
	vec3 n = normalize(texture(normal_tex, uv1).rgb * 2.0 - 1.0 + texture(normal_tex, uv2).rgb * 2.0 - 1.0);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 body = mix(shallow_color, deep_color, 0.5 + 0.5 * n.x);
	ALBEDO = mix(body, sky_color, fresnel * 0.8);
	ALPHA = mix(0.62, 0.95, fresnel);
	METALLIC = 0.0;
	ROUGHNESS = 0.04;
	SPECULAR = 0.9;
}
