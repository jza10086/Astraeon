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
uniform int glass_filter_mode = 2;
vec3 glass_tap(vec2 uv, float receiver_depth) {
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) return vec3(1.0);
	float depth = texture(glass_depth_map,uv).r * glass_far;
	return receiver_depth > depth + glass_bias ? texture(glass_color_map,uv).rgb : vec3(1.0);
}
vec3 glass_bilinear(vec2 uv, float depth) {
	vec2 pixel = uv / glass_texel - 0.5;
	vec2 base = (floor(pixel) + 0.5) * glass_texel;
	vec2 f = fract(pixel);
	return mix(mix(glass_tap(base,depth),glass_tap(base+vec2(glass_texel,0.0),depth),f.x),
		mix(glass_tap(base+vec2(0.0,glass_texel),depth),glass_tap(base+vec2(glass_texel),depth),f.x),f.y);
}
vec3 glass_transmittance(vec3 position) {
	if (!glass_active) return vec3(1.0);
	vec4 view = glass_view * vec4(position,1.0);
	vec4 clip = glass_projection * view;
	vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
	uv.y = 1.0-uv.y;
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) return vec3(1.0);
	float depth = -view.z;
	if (glass_filter_mode == 0) return glass_tap(uv,depth);
	if (glass_filter_mode == 2) return glass_bilinear(uv,depth);
	vec3 result = vec3(0.0);
	float weight = 0.0;
	if (glass_filter_mode == 1) {
		for (int i=0;i<4;i++) result += glass_tap(uv + vec2(float(i%2)*2.0-1.0,float(i/2)*2.0-1.0)*glass_filter*glass_texel,depth);
		return result*0.25;
	}
	if (glass_filter_mode == 5) {
		vec2 d=vec2(glass_filter*glass_texel,0.0);
		return glass_tap(uv,depth)*0.4+(glass_tap(uv+d,depth)+glass_tap(uv-d,depth)+glass_tap(uv+d.yx,depth)+glass_tap(uv-d.yx,depth))*0.15;
	}
	if (glass_filter_mode == 3) {
		int radius = 1;
		for (int y=-1;y<=1;y++) for (int x=-1;x<=1;x++) {
			if (abs(x)>radius || abs(y)>radius) continue;
			float w=float((radius+1-abs(x))*(radius+1-abs(y)));
			result += glass_tap(uv+vec2(float(x),float(y))*glass_filter*glass_texel,depth)*w;
			weight += w;
		}
	} else {
		int count = 8;
		for (int i=0;i<8;i++) {
			if(i>=count) break;
			float angle=float(i)*2.39996323;
			vec2 offset=vec2(cos(angle),sin(angle))*sqrt((float(i)+0.5)/float(count));
			result += glass_tap(uv+offset*glass_filter*glass_texel,depth);
			weight += 1.0;
		}
	}
	return result/weight;
}
