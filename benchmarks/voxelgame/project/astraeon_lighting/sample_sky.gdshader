shader_type sky;
render_mode use_half_res_pass;
uniform vec3 zenith : source_color = vec3(0.15, 0.35, 0.7);
uniform vec3 horizon : source_color = vec3(0.65, 0.8, 1.0);
uniform bool enhanced = true;
uniform bool clouds_enabled = true;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform float cloud_coverage = 0.45;
uniform float cloud_clock = 0.0;
uniform int cloud_steps = 24;
uniform bool cloud_morph = false;
// A height-field volume with inexpensive artistic lighting; no physical scattering.
vec4 cloud_layer(vec3 ray, vec2 screen_uv) {
	if (!clouds_enabled || cloud_coverage <= 0.0 || ray.y <= 0.025) { return vec4(0.0); }
	float begin = max(0.0, (90.0 - POSITION.y) / ray.y);
	float end = (120.0 - POSITION.y) / ray.y;
	if (end <= begin) { return vec4(0.0); }
	float step_length = (end - begin) / float(cloud_steps);
	// Fixed screen-space jitter breaks coherent marching bands without temporal history.
	float jitter = fract(52.9829189 * fract(dot(screen_uv * vec2(1920.0,1080.0), vec2(0.06711056,0.00583715))));
	float lod = max(0.0, log2(max(step_length * 512.0 / 550.0, 1.0)));
	float transmission = 1.0;
	vec3 sum = vec3(0.0);
	vec3 lit_color = mix(horizon, vec3(1.0), 0.5) * clamp(length(horizon), 0.015, 1.0);
	for (int i = 0; i < cloud_steps; i++) {
		vec3 p = POSITION + ray * (begin + (float(i) + jitter) * step_length);
		vec2 uv = p.xz / 550.0 + vec2(cloud_clock * 0.04, cloud_clock * 0.013);
		float field = textureLod(cloud_noise, uv, lod).r;
		if (cloud_morph) {
			field = mix(field, textureLod(cloud_noise, uv.yx + vec2(cloud_clock * 0.018,0.37),lod).r,0.4);
		}
		float coverage = smoothstep(0.68 - cloud_coverage * 0.5, 0.90 - cloud_coverage * 0.5, field);
		float half_height = coverage * 15.0;
		float density = smoothstep(0.0, 3.0, half_height - abs(p.y - 105.0)) * coverage;
		float alpha = 1.0 - exp(-density * step_length * 0.08);
		float upper_light = clamp((p.y - (105.0 - half_height)) / max(half_height * 2.0, 0.01), 0.0, 1.0);
		vec3 color = lit_color * mix(0.42, 1.12, upper_light);
		sum += transmission * alpha * color;
		transmission *= 1.0 - alpha;
		if (transmission < 0.015) { break; }
	}
	float fade = smoothstep(0.025, 0.12, ray.y);
	return vec4(sum * fade, (1.0 - transmission) * fade);
}
void sky() {
	vec3 background = enhanced ? mix(horizon, zenith, pow(clamp(EYEDIR.y,0.0,1.0),0.45)) : horizon;
	if (AT_HALF_RES_PASS) {
		vec4 cloud = cloud_layer(EYEDIR, SCREEN_UV);
		COLOR = cloud.rgb;
		ALPHA = cloud.a;
	} else if (AT_CUBEMAP_PASS) {
		// Ambient/reflection are disabled in this lab; avoid repeated cloud integration.
		COLOR = background;
	} else {
		COLOR = background * (1.0 - HALF_RES_COLOR.a) + HALF_RES_COLOR.rgb;
	}
}
