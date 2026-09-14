shader_type spatial;
render_mode blend_mix, cull_disabled, ambient_light_disabled;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool depth_absorption = true;
uniform bool waves_enabled = true;
uniform bool reflection_enabled = true;
uniform float clock = 0.0;
uniform float wave_strength = 0.12;
uniform vec3 sky_color : source_color = vec3(0.4, 0.5, 0.65);
uniform vec3 horizon : source_color = vec3(0.6, 0.78, 0.95);
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (waves_enabled) {
		float a = world_position.x * 0.7 + clock * 1.3;
		float b = world_position.z * 0.5 + clock * 0.9;
		VERTEX.y += (sin(a) + sin(b)) * wave_strength * 0.5;
		NORMAL = normalize(vec3(-cos(a) * 0.35 * wave_strength, 1.0, -cos(b) * 0.25 * wave_strength));
	}
}
void fragment() {
	float thickness = 3.0; // Uniform low-quality fallback, identical across the pool.
	if (depth_absorption && FRONT_FACING) {
		vec3 surface = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 ray = normalize(surface - CAMERA_POSITION_WORLD);
		// Clip to finite water bounds when a ray reaches a bank or misses scene depth.
		vec3 safe_ray = mix(vec3(-0.00001), vec3(0.00001), step(vec3(0.0),ray));
		safe_ray = mix(safe_ray, ray, step(vec3(0.00001), abs(ray)));
		vec3 boundary = mix(vec3(12.0,-5.0,-25.0), vec3(28.0,0.75 + wave_strength,-9.0), step(vec3(0.0), ray));
		vec3 exit_t = (boundary - surface) / safe_ray;
		float exit_distance = max(0.0, min(exit_t.x, min(exit_t.y,exit_t.z)));
		float depth = texture(scene_depth, SCREEN_UV).r; // Exactly one scene-depth fetch.
		thickness = exit_distance;
		if (depth > 0.000001) {
			// Forward+ / D3D12 reverse Z, NDC depth in [0,1].
			vec4 hit_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
			hit_view /= hit_view.w;
			vec3 hit = (INV_VIEW_MATRIX * hit_view).xyz;
			thickness = clamp(dot(hit - surface, ray), 0.0, exit_distance);
		}
	}
	float absorption = 1.0 - exp(-thickness * 0.22);
	ALBEDO = mix(vec3(0.06, 0.4, 0.36), vec3(0.012, 0.075, 0.15), absorption);
	float fresnel = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 5.0);
	EMISSION = ALBEDO * sky_color * 0.35;
	if (reflection_enabled) {
		EMISSION += mix(sky_color, horizon, 0.65) * (0.04 + 0.8 * fresnel);
	}
	ROUGHNESS = 0.22;
	SPECULAR = 0.45;
	ALPHA = depth_absorption ? mix(0.03, 0.92, absorption) : 0.65;
}
