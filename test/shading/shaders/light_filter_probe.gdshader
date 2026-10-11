shader_type canvas_item;
render_mode unshaded;
#include "res://game/shading/shaders/light_pages.gdshaderinc"
uniform float block_curve = 1.6;
#include "res://game/shading/shaders/light_sampling.gdshaderinc"
uniform vec3 probe_origin = vec3(-2.0,0.0,0.5);
uniform float probe_width = 4.0;
uniform bool response_probe = false;
void fragment() {
    vec3 p = probe_origin + vec3(UV.x*probe_width,0.0,0.0);
    vec3 cell = floor(p+vec3(0.0,0.02,0.0));
    vec3 section = floor(cell/16.0);
    int slot = light_page_slot(section);
    vec3 c = light_page_texel(slot,cell-section*16.0).rgb;
    vec2 value = smooth_surface_light(p,vec3(0,1,0),c,section,slot);
    COLOR = response_probe ? vec4(vec3(block_light_response(UV.x)),1.0) : vec4(value,0.0,1.0);
}
