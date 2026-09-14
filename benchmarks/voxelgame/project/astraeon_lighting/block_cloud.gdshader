shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 cloud_lit : source_color = vec3(0.9);
uniform vec3 cloud_horizon : source_color = vec3(0.65,0.8,1.0);
uniform vec3 light_direction = vec3(0,1,0);
varying vec3 world_normal;
varying vec3 world_position;
void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	float brightness = 0.68 + normalize(world_normal).y * 0.18 + max(dot(normalize(world_normal),light_direction),0.0) * 0.18;
	float distance = length(world_position.xz - CAMERA_POSITION_WORLD.xz);
	ALBEDO = mix(cloud_lit * brightness, cloud_horizon, smoothstep(500.0,740.0,distance));
}
