shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, ambient_light_disabled;
uniform float water_depth = 2.0;
uniform bool waves_enabled = true;
uniform bool reflection_enabled = true;
uniform float clock = 0.0;
uniform float wave_strength = 0.12;
uniform vec3 sky_color : source_color = vec3(0.4, 0.5, 0.65);
uniform vec3 horizon : source_color = vec3(0.6, 0.78, 0.95);
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Wave phase uses world coordinates so shallow/deep patches meet continuously.
	if (waves_enabled) {
		float a = world_position.x * 0.7 + clock * 1.3;
		float b = world_position.z * 0.5 + clock * 0.9;
		VERTEX.y += (sin(a) + sin(b)) * wave_strength * 0.5;
		NORMAL = normalize(vec3(-cos(a) * 0.35 * wave_strength, 1.0, -cos(b) * 0.25 * wave_strength));
	}
}
void fragment() {
	float absorption = 1.0 - exp(-water_depth * 0.35);
	ALBEDO = mix(vec3(0.06, 0.4, 0.36), vec3(0.012, 0.075, 0.15), absorption);
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 5.0);
	EMISSION = ALBEDO * sky_color * 0.35;
	if (reflection_enabled) {
		EMISSION += mix(sky_color, horizon, 0.65) * (0.04 + 0.8 * fresnel);
	}
	ROUGHNESS = 0.22;
	SPECULAR = 0.45;
	ALPHA = mix(0.45, 0.88, absorption);
}
