shader_type spatial;
render_mode unshaded;
#include "res://astraeon_lighting/reflection_clip.gdshaderinc"
uniform vec3 lamp_color : source_color = vec3(1.0,0.72,0.32);
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	if (reflection_clipped(world_position, CAMERA_VISIBLE_LAYERS)) discard;
	ALBEDO = lamp_color;
	EMISSION = lamp_color*1.5;
}
