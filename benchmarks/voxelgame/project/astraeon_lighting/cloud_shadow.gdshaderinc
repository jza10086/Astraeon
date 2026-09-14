// Cloud-bottom projection affects only directional direct lighting at call sites.
uniform sampler2D block_cloud_mask : repeat_enable, filter_nearest;
uniform bool cloud_shadow_enabled = false;
uniform vec2 block_cloud_offset = vec2(0.0);
uniform float block_cloud_period = 768.0;
uniform float block_cloud_height = 90.0;
uniform vec3 cloud_light_direction = vec3(0.0, 1.0, 0.0);
uniform float cloud_shadow_strength = 0.55;
uniform float cloud_shadow_softness = 0.3;
float cloud_visibility(vec3 position) {
	if (!cloud_shadow_enabled || cloud_light_direction.y <= 0.04 || position.y >= block_cloud_height) { return 1.0; }
	float distance = (block_cloud_height - position.y) / cloud_light_direction.y;
	vec2 uv = (position.xz + cloud_light_direction.xz * distance - block_cloud_offset) / block_cloud_period;
	float cover;
	if (cloud_shadow_softness <= 0.001) {
		cover = texture(block_cloud_mask, uv).r;
	} else {
		// Four neighboring texels, continuously interpolate only near their boundary.
		vec2 grid = uv * 32.0 - 0.5;
		vec2 base = floor(grid);
		vec2 f = smoothstep(vec2(0.5 - cloud_shadow_softness * 0.5), vec2(0.5 + cloud_shadow_softness * 0.5), fract(grid));
		float a = texture(block_cloud_mask, (base + vec2(0.5,0.5)) / 32.0).r;
		float b = texture(block_cloud_mask, (base + vec2(1.5,0.5)) / 32.0).r;
		float c = texture(block_cloud_mask, (base + vec2(0.5,1.5)) / 32.0).r;
		float d = texture(block_cloud_mask, (base + vec2(1.5,1.5)) / 32.0).r;
		cover = mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
	}
	return 1.0 - cover * cloud_shadow_strength * smoothstep(0.04, 0.15, cloud_light_direction.y);
}
