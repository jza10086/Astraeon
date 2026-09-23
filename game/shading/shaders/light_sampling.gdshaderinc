// B stores open air. Outside the finite volume never contributes light.
vec3 cell_light(vec3 cell) { return page_light(cell).rgb; }
vec2 smooth_surface_light(vec3 position, vec3 normal, vec3 c0, vec3 section, int slot) {
	vec3 q = position + normal * 0.02;
	vec3 anchor = floor(q);
	vec3 a = abs(normal);
	vec3 u = a.x > 0.5 ? vec3(0, 1, 0) : vec3(1, 0, 0);
	vec3 v = a.z > 0.5 ? vec3(0, 1, 0) : vec3(0, 0, 1);
	vec2 offset = vec2(dot(q - anchor - 0.5, u), dot(q - anchor - 0.5, v));
	vec3 du = u * sign(offset.x);
	vec3 dv = v * sign(offset.y);
	vec2 f = abs(offset);
	vec3 local = anchor - section * 16.0;
	vec3 c1 = neighboring_light(local + du,section,slot);
	vec3 c2 = neighboring_light(local + dv,section,slot);
	vec3 c3 = neighboring_light(local + du + dv,section,slot);
	// Never sample across the surface normal; diagonal cannot cut a blocked corner.
	vec4 valid = vec4(c0.b, c1.b, c2.b, c3.b * c1.b * c2.b) * c0.b;
	vec4 weights = vec4((1.0-f.x)*(1.0-f.y), f.x*(1.0-f.y), (1.0-f.x)*f.y, f.x*f.y) * valid;
	return vec2(dot(weights, vec4(c0.r,c1.r,c2.r,c3.r)), dot(weights, vec4(c0.g,c1.g,c2.g,c3.g)))
		/ max(dot(weights,vec4(1.0)), 0.0001);
}
