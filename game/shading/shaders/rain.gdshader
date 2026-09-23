shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
#include "res://game/shading/shaders/weather_pages.gdshaderinc"
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
	vec3 column = weather_column(world_position.xz);
	if (column.b < 0.5 || world_position.y <= column.r) discard;
	ALBEDO = vec3(0.65,0.78,0.88);
	ALPHA = opacity * (1.0-abs(UV.x*2.0-1.0));
}
