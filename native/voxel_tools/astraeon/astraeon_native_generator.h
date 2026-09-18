#pragma once
#include "../generators/voxel_generator.h"
#include "../storage/voxel_buffer.h"
#include "../util/thread/rw_lock.h"
#include <atomic>

namespace zylann::voxel {
// Current generation contract: six stable block IDs, height range [-64, 192).
class AstraeonNativeGenerator : public VoxelGenerator {
    GDCLASS(AstraeonNativeGenerator, VoxelGenerator)
public:
    Dictionary get_metrics() const;
    void set_seed(int value);
    int get_seed() const;
    void set_biome_layout(int value);
    int get_biome_layout() const;
    int get_used_channels_mask() const override { return 1 << VoxelBuffer::CHANNEL_TYPE; }
    bool supports_lod() const override { return false; }
    Result generate_block(VoxelQueryData input) override;
protected:
    static void _bind_methods();
private:
    mutable RWLock _lock;
    std::atomic<int64_t> _blocks{0}, _usec{0};
    int _seed = 20260916;
    int _biome_layout = 0;
};
}
