#pragma once
#include "streams/voxel_stream.h"
#include <mutex>
#include <atomic>
#include <string>
namespace zylann::voxel {
// Current-only format, raw u16 TYPE data. One stream instance owns one world.
class AstraeonNativeStream : public VoxelStream {
    GDCLASS(AstraeonNativeStream, VoxelStream)
public:
    bool open_world(String directory, int seed, int biome_layout);
    String get_last_error() const;
    int64_t get_saved_blocks() const;
    Dictionary get_metrics() const;
    int64_t get_loaded_blocks() const;
    int get_used_channels_mask() const override { return 1; }
    int get_block_size_po2() const override { return 4; }
    void load_voxel_block(VoxelQueryData &query) override;
    void save_voxel_block(VoxelQueryData &query) override;
protected:
    static void _bind_methods();
private:
    void access(VoxelQueryData &query, bool writing);
    void fail(const String &message);
    mutable std::mutex _mutex, _state_mutex;
    std::string _directory;
    String _error;
    int _seed = 0, _biome_layout = 0;
    std::atomic<int64_t> _saved{0}, _loaded{0}, _save_usec{0}, _load_usec{0}, _save_requests{0}, _load_requests{0};
};
}
