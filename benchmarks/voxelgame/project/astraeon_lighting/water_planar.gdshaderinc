uniform sampler2D planar_texture : filter_linear, repeat_disable;
uniform mat4 planar_view_projection;
uniform bool planar_valid = false;
uniform float planar_strength = 1.0;
uniform float planar_distortion = 0.015;
uniform float planar_blur_pixels = 0.0;
uniform float planar_edge_fade = 0.02;
vec4 sample_planar(vec3 world, vec3 normal) {
	if (!planar_valid) return vec4(0.0);
	// Project the undeformed reference plane so small waves don't shift the camera mapping.
	world.y = 0.75;
	vec4 projected = planar_view_projection * vec4(world,1.0);
	if (projected.w <= 0.0) return vec4(0.0);
	vec2 uv = projected.xy / projected.w * vec2(0.5,-0.5) + 0.5;
	uv += normal.xz * planar_distortion;
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) return vec4(0.0);
	vec2 edge = min(uv,1.0-uv);
	float fade = smoothstep(0.0,planar_edge_fade,min(edge.x,edge.y));
	vec3 color;
	if (planar_blur_pixels > 0.0) {
		vec2 radius = vec2(planar_blur_pixels) / vec2(textureSize(planar_texture,0));
		color = (texture(planar_texture,uv+radius).rgb+texture(planar_texture,uv-radius).rgb
			+texture(planar_texture,uv+radius*vec2(-1,1)).rgb+texture(planar_texture,uv+radius*vec2(1,-1)).rgb)*0.25;
	} else { color = texture(planar_texture,uv).rgb; }
	return vec4(color,fade);
}
