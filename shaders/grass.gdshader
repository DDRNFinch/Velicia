shader_type spatial;
// Grass blades: colour sampled from the terrain grass texture at the blade's
// world position (so blades match the ground), darker roots, wind gusts and a
// distance fade so the grass ring around the player has no hard edge.

render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float ground_tile = 0.22;
uniform float wind_strength = 0.35;
uniform float fade_start = 18.0;
uniform float fade_end = 26.0;

varying vec3 base_world;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	base_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = COLOR.a; // 0 at root, 1 at tip
	vec2 gust_uv = wp.xz * 0.02 + vec2(TIME * 0.05, TIME * 0.03);
	float gust = texture(noise_tex, gust_uv).r;
	float sway = sin(TIME * 2.2 + wp.x * 0.6 + wp.z * 0.4) * 0.3 + gust * 1.2;
	VERTEX.x += sway * wind_strength * h * h;
	VERTEX.z += sway * wind_strength * 0.5 * h * h;
}

void fragment() {
	float dist = length(base_world - CAMERA_POSITION_WORLD);
	// Ordered dither fade so distant blades thin out instead of popping.
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	vec2 sp = floor(FRAGCOORD.xy);
	float dither = fract(sin(dot(sp, vec2(12.9898, 78.233))) * 43758.5453);
	if (fade < dither) {
		discard;
	}
	vec3 ground = texture(grass_albedo, base_world.xz * ground_tile).rgb;
	float h = COLOR.a;
	ALBEDO = ground * mix(0.75, 1.25, h) * COLOR.rgb;
	ROUGHNESS = 0.85;
}
