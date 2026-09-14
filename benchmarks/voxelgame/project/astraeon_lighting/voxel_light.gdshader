shader_type spatial;
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled;
uniform sampler3D light_volume : filter_nearest, repeat_disable;
uniform vec3 volume_origin;
uniform vec3 volume_size;
uniform vec4 base_color : source_color = vec4(0.65, 0.67, 0.7, 1.0);
uniform vec3 sky_color : source_color = vec3(0.55, 0.68, 1.0);
uniform vec3 block_color : source_color = vec3(1.0, 0.64, 0.32);
uniform float block_energy = 1.3;
uniform float block_curve = 1.6;
uniform float self_emission = 0.0;
varying vec3 world_position;
varying vec3 world_normal;
varying float sky_visibility;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Sample the adjacent air cell, never interpolate through an opaque wall.
	vec3 cell = floor(world_position + normalize(world_normal) * 0.02 - volume_origin);
	vec2 illumination = vec2(0.0);
	if (all(greaterThanEqual(cell, vec3(0.0))) && all(lessThan(cell, volume_size))) {
		illumination = texture(light_volume, (cell + vec3(0.5)) / volume_size).rg;
	}
	sky_visibility = illumination.r;
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float pattern = mix(0.85, 1.0, smoothstep(0.0, 0.035, edge));
	ALBEDO = base_color.rgb * COLOR.rgb * pattern;
	ROUGHNESS = 1.0;
	EMISSION = ALBEDO * (sky_color * illumination.r
		+ block_color * block_energy * pow(illumination.g, block_curve));
	EMISSION += base_color.rgb * self_emission;
}

void light() {
	// Sky visibility prevents direct light in sealed rooms even with shadows off.
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION
		* LIGHT_COLOR * sky_visibility / PI;
}
