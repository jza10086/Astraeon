// Directional sky and three independent noise scales; no scene capture for this fallback.
#include "res://game/shading/shaders/sky_appearance.gdshaderinc"
uniform sampler2D water_noise : repeat_enable, filter_linear_mipmap;
uniform float wave_normal_strength = 0.22;
uniform float wave_detail_strength = 0.1;
uniform float wave_detail_scale = 0.3;
uniform float wave_direction = 35.0;
uniform float wave_fade_distance = 100.0;
uniform float water_fresnel = 0.02;
uniform float water_sky_visibility = 1.0;
uniform bool water_cloud_reflection = true;
uniform bool water_clouds_visible = true;
uniform vec3 water_cloud_color : source_color = vec3(0.8);
uniform bool water_refraction = true;
uniform float water_refraction_strength = 0.018;
uniform float water_refraction_edge = 0.25;
uniform sampler2D water_background : hint_screen_texture, repeat_disable, filter_linear;
vec3 water_sky(vec3 position, vec3 direction) {
    vec3 result = evaluate_sky(direction);
    if (water_cloud_reflection && water_clouds_visible && direction.y > 0.015 && position.y < block_cloud_height) {
        float t = (block_cloud_height-position.y)/direction.y;
        vec2 uv = (position.xz + direction.xz*t - block_cloud_offset)/block_cloud_period;
        float cover = texture(block_cloud_mask,uv).r * smoothstep(0.015,0.06,direction.y);
        result = mix(result,water_cloud_color,cover);
    }
    return result * water_sky_visibility;
}
vec2 water_slopes(vec3 position, float time, vec3 camera_position) {
    float angle = radians(wave_direction);
    mat2 rotation = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)));
    vec2 p = rotation*position.xz;
    vec2 a = texture(water_noise,p*0.05*wave_scale+vec2(time*0.025)).rg*2.0-1.0;
    vec2 b = texture(water_noise,p*0.03125*wave_scale-vec2(time*0.018,time*0.025)).rg*2.0-1.0;
    vec2 c = texture(water_noise,p*wave_detail_scale+vec2(time*0.025,-time*0.02)).rg*2.0-1.0;
    float fade = 1.0-smoothstep(wave_fade_distance*0.4,wave_fade_distance,length(position-camera_position));
    return rotation*((a+b)*wave_normal_strength*0.5+c*wave_detail_strength*fade);
}
