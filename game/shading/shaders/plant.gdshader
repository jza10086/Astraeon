shader_type spatial;
render_mode diffuse_lambert, cull_disabled;
uniform bool authored_surface = false;
uniform sampler2D authored_orm : filter_nearest;
uniform sampler2D authored_emission : source_color, filter_nearest;
uniform float authored_emission_energy = 0.0;
uniform float emission_multiplier = 1.0;
uniform float authored_specular = 0.5;
uniform bool use_block_atlas = false;
uniform sampler2D block_atlas : source_color, filter_nearest, repeat_disable;
uniform bool block_cutout = false;
uniform float block_alpha_cutoff = 0.5;
#include "res://game/shading/shaders/light_pages.gdshaderinc"
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
uniform bool grass = false;
uniform bool reflection_plants = true;
uniform bool wind_enabled = true;
uniform float wind_clock = 0.0;
uniform float wind_strength = 0.12;
uniform float translucency = 0.25;
varying vec3 world_position;
varying vec3 world_normal;
varying float sky_visibility;
#include "res://game/shading/shaders/surface_material.gdshaderinc"
#include "res://game/shading/shaders/glass_receiver.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (wind_enabled) {
		float anchor = grass ? clamp(VERTEX.y + 0.65, 0.0, 1.0) : clamp((world_position.y - 1.0) / 8.0, 0.0, 1.0);
		VERTEX.x += sin(wind_clock * 1.4 + world_position.x * 0.7 + world_position.z * 0.4) * wind_strength * anchor;
	}
}

#include "res://game/shading/shaders/reflection_clip.gdshaderinc"
void fragment() {
	vec4 block_texel = use_block_atlas ? texture(block_atlas, UV) : vec4(1.0);
	if (block_cutout && block_texel.a < block_alpha_cutoff) discard;
	if ((CAMERA_VISIBLE_LAYERS & 524288u) != 0u && !reflection_plants) discard;
	if (reflection_clipped(world_position, CAMERA_VISIBLE_LAYERS)) discard;
	vec2 p = abs(UV - vec2(0.5));
	float mask = grass ? step(p.x, 0.09 + UV.y * 0.38) : step(p.x * 0.65 + p.y, 0.61);
	ALPHA = use_block_atlas ? block_texel.a : mask;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Light is sampled at the undeformed position, shared by render and shadow meshes.
	vec3 cell = floor(world_position + normalize(world_normal) * 0.02);
	vec3 section = floor(cell / 16.0);
	int slot = light_page_slot(section);
	vec4 sample_light = light_page_texel(slot,cell-section*16.0);
	vec2 illumination = sample_light.rg;
	sky_visibility = illumination.r;
	vec2 filtered = (ambient_smoothing > 0.0 || indirect_strength > 0.0)
		? smooth_surface_light(world_position, normalize(world_normal),sample_light.rgb,section,slot) : illumination;
	float indirect = filtered.g;
	float ambient = pow(max(mix(illumination.r, filtered.r, ambient_smoothing), 0.0), ambient_curve) * ambient_strength;
	vec2 face_uv = use_block_atlas ? vec2(fract(UV.x * 6.0), UV.y) : UV;
	float edge = min(min(face_uv.x, 1.0 - face_uv.x), min(face_uv.y, 1.0 - face_uv.y));
	float pattern = mix(1.0, mix(0.85, 1.0, smoothstep(0.0, 0.035, edge)), block_grid_strength);
	ALBEDO = base_color.rgb * block_texel.rgb * mix(vec3(1.0), COLOR.rgb, ao_strength) * pattern;
	vec3 orm = authored_surface ? texture(authored_orm, UV).rgb : vec3(1.0);
	float wet = surface_wetness(world_position, normalize(world_normal));
	ALBEDO *= 1.0 - wet * wet_darken;
	ROUGHNESS = mix(material_roughness * orm.g, wet_roughness, wet);
	surface_specular = mix(material_specular * (authored_surface ? authored_specular * 2.0 : 1.0), wet_specular, wet);
	surface_metallic = authored_surface ? 1.0-(1.0-orm.b)*(1.0-material_metallic) : material_metallic;
	METALLIC = surface_metallic;
	SPECULAR = surface_specular;
	IRRADIANCE = vec4(sky_color * ambient * (1.0-ambient_minimum) + ambient_minimum_color * ambient_minimum
		+ block_color * block_energy * indirect_strength * pow(indirect, block_curve), 1.0);
	// Attenuate sky specular indoors; keep a configurable environment floor.
	RADIANCE = vec4(vec3(0.0), 1.0-clamp(max(ambient,ambient_minimum),0.0,1.0));
	EMISSION = authored_surface ? texture(authored_emission, UV).rgb * authored_emission_energy * emission_multiplier : base_color.rgb * self_emission;
}

void light() {
	float visibility = LIGHT_IS_DIRECTIONAL ? sky_visibility * cloud_visibility(world_position) : 1.0;
	// Sky visibility prevents direct light in sealed rooms even with shadows off.
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION
		* LIGHT_COLOR * (1.0-surface_metallic) * visibility * (LIGHT_IS_DIRECTIONAL ? glass_transmittance(world_position) : vec3(1.0)) / PI;
	DIFFUSE_LIGHT += max(-dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR * translucency * visibility / PI;
	SPECULAR_LIGHT += surface_highlight(NORMAL, LIGHT, VIEW, ALBEDO, ROUGHNESS, surface_metallic, surface_specular) * LIGHT_COLOR * ATTENUATION * (LIGHT_IS_DIRECTIONAL ? sky_visibility * cloud_visibility(world_position) * glass_transmittance(world_position) : vec3(1.0));
}
