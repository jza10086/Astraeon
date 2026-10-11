#include "res://game/shading/shaders/glass_receiver.gdshaderinc"
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 water_bounds_min = vec3(12.0,-5.0,-25.0);
uniform vec3 water_bounds_max = vec3(28.0,0.75,-9.0);
uniform bool water_visible = true;
uniform bool depth_absorption = true;
uniform bool waves_enabled = true;
uniform bool reflection_enabled = true;
uniform float clock = 0.0;
uniform float wave_strength = 0.12;
uniform float wave_scale = 1.0;
uniform vec3 water_shallow_color : source_color = vec3(0.06, 0.4, 0.36);
uniform vec3 water_deep_color : source_color = vec3(0.012, 0.075, 0.15);
uniform float water_absorption = 0.22;
uniform float water_opacity = 1.0;
uniform float water_low_opacity = 0.65;
uniform float water_roughness = 0.22;
uniform float water_specular = 0.45;
uniform float water_sky_strength = 1.0;
#ifdef WATER_SSR
#include "res://game/shading/shaders/water_ssr.gdshaderinc"
#endif
#ifdef WATER_PLANAR
#include "res://game/shading/shaders/water_planar.gdshaderinc"
#endif
uniform vec3 sky_color : source_color = vec3(0.4, 0.5, 0.65);
#include "res://game/shading/shaders/cloud_shadow.gdshaderinc"
#include "res://game/shading/shaders/water_appearance.gdshaderinc"
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (waves_enabled && NORMAL.y > 0.5) {
		float a = world_position.x * 0.7 * wave_scale + clock * 1.3;
		float b = world_position.z * 0.5 * wave_scale + clock * 0.9;
		VERTEX.y += (sin(a) + sin(b)) * wave_strength * 0.5;
		NORMAL = normalize(vec3(-cos(a) * 0.35 * wave_strength * wave_scale, 1.0, -cos(b) * 0.25 * wave_strength * wave_scale));
	}
}
void fragment() {
	if (!water_visible || (CAMERA_VISIBLE_LAYERS & 524288u) != 0u) discard;
	vec3 surface_world = (INV_VIEW_MATRIX * vec4(VERTEX,1.0)).xyz;
    if (waves_enabled && abs((mat3(INV_VIEW_MATRIX)*NORMAL).y) > 0.5) {
        vec2 slope = water_slopes(surface_world,clock,CAMERA_POSITION_WORLD);
        vec3 world_normal = normalize(vec3(-slope.x,1.0,-slope.y));
        NORMAL = normalize(mat3(VIEW_MATRIX)*world_normal);
        if (!FRONT_FACING) NORMAL = -NORMAL;
    }
    float thickness = 3.0; // Uniform low-quality fallback, identical across the pool.
	if (depth_absorption && FRONT_FACING) {
		vec3 surface = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 ray = normalize(surface - CAMERA_POSITION_WORLD);
		// Clip to finite water bounds when a ray reaches a bank or misses scene depth.
		vec3 safe_ray = mix(vec3(-0.00001), vec3(0.00001), step(vec3(0.0),ray));
		safe_ray = mix(safe_ray, ray, step(vec3(0.00001), abs(ray)));
		vec3 boundary = mix(water_bounds_min, water_bounds_max + vec3(0.0,wave_strength,0.0), step(vec3(0.0), ray));
		vec3 exit_t = (boundary - surface) / safe_ray;
		float exit_distance = max(0.0, min(exit_t.x, min(exit_t.y,exit_t.z)));
		float depth = texture(scene_depth, SCREEN_UV).r; // Exactly one scene-depth fetch.
		thickness = exit_distance;
		if (depth > 0.000001) {
			// Forward+ / D3D12 reverse Z, NDC depth in [0,1].
			vec4 hit_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
			hit_view /= hit_view.w;
			vec3 hit = (INV_VIEW_MATRIX * hit_view).xyz;
			thickness = clamp(dot(hit - surface, ray), 0.0, exit_distance);
		}
	}
	float absorption = 1.0 - exp(-thickness * water_absorption);
	vec3 tint = mix(water_shallow_color, water_deep_color, absorption);
	float base_alpha = (depth_absorption ? mix(0.03, 0.92, absorption) : water_low_opacity) * water_opacity;
	float fresnel = water_fresnel + (1.0-water_fresnel) * pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 5.0);
	vec3 reflected = vec3(0.0);
	float reflect_weight = 0.0;
	if (FRONT_FACING) {
		float sky_weight = reflection_enabled ? clamp(water_sky_strength * fresnel, 0.0, 1.0) : 0.0;
		vec3 ray = reflect(-normalize(VIEW),normalize(NORMAL));
        reflected = water_sky(surface_world,normalize(mat3(INV_VIEW_MATRIX)*ray)) * sky_weight;
		reflect_weight = sky_weight;
#ifdef WATER_SSR
		vec4 hit = trace_water_reflection(VERTEX, normalize(NORMAL), PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
		float confidence = hit.a * water_ssr_strength;
		reflected = mix(reflected, hit.rgb * fresnel, confidence);
		reflect_weight = mix(reflect_weight, fresnel, confidence);
#endif
#ifdef WATER_PLANAR
		vec3 normal_world = normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
		vec4 planar = sample_planar(surface_world, normal_world);
		float planar_weight = planar.a * planar_strength;
		reflected = mix(reflected, planar.rgb * fresnel, planar_weight);
		reflect_weight = mix(reflect_weight, fresnel, planar_weight);
#endif
	}
	ALPHA = max(base_alpha + (1.0 - base_alpha) * reflect_weight, 0.0001);
	ALBEDO = tint * base_alpha * (1.0 - reflect_weight) / ALPHA;
	EMISSION = reflected / ALPHA;
    if (water_refraction && FRONT_FACING && depth_absorption) {
        vec2 delta_uv = NORMAL.xy*water_refraction_strength/(1.0+length(VERTEX)*0.04);
        delta_uv *= smoothstep(0.0,water_refraction_edge,thickness);
        vec2 uv = clamp(SCREEN_UV+delta_uv,vec2(0.001),vec2(0.999));
        float refracted_depth = texture(scene_depth,uv).r;
        vec4 refracted_hit = INV_PROJECTION_MATRIX*vec4(uv*2.0-1.0,refracted_depth,1.0);
        refracted_hit /= max(refracted_hit.w,0.000001);
        // Reject foreground silhouettes and off-screen samples; never pull a bank into water.
        float valid = step(length(VERTEX)+water_refraction_edge,length(refracted_hit.xyz));
        valid *= step(0.001,SCREEN_UV.x+delta_uv.x)*step(SCREEN_UV.x+delta_uv.x,0.999);
        valid *= step(0.001,SCREEN_UV.y+delta_uv.y)*step(SCREEN_UV.y+delta_uv.y,0.999);
        uv = mix(SCREEN_UV,uv,valid);
        float transmission = (1.0-base_alpha)*(1.0-reflect_weight);
        ALBEDO = tint*base_alpha*(1.0-reflect_weight);
        EMISSION = texture(water_background,uv).rgb*transmission+reflected;
        ALPHA = 1.0;
    }
	ROUGHNESS = water_roughness;
	SPECULAR = water_specular;
}

void light() {
	float shadow = LIGHT_IS_DIRECTIONAL ? cloud_visibility(world_position) : 1.0;
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * (LIGHT_COLOR * (LIGHT_IS_DIRECTIONAL ? glass_transmittance(world_position) : vec3(1.0))) * shadow / PI;
	// Keep the existing water highlight when supplying a custom light function.
	vec3 halfway = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += pow(max(dot(NORMAL, halfway),0.0),mix(256.0, 8.0, water_roughness)) * water_specular * ATTENUATION * (LIGHT_COLOR * (LIGHT_IS_DIRECTIONAL ? glass_transmittance(world_position) : vec3(1.0))) * shadow;
}
