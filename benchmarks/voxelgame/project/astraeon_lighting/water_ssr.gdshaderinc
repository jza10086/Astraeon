// Transparent water cannot receive Environment SSR. Trace the opaque depth buffer locally.
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform int water_ssr_steps = 32;
uniform float water_ssr_strength = 1.0;
uniform float water_ssr_distance = 48.0;
uniform float water_ssr_tolerance = 0.3;
uniform float water_ssr_edge_fade = 0.08;

vec4 trace_water_reflection(vec3 surface, vec3 normal, mat4 projection, mat4 inverse_projection) {
	vec3 ray = normalize(reflect(normalize(surface), normal));
	vec3 origin = surface + normal * 0.06;
	float previous_t = 0.0;
	bool was_in_front = false;
	for (int i = 1; i <= water_ssr_steps; i++) {
		float fraction = float(i) / float(water_ssr_steps);
		float t = 0.08 + fraction * fraction * water_ssr_distance;
		vec3 point = origin + ray * t;
		vec4 clip = projection * vec4(point, 1.0);
		if (clip.w <= 0.0) break;
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) break;
		float depth = textureLod(scene_depth, uv, 0.0).r;
		if (depth <= 0.000001) { previous_t = t; was_in_front = false; continue; }
		vec4 scene = inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
		float gap = scene.z / scene.w - point.z;
		if (gap >= 0.0 && was_in_front) {
			float lo = previous_t;
			float hi = t;
			// Refine the first crossing to avoid fixed-step reflection stripes.
			for (int refine = 0; refine < 5; refine++) {
				float mid = (lo + hi) * 0.5;
				vec3 probe = origin + ray * mid;
				vec4 projected = projection * vec4(probe,1.0);
				uv = projected.xy / projected.w * 0.5 + 0.5;
				depth = textureLod(scene_depth,uv,0.0).r;
				scene = inverse_projection * vec4(uv*2.0-1.0,depth,1.0);
				gap = scene.z / scene.w - probe.z;
				if (gap >= 0.0 && depth > 0.000001) hi = mid; else lo = mid;
			}
			point = origin + ray * hi;
			clip = projection * vec4(point,1.0);
			uv = clip.xy / clip.w * 0.5 + 0.5;
			depth = textureLod(scene_depth,uv,0.0).r;
			scene = inverse_projection * vec4(uv*2.0-1.0,depth,1.0);
			gap = scene.z / scene.w - point.z;
			if (depth > 0.000001 && gap >= 0.0 && gap < water_ssr_tolerance) {
				vec2 edge = min(uv,1.0-uv);
				float fade = smoothstep(0.0,water_ssr_edge_fade,min(edge.x,edge.y));
				fade *= 1.0-smoothstep(water_ssr_distance*0.75,water_ssr_distance,hi);
				return vec4(textureLod(scene_color,uv,water_roughness*4.0).rgb,fade);
			}
			return vec4(0.0);
		}
		was_in_front = gap < 0.0;
		previous_t = t;
	}
	return vec4(0.0);
}
