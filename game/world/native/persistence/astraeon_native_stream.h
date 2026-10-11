#pragma once
#include "streams/voxel_stream.h"
#include <mutex>
#include <atomic>
#include <string>
#include <cstdio>
#include <memory>
#include <unordered_map>
#include <condition_variable>
#include <array>
#include "util/godot/core/packed_string_array.h"
namespace zylann::voxel {
// Current-only format, raw u16 TYPE data. One stream instance owns one world.
class AstraeonNativeStream : public VoxelStream {
    GDCLASS(AstraeonNativeStream, VoxelStream)
public:
    bool open_world(String directory, int seed, int biome_layout, PackedStringArray state_keys, String world_id);
    String get_last_error() const;
    int64_t get_saved_blocks() const;
    Dictionary get_metrics() const;
    void set_region_handle_limit(int limit);
    int64_t get_loaded_blocks() const;
    bool supports_parallel_access() const override { return true; }
    int get_used_channels_mask() const override { return 1; }
    int get_block_size_po2() const override { return 4; }
    void load_voxel_block(VoxelQueryData &query) override;
    void save_voxel_block(VoxelQueryData &query) override;
protected:
    static void _bind_methods();
private:
    // Leases are held for an entire transaction. Only idle entries can be evicted.
    struct Region {
        std::mutex mutex;
        FILE *file = nullptr;
        uint64_t last_use = 0;
        ~Region() { if (file != nullptr) fclose(file); }
    };
    std::shared_ptr<Region> acquire_region(const std::string &key);
    void release_region(std::shared_ptr<Region> &region);
    void access(VoxelQueryData &query, bool writing);
    void fail(const String &message);
    mutable std::mutex _mutex, _state_mutex;
    std::condition_variable _region_available;
    std::unordered_map<std::string, std::shared_ptr<Region>> _regions;
    // Runtime ordering only; never changes the on-disk format. Survives handle eviction.
    std::unordered_map<std::string, std::array<uint64_t, 64>> _saved_revisions;
    size_t _region_limit = 32;
    uint64_t _region_clock = 0;
    std::atomic<int64_t> _region_hits{0}, _region_misses{0}, _region_evictions{0};
    std::string _directory;
    String _error;
    int _seed = 0, _biome_layout = 0, _state_count = 0;
    String _world_id;
    std::atomic<int64_t> _saved{0}, _loaded{0}, _save_usec{0}, _load_usec{0}, _save_requests{0}, _load_requests{0};
};
}
