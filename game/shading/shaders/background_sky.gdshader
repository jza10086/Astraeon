shader_type sky;
#include "res://game/shading/shaders/sky_appearance.gdshaderinc"
void sky() { COLOR = evaluate_sky(EYEDIR); }
