uniform bool wet_active = false;
uniform sampler2D wet_map : filter_nearest, repeat_disable;
uniform vec2 wet_origin;
uniform vec2 wet_size = vec2(64.0);
uniform float wet_darken = 0.25;
uniform float wet_roughness = 0.18;
uniform float wet_specular = 0.65;
uniform float material_roughness = 1.0;
uniform float material_metallic = 0.0;
uniform float material_specular = 0.0;
varying float surface_metallic;
varying float surface_specular;
float surface_wetness(vec3 position, vec3 normal) {
	if (!wet_active) return 0.0;
	vec2 uv = (position.xz-wet_origin)/wet_size;
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)))) return 0.0;
	vec2 column = texture(wet_map,uv).rg;
	return column.g * step(column.r-0.08,position.y) * smoothstep(0.0,0.8,normal.y);
}
vec3 surface_highlight(vec3 normal, vec3 light, vec3 view, vec3 albedo, float roughness, float metallic, float specular) {
	float nl=max(dot(normal,light),0.0),nv=max(dot(normal,view),0.001);
	vec3 h=normalize(light+view);
	float nh=max(dot(normal,h),0.0),vh=max(dot(view,h),0.0);
	float a=max(roughness*roughness,0.0025),a2=a*a;
	float d=a2/(3.14159265*pow(nh*nh*(a2-1.0)+1.0,2.0));
	float k=pow(roughness+1.0,2.0)/8.0;
	float g=(nl/(nl*(1.0-k)+k))*(nv/(nv*(1.0-k)+k));
	vec3 f0=mix(vec3(0.08*specular),albedo,metallic);
	vec3 f=f0+(1.0-f0)*pow(1.0-vh,5.0);
	return f*d*g/(4.0*nv+0.0001);
}
