shader_type sky;
// Atmospheric sky: height gradient, sun disc and halo, drifting layered
// clouds lit by the sun, and stars at night. Colours are driven by the
// day/night cycle (scripts/world/day_night.gd).

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.7, 0.76, 0.82);
uniform vec3 ground_color : source_color = vec3(0.24, 0.24, 0.22);
uniform vec3 cloud_color : source_color = vec3(0.96, 0.95, 0.92);
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_cover = 0.48;
uniform float star_strength = 0.0;
uniform float sun_size = 0.9995;

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, h));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.25, -h));
	}
	float sd = dot(dir, LIGHT0_DIRECTION);
	vec3 sun = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += sun * pow(max(sd, 0.0), 6.0) * 0.18;
	col += sun * pow(max(sd, 0.0), 64.0) * 0.35;
	if (sd > sun_size) {
		col += sun * 6.0;
	}
	if (h > 0.0) {
		vec2 uv = dir.xz / (h + 0.18) * 0.22;
		vec2 drift = vec2(TIME * 0.004, TIME * 0.0015);
		float n = texture(cloud_noise, uv + drift).r * 0.62 + texture(cloud_noise, uv * 2.9 - drift * 1.7).g * 0.38;
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n);
		float lit = 0.65 + 0.35 * pow(max(sd, 0.0), 3.0);
		vec3 cc = cloud_color * lit * (0.35 + 0.65 * min(LIGHT0_ENERGY, 1.2));
		col = mix(col, cc, c * smoothstep(0.0, 0.12, h) * 0.92);
		if (star_strength > 0.0) {
			vec2 sp = floor(dir.xz / (h + 0.05) * 220.0);
			float star = step(0.9965, fract(sin(dot(sp, vec2(12.9898, 78.233))) * 43758.5453));
			col += vec3(star * star_strength * (1.0 - c));
		}
	}
	COLOR = col;
}
