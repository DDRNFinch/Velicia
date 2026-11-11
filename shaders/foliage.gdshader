shader_type spatial;
// Leaves and pine needles: alpha-cutout cards with wind sway and soft
// light wrap so canopies don't look flat. Per-instance tint comes from COLOR.

render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.45;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.4;
uniform vec3 tint = vec3(1.0);

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(VERTEX.y, 0.0);
	float phase = wp.x * 0.21 + wp.z * 0.17;
	float sway = sin(TIME * wind_speed + phase) + 0.4 * sin(TIME * wind_speed * 2.3 + phase * 3.0);
	VERTEX.x += sway * wind_strength * h * 0.1;
	VERTEX.z += sway * wind_strength * h * 0.06;
	// Leaf flutter
	VERTEX += NORMAL * sin(TIME * 5.0 + phase * 7.0 + VERTEX.y * 3.0) * 0.02;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * COLOR.rgb * tint * 1.7;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	// Fake translucency: brighten faces turned away from the viewer.
	if (!FRONT_FACING) {
		ALBEDO *= 0.85;
	}
}
