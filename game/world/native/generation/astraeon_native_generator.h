#pragma once
#include "generators/voxel_generator.h"
#include "storage/voxel_buffer.h"
#include "util/thread/rw_lock.h"
#include <atomic>
#include "util/godot/core/packed_string_array.h"

namespace zylann::voxel {
// Generation v2: plains, forests, rivers and ocean; immutable configured content IDs.
class AstraeonNativeGenerator : public VoxelGenerator {
    GDCLASS(AstraeonNativeGenerator, VoxelGenerator)
public:
    Dictionary get_metrics() const;
    bool configure_content(PackedStringArray keys);
    Dictionary sample_column(int x, int z) const;
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
    int _grass = -1, _dirt = -1, _leaves = -1, _log = -1, _water = -1;
    bool _configured = false;
    int _seed = 20260916;
    int _biome_layout = 0;
};
}
