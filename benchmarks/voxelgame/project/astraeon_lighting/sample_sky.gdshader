shader_type sky;
uniform vec3 zenith : source_color = vec3(0.15, 0.35, 0.7);
uniform vec3 horizon : source_color = vec3(0.65, 0.8, 1.0);
uniform bool enhanced = true;
void sky() {
	float height = clamp(EYEDIR.y, 0.0, 1.0);
	COLOR = enhanced ? mix(horizon, zenith, pow(height, 0.45)) : horizon;
}
