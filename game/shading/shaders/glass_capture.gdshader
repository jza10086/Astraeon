shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform bool depth_pass = false;
uniform vec3 transmission : source_color = vec3(0.7,0.15,0.05);
uniform float far_distance = 256.0;
void fragment() {
	ALBEDO = depth_pass ? vec3(clamp(-VERTEX.z / far_distance, 0.0, 1.0)) : transmission;
}
