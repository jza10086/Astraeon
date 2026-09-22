// Shared direct-only nearest-glass transmittance. Engine opaque shadows still apply.
uniform bool glass_active = false;
uniform sampler2D glass_depth_map : filter_nearest, repeat_disable;
uniform sampler2D glass_color_map : filter_nearest, repeat_disable;
uniform mat4 glass_view;
uniform mat4 glass_projection;
uniform float glass_far = 256.0;
uniform float glass_bias = 0.08;
uniform float glass_filter = 1.0;
uniform float glass_texel = 0.0009765625;
vec3 glass_transmittance(vec3 position) {
	if (!glass_active) return vec3(1.0);
	vec4 view = glass_view * vec4(position, 1.0);
	vec4 clip = glass_projection * view;
	vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
	uv.y = 1.0 - uv.y;
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) return vec3(1.0);
	vec3 result = vec3(0.0);
	int count = glass_filter > 0.0 ? 4 : 1;
	for (int i=0;i<4;i++) {
		if (i>=count) break;
		vec2 offset = count==1 ? vec2(0.0) : vec2(float(i%2)*2.0-1.0,float(i/2)*2.0-1.0)*glass_filter*glass_texel;
		vec2 sample_uv = clamp(uv+offset,vec2(0.0),vec2(1.0));
		float depth = texture(glass_depth_map,sample_uv).r*glass_far;
		result += -view.z > depth+glass_bias ? texture(glass_color_map,sample_uv).rgb : vec3(1.0);
	}
	return result/float(count);
}
