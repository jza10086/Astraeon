// Six canonical face constants. UV face index rotates with geometry, so orientations share data.
uniform bool pack_surface = false;
uniform bool pack_textured = false;
uniform vec4 pack_colors[6] : source_color;
uniform vec2 pack_orm[6];
uniform vec3 pack_glow[6] : source_color;
int pack_face(vec2 uv) { return clamp(int(floor(uv.x * 6.0)), 0, 5); }

uniform int breaking_stage = -1;
uniform vec3 breaking_target = vec3(0.0);
uniform sampler2D breaking_texture : filter_nearest, repeat_disable;
uniform vec4 breaking_tint : source_color = vec4(0.025, 0.02, 0.018, 1.0);
uniform float breaking_strength = 0.9;
float breaking_mask(vec3 pos, vec3 normal, vec2 uv) {
    if (breaking_stage < 0) return 0.0;
    vec3 cell = floor(pos - normalize(normal) * 0.001);
    if (any(notEqual(cell, breaking_target))) return 0.0;
    vec2 size = vec2(textureSize(breaking_texture, 0));
    vec2 face_uv = vec2(fract(uv.x * 6.0), uv.y);
    vec2 texel = clamp(floor(face_uv * size.y), vec2(0.0), vec2(size.y - 1.0));
    vec2 atlas_uv = (texel + vec2(float(breaking_stage) * size.y, 0.0) + vec2(0.5)) / size;
    return texture(breaking_texture, atlas_uv).r * breaking_strength * breaking_tint.a;
}
