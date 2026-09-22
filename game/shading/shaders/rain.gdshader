shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D roof_map : filter_nearest, repeat_disable;
uniform vec2 roof_origin;
uniform vec2 roof_size = vec2(64.0);
uniform float opacity = 0.3;
varying vec3 world_position;
void vertex() {
	// Keep rain vertical, rotate only around Y toward the observer.
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x,0.0,INV_VIEW_MATRIX[0].z));
	world_position = center + right*VERTEX.x + vec3(0.0,VERTEX.y,0.0);
	VERTEX = (inverse(MODEL_MATRIX)*vec4(world_position,1.0)).xyz;
}
void fragment() {
	vec2 uv = (world_position.xz-roof_origin)/roof_size;
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThanEqual(uv,vec2(1.0)))) discard;
	if (world_position.y <= texture(roof_map,uv).r) discard;
	ALBEDO = vec3(0.65,0.78,0.88);
	ALPHA = opacity * (1.0-abs(UV.x*2.0-1.0));
}
