#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include "astraeon/data/content/astraeon_content_pack.h"
#include <map>
#include <memory>
#include <atomic>
namespace zylann::voxel {
// Scene-local cache. Only commit() creates GPU resources or changes material bindings.
class AstraeonVisualCache : public ::godot::RefCounted {
    GDCLASS(AstraeonVisualCache, ::godot::RefCounted)
public:
    ~AstraeonVisualCache();
    bool configure(::godot::Dictionary policy);
    bool register_visual(::godot::String hash, ::godot::String pack, int width, int height, bool pinned);
    void bind_material(::godot::String hash, ::godot::Ref<::godot::ShaderMaterial> material);
    bool request(::godot::String owner, ::godot::PackedStringArray hashes);
    void release(::godot::String owner);
    bool is_ready(::godot::PackedStringArray hashes) const;
    void commit();
    void shutdown();
    ::godot::Dictionary get_metrics() const;
    ::godot::Ref<::godot::ImageTexture> texture(::godot::String hash) const;
protected:
    static void _bind_methods();
private:
    struct Job { ::godot::Ref<AstraeonContentPack> reader; ::godot::String pack, hash, error; ::godot::PackedByteArray bytes; std::atomic<bool> done{false}; int64_t task=-1; uint64_t read_bytes=0; };
    struct Entry {
        ::godot::String path; int width=0,height=0; bool pinned=false; int references=0;
        uint64_t touched=0, requested=0; ::godot::PackedByteArray cpu;
        ::godot::Ref<::godot::ImageTexture> gpu;
        ::godot::Array materials; std::shared_ptr<Job> job; ::godot::String error;
    };
    void read_job(::godot::String hash);
    std::map<std::string,Entry> _entries;
    std::map<std::string,::godot::Ref<AstraeonContentPack>> _readers;
    ::godot::Dictionary _owners;
    bool _closed=false;
    uint64_t _cpu_limit=64ull<<20,_gpu_limit=128ull<<20,_warm_usec=30000000,_upload_usec=500,_upload_bytes=2ull<<20;
    int _max_jobs=2;
    uint64_t _hits=0,_misses=0,_reads=0,_read_bytes=0,_uploaded=0,_uploads=0,_evictions=0,_overruns=0,_max_latency=0;
    ::godot::String _pressure;
};
}
