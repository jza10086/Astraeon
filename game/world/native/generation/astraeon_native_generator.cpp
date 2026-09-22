#include "astraeon_native_generator.h"
#include "thirdparty/fast_noise/FastNoiseLite.h"
#include "util/godot/core/class_db.h"
#include <algorithm>
#include <cmath>
#include <chrono>

namespace zylann::voxel {
namespace {
float smooth(float a, float b, float value) {
    const float t = std::clamp((value - a) / (b - a), 0.f, 1.f);
    return t * t * (3.f - 2.f * t);
}
struct Column { int height; bool forest; int biome; };
struct Landscape {
    fast_noise_lite::FastNoiseLite noise[4];
    int layout;
    Landscape(int seed, int p_layout) : layout(p_layout) {
        const float frequencies[] = {0.0018f, 0.003f, 0.004f, 0.018f};
        for (int i = 0; i < 4; ++i) {
            noise[i].SetSeed(int((uint32_t(seed) + uint32_t(i) * 104729u) & 0x7fffffffu));
            noise[i].SetFrequency(frequencies[i]);
            noise[i].SetNoiseType(fast_noise_lite::FastNoiseLite::NoiseType_OpenSimplex2S);
            noise[i].SetFractalType(fast_noise_lite::FastNoiseLite::FractalType_FBm);
            noise[i].SetFractalOctaves(3);
        }
    }
    Column sample(int x, int z) const {
        float land = smooth(-0.2f, 0.12f, noise[0].GetNoise(float(x), float(z)));
        float river = 1.f - smooth(0.018f, 0.065f, std::abs(noise[1].GetNoise(float(x), float(z))));
        bool forest = noise[2].GetNoise(float(x), float(z)) > 0.05f;
        if (layout == 1) {
            const int band = (x % 1024 + 1024) % 1024;
            land = 1.f - smooth(736.f, 800.f, float(band));
            river = 1.f - smooth(8.f, 24.f, std::abs(float(band) - 640.f));
            forest = band >= 256 && band < 512;
        }
        const float detail = noise[3].GetNoise(float(x), float(z));
        const float ground = 20.f + land * (22.f + detail * 3.f);
        const int height = int(std::floor(ground + river * land * (27.f - ground)));
        const int biome = land < 0.5f ? 3 : (river > 0.5f ? 2 : (forest ? 1 : 0));
        return {height, forest && height >= 34 && land > 0.9f && river < 0.05f, biome};
    }
};
uint32_t tree_hash(int x, int z, int seed) {
    uint32_t h = uint32_t(x) * 0x9e3779b9u ^ uint32_t(z) * 0x85ebca6bu ^ uint32_t(seed);
    h ^= h >> 16; h *= 0x7feb352du; h ^= h >> 15; h *= 0x846ca68bu; return h ^ (h >> 16);
}
int floor8(int v) { return v >= 0 ? v / 8 : (v + 1) / 8 - 1; }
}
bool AstraeonNativeGenerator::configure_content(PackedStringArray keys) {
    RWLockWrite lock(_lock);
    if (_configured || keys.size() < 2 || keys.size() > 65536 || keys[0] != "astraeon_air/default") return false;
    int grass = -1, dirt = -1, leaves = -1, log = -1, water = -1;
    for (int i = 0; i < keys.size(); ++i) {
        for (int j = 0; j < i; ++j) if (keys[i] == keys[j]) return false;
        if (keys[i] == "astraeon_grass/default") grass = i;
        if (keys[i] == "astraeon_dirt/default") dirt = i;
        if (keys[i] == "astraeon_leaves/default") leaves = i;
        if (keys[i] == "astraeon_log/axis_y") log = i;
        if (keys[i] == "astraeon_water/default") water = i;
    }
    if (grass < 0 || dirt < 0 || leaves < 0 || log < 0 || water < 0) return false;
    _grass = grass; _dirt = dirt; _leaves = leaves; _log = log; _water = water; _configured = true;
    return true;
}
void AstraeonNativeGenerator::set_seed(int value) { RWLockWrite lock(_lock); _seed = value; }
int AstraeonNativeGenerator::get_seed() const { RWLockRead lock(_lock); return _seed; }
void AstraeonNativeGenerator::set_biome_layout(int value) {
    ERR_FAIL_COND(value < 0 || value > 1);
    RWLockWrite lock(_lock); _biome_layout = value;
}
int AstraeonNativeGenerator::get_biome_layout() const { RWLockRead lock(_lock); return _biome_layout; }
Dictionary AstraeonNativeGenerator::sample_column(int x, int z) const {
    RWLockRead lock(_lock);
    const Column c = Landscape(_seed, _biome_layout).sample(x, z);
    Dictionary d; d["height"] = c.height; d["biome"] = c.biome; d["forest"] = c.forest; return d;
}
VoxelGenerator::Result AstraeonNativeGenerator::generate_block(VoxelQueryData input) {
    ERR_FAIL_COND_V(input.lod != 0, Result());
    const auto started = std::chrono::steady_clock::now();
    int seed, layout, grass, dirt, leaves, log, water;
    { RWLockRead lock(_lock);
      ERR_FAIL_COND_V(!_configured, Result());
      seed = _seed; layout = _biome_layout; grass = _grass; dirt = _dirt; leaves = _leaves; log = _log; water = _water; }
    const Landscape landscape(seed, layout);
    VoxelBuffer &out = input.voxel_buffer;
    const Vector3i size = out.get_size(), origin = input.origin_in_voxels;
    out.clear_channel(VoxelBuffer::CHANNEL_TYPE, 0);
    for (int z = 0; z < size.z; ++z) for (int x = 0; x < size.x; ++x) {
        const Column c = landscape.sample(origin.x + x, origin.z + z);
        auto fill = [&](int id, int bottom, int top) {
            bottom = std::clamp(bottom - origin.y, 0, size.y);
            top = std::clamp(top - origin.y, 0, size.y);
            if (top > bottom) out.fill_area(id, Vector3i(x, bottom, z), Vector3i(x + 1, top, z + 1), VoxelBuffer::CHANNEL_TYPE);
        };
        fill(dirt, -64, c.height);
        fill(c.height >= 32 ? grass : dirt, c.height, c.height + 1);
        fill(water, c.height + 1, 32);
    }
    // World-grid anchors and a canopy halo make results independent of section boundaries/order.
    for (int cz = floor8(origin.z - 2); cz <= floor8(origin.z + size.z - 1 + 2); ++cz)
    for (int cx = floor8(origin.x - 2); cx <= floor8(origin.x + size.x - 1 + 2); ++cx) {
        const uint32_t h = tree_hash(cx, cz, seed);
        if ((h & 3u) == 0) continue;
        const int tx = cx * 8 + 2 + int((h >> 2) % 3), tz = cz * 8 + 2 + int((h >> 4) % 3);
        const Column c = landscape.sample(tx, tz);
        if (!c.forest || (std::abs(tx) < 8 && std::abs(tz) < 8)) continue;
        const int top = c.height + 4 + int((h >> 8) % 3);
        auto put = [&](int x, int y, int z, int id, bool only_air) {
            const Vector3i p(x - origin.x, y - origin.y, z - origin.z);
            if (p.x < 0 || p.y < 0 || p.z < 0 || p.x >= size.x || p.y >= size.y || p.z >= size.z) return;
            if (!only_air || out.get_voxel(p, VoxelBuffer::CHANNEL_TYPE) == 0) out.set_voxel(id, p, VoxelBuffer::CHANNEL_TYPE);
        };
        for (int y = c.height + 1; y <= top; ++y) put(tx, y, tz, log, false);
        for (int y = top - 2; y <= top + 1; ++y) for (int dz = -2; dz <= 2; ++dz) for (int dx = -2; dx <= 2; ++dx) {
            if (y == top + 1 && std::abs(dx) + std::abs(dz) > 1) continue;
            if (std::abs(dx) == 2 && std::abs(dz) == 2) continue;
            put(tx + dx, y, tz + dz, leaves, true);
        }
    }
    out.compress_uniform_channels();
    ++_blocks;
    _usec += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return Result();
}
Dictionary AstraeonNativeGenerator::get_metrics() const { Dictionary d; d["blocks"] = _blocks.load(); d["usec"] = _usec.load(); return d; }
void AstraeonNativeGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure_content", "keys"), &AstraeonNativeGenerator::configure_content);
    ClassDB::bind_method(D_METHOD("sample_column", "x", "z"), &AstraeonNativeGenerator::sample_column);
    ClassDB::bind_method(D_METHOD("get_metrics"), &AstraeonNativeGenerator::get_metrics);
    ClassDB::bind_method(D_METHOD("set_seed", "value"), &AstraeonNativeGenerator::set_seed);
    ClassDB::bind_method(D_METHOD("get_seed"), &AstraeonNativeGenerator::get_seed);
    ClassDB::bind_method(D_METHOD("set_biome_layout", "value"), &AstraeonNativeGenerator::set_biome_layout);
    ClassDB::bind_method(D_METHOD("get_biome_layout"), &AstraeonNativeGenerator::get_biome_layout);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "biome_layout", PROPERTY_HINT_ENUM, "Natural,Test bands"), "set_biome_layout", "get_biome_layout");
}
}
