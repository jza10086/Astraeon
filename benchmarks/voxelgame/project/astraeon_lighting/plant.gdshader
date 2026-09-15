shader_type spatial;
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled, cull_disabled;
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
uniform float ambient_curve = 1.4;
uniform float block_grid_strength = 1.0;
#include "res://astraeon_lighting/cloud_shadow.gdshaderinc"
#include "res://astraeon_lighting/light_sampling.gdshaderinc"
uniform bool grass = false;
uniform bool reflection_plants = true;
uniform bool wind_enabled = true;
uniform float wind_clock = 0.0;
uniform float wind_strength = 0.12;
uniform float translucency = 0.25;
varying vec3 world_position;
varying vec3 world_normal;
varying float sky_visibility;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	if (wind_enabled) {
		float anchor = grass ? clamp(VERTEX.y + 0.65, 0.0, 1.0) : clamp((world_position.y - 1.0) / 8.0, 0.0, 1.0);
		VERTEX.x += sin(wind_clock * 1.4 + world_position.x * 0.7 + world_position.z * 0.4) * wind_strength * anchor;
	}
}

#include "res://astraeon_lighting/reflection_clip.gdshaderinc"
void fragment() {
	if ((CAMERA_VISIBLE_LAYERS & 524288u) != 0u && !reflection_plants) discard;
	if (reflection_clipped(world_position, CAMERA_VISIBLE_LAYERS)) discard;
	vec2 p = abs(UV - vec2(0.5));
	float mask = grass ? step(p.x, 0.09 + UV.y * 0.38) : step(p.x * 0.65 + p.y, 0.61);
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Light is sampled at the undeformed position, shared by render and shadow meshes.
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
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float pattern = mix(1.0, mix(0.85, 1.0, smoothstep(0.0, 0.035, edge)), block_grid_strength);
	ALBEDO = base_color.rgb * mix(vec3(1.0), COLOR.rgb, ao_strength) * pattern;
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * (sky_color * ambient
		+ block_color * block_energy * indirect_strength * pow(indirect, block_curve));
	EMISSION += base_color.rgb * self_emission;
}

void light() {
	float visibility = LIGHT_IS_DIRECTIONAL ? sky_visibility * cloud_visibility(world_position) : 1.0;
	// Sky visibility prevents direct light in sealed rooms even with shadows off.
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION
		* LIGHT_COLOR * visibility / PI;
	DIFFUSE_LIGHT += max(-dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR * translucency * visibility / PI;
}
