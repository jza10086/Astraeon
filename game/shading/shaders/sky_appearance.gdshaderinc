uniform vec3 zenith : source_color = vec3(0.15,0.35,0.7);
uniform vec3 horizon : source_color = vec3(0.65,0.8,1.0);
uniform bool enhanced = true;
uniform int celestial_mode = 0;
uniform int celestial_shape = 0;
uniform vec3 sun_direction = vec3(0.0,1.0,0.0);
uniform vec3 moon_direction = vec3(0.0,-1.0,0.0);
uniform float sun_radius = 0.00872665;
uniform float moon_radius = 0.01047198;
uniform float disc_edge = 0.000349;
uniform float halo_strength = 0.25;
uniform vec3 sun_tint : source_color = vec3(1.0,0.9,0.7);
uniform vec3 moon_tint : source_color = vec3(0.65,0.75,1.0);
uniform float sun_energy = 5.0;
uniform float moon_energy = 1.0;
uniform sampler2D sun_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D moon_texture : source_color, filter_linear_mipmap, repeat_disable;
vec4 disc(vec3 ray, vec3 direction, float radius, sampler2D tex) {
	float cosine = dot(ray,direction);
	float angle = acos(clamp(cosine,-1.0,1.0));
	vec3 reference = abs(direction.y)>0.99 ? vec3(1.0,0.0,0.0) : vec3(0.0,1.0,0.0);
	vec3 right = normalize(cross(reference,direction));
	vec3 up = cross(direction,right);
	vec2 plane=vec2(dot(ray,right),-dot(ray,up));
	float distance_to_edge = celestial_shape == 0 ? angle : atan(max(abs(plane.x),abs(plane.y)),max(cosine,0.0001));
	float mask = (1.0-smoothstep(radius-disc_edge,radius+disc_edge,distance_to_edge))*step(0.0,cosine);
	vec3 color = vec3(1.0);
	if (celestial_mode == 2 && mask>0.0) {
		vec2 uv=plane/max(2.0*tan(radius)*cosine,0.0001)+0.5;
		vec4 sample_color=texture(tex,uv);
		color=sample_color.rgb;
		mask*=sample_color.a;
	}
	float halo=exp(-angle/max(radius*3.0,0.0001))*halo_strength*(1.0-mask);
	float horizon_fade=smoothstep(-0.02,0.02,direction.y);
	return vec4((color*mask+vec3(halo))*horizon_fade,mask*horizon_fade);
}
vec3 evaluate_sky(vec3 ray) {
	vec3 result = enhanced ? mix(horizon,zenith,pow(clamp(ray.y,0.0,1.0),0.45)) : horizon;
	if (celestial_mode != 0) {
		vec4 sun=disc(ray,normalize(sun_direction),sun_radius,sun_texture);
		vec4 moon=disc(ray,normalize(moon_direction),moon_radius,moon_texture);
		result=result*(1.0-max(sun.a,moon.a))+sun.rgb*sun_tint*sun_energy+moon.rgb*moon_tint*moon_energy;
	}
	return result;
}
