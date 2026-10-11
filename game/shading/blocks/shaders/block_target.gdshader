shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 outline_color : source_color = vec3(0.0);
uniform float width_pixels : hint_range(0.5, 5.0) = 2.0;

void fragment() {
	// Selection is interaction feedback, not part of planar reflection captures.
	if ((CAMERA_VISIBLE_LAYERS & 524288u) != 0u) discard;
	vec2 edge_pixels = min(UV, vec2(1.0) - UV) / max(fwidth(UV), vec2(0.000001));
	if (min(edge_pixels.x, edge_pixels.y) > width_pixels) discard;
	ALBEDO = outline_color;
}
