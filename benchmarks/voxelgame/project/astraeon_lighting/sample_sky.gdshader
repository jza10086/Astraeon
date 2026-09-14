shader_type sky;
uniform vec3 zenith : source_color = vec3(0.15, 0.35, 0.7);
uniform vec3 horizon : source_color = vec3(0.65, 0.8, 1.0);
uniform bool enhanced = true;
uniform bool clouds_enabled = true;
uniform float cloud_coverage = 0.45;
uniform float cloud_clock = 0.0;
float cloud_field(vec2 p) {
	// Smooth analytic bands avoid high-frequency hash precision artifacts on D3D12.
	return 0.5 + sin(p.x + sin(p.y * 0.8)) * 0.22
		+ sin(p.y * 1.4 + cos(p.x * 0.6)) * 0.18
		+ sin(p.x * 2.7 + p.y * 1.8) * 0.07;
}
void sky() {
	float height = clamp(EYEDIR.y, 0.0, 1.0);
	COLOR = enhanced ? mix(horizon, zenith, pow(height, 0.45)) : horizon;
	if (clouds_enabled && EYEDIR.y > 0.10) {
		vec2 p = EYEDIR.xz / max(EYEDIR.y, 0.10) * 2.5 + vec2(cloud_clock, cloud_clock * 0.3);
		float n = cloud_field(p);
		float cover = smoothstep(1.0 - cloud_coverage, 1.15 - cloud_coverage, n);
		cover *= smoothstep(0.10, 0.25, EYEDIR.y);
		COLOR = mix(COLOR, mix(horizon, vec3(1.0), 0.35) * clamp(length(horizon), 0.02, 1.0), cover);
	}
}
