// Rendering controls never change authoritative 0..15 light propagation.
uniform int light_filter_mode = 2; // 0 cell, 1 bilinear, 2 quadratic B-spline
uniform float block_smoothing = 1.0;
uniform int block_response_mode = 0; // 0 adjustable power, 1 normalized MakeUp-style
// B marks transmissive cells (opacity < 15), including leaves. Unknown cells never contribute light.
vec3 cell_light(vec3 cell) { return page_light(cell).rgb; }
vec2 linear_surface_light(vec3 position, vec3 normal, vec3 c0, vec3 section, int slot) {
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

// Compact positive quadratic kernel: continuous slope, no overshoot/ringing.
// Taps stay on the receiving side of the surface, within a one-cell halo.
vec3 quadratic_weights(float t) {
    return vec3(0.5 * (0.5-t)*(0.5-t), 0.75-t*t, 0.5 * (0.5+t)*(0.5+t));
}
vec2 smooth_surface_light(vec3 position, vec3 normal, vec3 c0, vec3 section, int slot) {
    if (light_filter_mode == 0) return c0.rg;
    if (light_filter_mode == 1) return linear_surface_light(position,normal,c0,section,slot);
    vec3 q = position + normal * 0.02;
    vec3 anchor = floor(q);
    vec3 a = abs(normal);
    vec3 u = a.x > 0.5 ? vec3(0,1,0) : vec3(1,0,0);
    vec3 v = a.z > 0.5 ? vec3(0,1,0) : vec3(0,0,1);
    vec3 local = anchor-section*16.0;
    vec3 wu = quadratic_weights(dot(q-anchor-0.5,u));
    vec3 wv = quadratic_weights(dot(q-anchor-0.5,v));
    vec3 left = neighboring_light(local-u,section,slot);
    vec3 right = neighboring_light(local+u,section,slot);
    vec3 down = neighboring_light(local-v,section,slot);
    vec3 up = neighboring_light(local+v,section,slot);
    vec3 taps[9];
    taps[0] = neighboring_light(local-u-v,section,slot) * left.b * down.b;
    taps[1] = down;
    taps[2] = neighboring_light(local+u-v,section,slot) * right.b * down.b;
    taps[3] = left;
    taps[4] = c0;
    taps[5] = right;
    taps[6] = neighboring_light(local-u+v,section,slot) * left.b * up.b;
    taps[7] = up;
    taps[8] = neighboring_light(local+u+v,section,slot) * right.b * up.b;
    vec2 sum = vec2(0.0);
    float total = 0.0;
    for (int y=0; y<3; y++) {
        for (int x=0; x<3; x++) {
            vec3 tap = taps[x+y*3];
            float weight = wu[x]*wv[y]*tap.b*c0.b;
            sum += tap.rg*weight;
            total += weight;
        }
    }
    return sum/max(total,0.0001);
}
// MakeUp light_vertex uses x^1.5 + (1.17*x)^6. Normalize at level 15
// so choosing a response does not silently multiply the energy slider.
float block_light_response(float value) {
    float x = clamp(value,0.0,1.0);
    if (block_response_mode == 0) return pow(x,block_curve);
    float boost = pow(1.17,6.0);
    float x2 = x*x;
    return (x*sqrt(x) + boost*x2*x2*x2)/(1.0+boost);
}
