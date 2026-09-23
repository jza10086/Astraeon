uniform sampler2DArray light_pages_0 : filter_nearest, repeat_disable;
uniform sampler2DArray light_pages_1 : filter_nearest, repeat_disable;
uniform sampler2DArray light_pages_2 : filter_nearest, repeat_disable;
uniform sampler2DArray light_pages_3 : filter_nearest, repeat_disable;
uniform sampler2D light_page_table : filter_nearest, repeat_disable;
uniform vec3 light_table_origin;
uniform vec3 light_table_size = vec3(1.0);
uniform int light_page_layers = 1024;
uniform int light_page_shift = 4;
// Resolve once for the common case where all four smoothing taps share a section.
int light_page_slot(vec3 section) {
    vec3 table_cell = section - light_table_origin;
    if (any(lessThan(table_cell, vec3(0.0))) || any(greaterThanEqual(table_cell, light_table_size))) return -1;
    ivec2 address = ivec2(int(table_cell.x), int(table_cell.y + light_table_size.y * table_cell.z));
    vec2 encoded = round(texelFetch(light_page_table, address, 0).rg * 255.0);
    return int(encoded.x + 256.0 * encoded.y) - 1;
}
vec4 light_page_texel(int slot, vec3 local_cell) {
    if (slot < 0) return vec4(0.0);
    int bank = slot / light_page_layers;
    int layer = slot % light_page_layers;
    ivec3 local = ivec3(local_cell);
    ivec3 texel = ivec3(local.x + (layer & ((1 << light_page_shift) - 1)) * 16, local.y + 16 * local.z, layer >> light_page_shift);
    if (bank == 0) return texelFetch(light_pages_0, texel, 0);
    if (bank == 1) return texelFetch(light_pages_1, texel, 0);
    if (bank == 2) return texelFetch(light_pages_2, texel, 0);
    return texelFetch(light_pages_3, texel, 0);
}
vec4 page_light(vec3 world_cell) {
    vec3 section = floor(world_cell / 16.0);
    return light_page_texel(light_page_slot(section), world_cell-section*16.0);
}
vec3 neighboring_light(vec3 local_cell, vec3 section, int slot) {
    if (all(greaterThanEqual(local_cell,vec3(0.0))) && all(lessThan(local_cell,vec3(16.0)))) return light_page_texel(slot,local_cell).rgb;
    return page_light(section*16.0+local_cell).rgb;
}
