shader_type spatial;
// Character skin. Vertex colour carries face paint masks written by
// tools/build_characters.py: r = eyebrows, g = lips, b = eye-socket shading.

uniform vec4 skin_color : source_color = vec4(0.78, 0.6, 0.47, 1.0);
uniform vec4 brow_color : source_color = vec4(0.2, 0.13, 0.08, 1.0);
uniform vec4 lip_color : source_color = vec4(0.66, 0.36, 0.34, 1.0);
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 9.0;
uniform float detail_strength = 1.0;
uniform float normal_strength = 0.5;
uniform float roughness_value = 0.58;
uniform float rim = 0.18;

void fragment() {
	vec2 uv = UV * detail_scale;
	vec3 d = mix(vec3(1.0), texture(detail_albedo, uv).rgb, detail_strength);
	vec3 col = skin_color.rgb * d;
	col = mix(col, lip_color.rgb * d, clamp(COLOR.g, 0.0, 1.0) * 0.8);
	col = mix(col, brow_color.rgb, clamp(COLOR.r, 0.0, 1.0) * 0.92);
	col *= 1.0 - clamp(COLOR.b, 0.0, 1.0) * 0.22;
	// Soft warm rim, a cheap stand-in for subsurface scattering.
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	col += skin_color.rgb * vec3(1.0, 0.55, 0.45) * f * rim;
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.35;
	NORMAL_MAP = texture(detail_normal, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
