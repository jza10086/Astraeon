shader_type spatial;
render_mode diffuse_lambert;
uniform bool use_block_atlas = false;
uniform sampler2D block_atlas : source_color, filter_nearest, repeat_disable;
uniform bool block_cutout = false;
uniform float block_alpha_cutoff = 0.5;
uniform sampler3D light_volume : filter_nearest, repeat_disable;
uniform vec3 volume_origin;
uniform vec3 volume_size;
uniform vec4 base_color : source_color = vec4(0.65, 0.67, 0.7, 1.0);
uniform vec3 sky_color : source_color = vec3(0.55, 0.68, 1.0);
uniform vec3 block_color : source_color = vec3(1.0, 0.64, 0.32);
uniform float block_energy = 1.3;
uniform float block_curve = 1.6;
uniform float self_emission = 0.0;
uniform float ao_strength = 0.65;
uniform float indirect_strength = 0.04;
uniform float ambient_smoothing = 1.0;
uniform float ambient_strength = 1.0;
uniform float ambient_minimum = 0.0;
uniform vec3 ambient_minimum_color : source_color = vec3(0.7,0.75,0.85);
uniform float ambient_curve = 1.4;
uniform float block_grid_strength = 1.0;
#include "res://game/shading/shaders/cloud_shadow.gdshaderinc"
#include "res://game/shading/shaders/light_sampling.gdshaderinc"
varying vec3 world_position;
varying vec3 world_normal;
varying float sky_visibility;
#include "res://game/shading/shaders/surface_material.gdshaderinc"
#include "res://game/shading/shaders/glass_receiver.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

#include "res://game/shading/shaders/reflection_clip.gdshaderinc"
void fragment() {
	vec4 block_texel = use_block_atlas ? texture(block_atlas, UV) : vec4(1.0);
	if (block_cutout && block_texel.a < block_alpha_cutoff) discard;
	if (reflection_clipped(world_position, CAMERA_VISIBLE_LAYERS)) discard;
	// Sample the adjacent air cell, never interpolate through an opaque wall.
	vec3 cell = floor(world_position + normalize(world_normal) * 0.02 - volume_origin);
	vec2 illumination = vec2(0.0);
	if (all(greaterThanEqual(cell, vec3(0.0))) && all(lessThan(cell, volume_size))) {
		illumination = texture(light_volume, (cell + vec3(0.5)) / volume_size).rg;
	}
	sky_visibility = illumination.r;
	vec2 filtered = (ambient_smoothing > 0.0 || indirect_strength > 0.0)
		? smooth_surface_light(world_position, normalize(world_normal)) : illumination;
	float indirect = filtered.g;
	float ambient = pow(max(mix(illumination.r, filtered.r, ambient_smoothing), 0.0), ambient_curve) * ambient_strength;
	vec2 face_uv = use_block_atlas ? vec2(fract(UV.x * 6.0), UV.y) : UV;
	float edge = min(min(face_uv.x, 1.0 - face_uv.x), min(face_uv.y, 1.0 - face_uv.y));
	float pattern = mix(1.0, mix(0.85, 1.0, smoothstep(0.0, 0.035, edge)), block_grid_strength);
	ALBEDO = base_color.rgb * block_texel.rgb * mix(vec3(1.0), COLOR.rgb, ao_strength) * pattern;
	float wet = surface_wetness(world_position, normalize(world_normal));
	ALBEDO *= 1.0 - wet * wet_darken;
	ROUGHNESS = mix(material_roughness, wet_roughness, wet);
	surface_specular = mix(material_specular, wet_specular, wet);
	surface_metallic = material_metallic;
	METALLIC = material_metallic;
	SPECULAR = surface_specular;
	IRRADIANCE = vec4(sky_color * ambient * (1.0-ambient_minimum) + ambient_minimum_color * ambient_minimum
		+ block_color * block_energy * indirect_strength * pow(indirect, block_curve), 1.0);
	// Attenuate sky specular indoors; keep a configurable environment floor.
	RADIANCE = vec4(vec3(0.0), 1.0-clamp(max(ambient,ambient_minimum),0.0,1.0));
	EMISSION = base_color.rgb * self_emission;
}

void light() {
	// Sky visibility prevents direct light in sealed rooms even with shadows off.
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION
		* LIGHT_COLOR * (1.0 - surface_metallic) * (LIGHT_IS_DIRECTIONAL ? sky_visibility * cloud_visibility(world_position) : 1.0) * (LIGHT_IS_DIRECTIONAL ? glass_transmittance(world_position) : vec3(1.0)) / PI;
	SPECULAR_LIGHT += surface_highlight(NORMAL, LIGHT, VIEW, ALBEDO, ROUGHNESS, surface_metallic, surface_specular) * LIGHT_COLOR * ATTENUATION * (LIGHT_IS_DIRECTIONAL ? sky_visibility * cloud_visibility(world_position) * glass_transmittance(world_position) : vec3(1.0));
}
