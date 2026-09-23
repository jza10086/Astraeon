uniform sampler2DArray weather_pages : filter_nearest, repeat_disable;
uniform sampler2D weather_page_table : filter_nearest, repeat_disable;
uniform vec2 weather_table_origin;
uniform vec2 weather_table_size = vec2(1.0);
vec3 weather_column(vec2 weather_world_xz) {
    vec2 section = floor(weather_world_xz / 16.0);
    vec2 q = section - weather_table_origin;
    if (any(lessThan(q, vec2(0))) || any(greaterThanEqual(q, weather_table_size))) return vec3(192.0,0.0,0.0);
    vec2 code = round(texelFetch(weather_page_table, ivec2(q), 0).rg * 255.0);
    int slot = int(code.x + 256.0 * code.y) - 1;
    if (slot < 0) return vec3(192.0,0.0,0.0);
    ivec2 local = ivec2(floor(weather_world_xz - section * 16.0));
    return vec3(texelFetch(weather_pages, ivec3(local.x+(slot%16)*16,local.y,slot/16), 0).rg,1.0);
}
