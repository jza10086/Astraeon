#include "astraeon_native_generator.h"
#include "../thirdparty/fast_noise/FastNoiseLite.h"
#include "../util/godot/core/class_db.h"
#include <algorithm>
#include <cmath>
#include <chrono>

namespace zylann::voxel {
namespace {
float smooth(float a, float b, float value) {
    const float t = std::clamp((value - a) / (b - a), 0.f, 1.f);
    return t * t * (3.f - 2.f * t);
}
}
void AstraeonNativeGenerator::set_seed(int value) { RWLockWrite lock(_lock); _seed = value; }
int AstraeonNativeGenerator::get_seed() const { RWLockRead lock(_lock); return _seed; }
void AstraeonNativeGenerator::set_biome_layout(int value) {
    ERR_FAIL_COND(value < 0 || value > 1);
    RWLockWrite lock(_lock); _biome_layout = value;
}
int AstraeonNativeGenerator::get_biome_layout() const { RWLockRead lock(_lock); return _biome_layout; }
VoxelGenerator::Result AstraeonNativeGenerator::generate_block(VoxelQueryData input) {
    ERR_FAIL_COND_V(input.lod != 0, Result());
    const auto started = std::chrono::steady_clock::now();
    int seed, layout;
    { RWLockRead lock(_lock); seed = _seed; layout = _biome_layout; }
    fast_noise_lite::FastNoiseLite noise[4];
    const float frequencies[] = {0.0018f, 0.0023f, 0.0031f, 0.018f};
    for (int i = 0; i < 4; ++i) {
        noise[i].SetSeed(int((uint32_t(seed) + uint32_t(i) * 104729u) & 0x7fffffffu));
        noise[i].SetFrequency(frequencies[i]);
        noise[i].SetNoiseType(fast_noise_lite::FastNoiseLite::NoiseType_OpenSimplex2S);
        noise[i].SetFractalType(fast_noise_lite::FastNoiseLite::FractalType_FBm);
        noise[i].SetFractalOctaves(3);
    }
    VoxelBuffer &out = input.voxel_buffer;
    const Vector3i size = out.get_size(), origin = input.origin_in_voxels;
    out.clear_channel(VoxelBuffer::CHANNEL_TYPE, 0);
    for (int z = 0; z < size.z; ++z) for (int x = 0; x < size.x; ++x) {
        const float gx = float(origin.x + x), gz = float(origin.z + z);
        float land = smooth(-0.22f, 0.08f, noise[0].GetNoise(gx, gz));
        float mountain = smooth(0.05f, 0.45f, noise[1].GetNoise(gx, gz)) * land;
        float dry = smooth(-0.05f, 0.3f, noise[2].GetNoise(gx, gz));
        if (layout == 1) {
            const float band = float(((origin.x + x) % 1024 + 1024) % 1024);
            land = 1.f - smooth(736.f, 800.f, band) + smooth(960.f, 1024.f, band);
            mountain = smooth(480.f, 544.f, band) * (1.f - smooth(704.f, 768.f, band));
            dry = smooth(224.f, 288.f, band) * (1.f - smooth(448.f, 512.f, band));
        }
        const float detail = noise[3].GetNoise(gx, gz);
        const int height = std::clamp(int(std::floor(8.f + land * (34.f + detail * (4.f + 5.f * dry)) + mountain * (76.f + detail * 26.f))), -62, 190);
        const bool sandy = land < 0.5f || (mountain <= 0.45f && dry > 0.5f);
        // Fill contiguous column intervals; no per-voxel script/native boundary.
        auto fill = [&](int id, int bottom, int top) {
            bottom = std::clamp(bottom - origin.y, 0, size.y);
            top = std::clamp(top - origin.y, 0, size.y);
            if (top > bottom) out.fill_area(id, Vector3i(x, bottom, z), Vector3i(x + 1, top, z + 1), VoxelBuffer::CHANNEL_TYPE);
        };
        fill(1, -64, height - 3);
        fill(sandy ? 4 : 2, height - 3, height);
        fill(sandy ? 4 : 3, height, height + 1);
        fill(5, height + 1, 32);
    }
    out.compress_uniform_channels();
    ++_blocks;
    _usec += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
    return Result();
}
Dictionary AstraeonNativeGenerator::get_metrics() const { Dictionary d; d["blocks"] = _blocks.load(); d["usec"] = _usec.load(); return d; }
void AstraeonNativeGenerator::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_metrics"), &AstraeonNativeGenerator::get_metrics);
    ClassDB::bind_method(D_METHOD("set_seed", "value"), &AstraeonNativeGenerator::set_seed);
    ClassDB::bind_method(D_METHOD("get_seed"), &AstraeonNativeGenerator::get_seed);
    ClassDB::bind_method(D_METHOD("set_biome_layout", "value"), &AstraeonNativeGenerator::set_biome_layout);
    ClassDB::bind_method(D_METHOD("get_biome_layout"), &AstraeonNativeGenerator::get_biome_layout);
    ADD_PROPERTY(PropertyInfo(Variant::INT, "seed"), "set_seed", "get_seed");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "biome_layout", PROPERTY_HINT_ENUM, "Natural,Test bands"), "set_biome_layout", "get_biome_layout");
}
}
