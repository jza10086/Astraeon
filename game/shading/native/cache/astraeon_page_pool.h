#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/texture2d_array_rd.hpp>
#include <godot_cpp/classes/rendering_device.hpp>
#include <godot_cpp/variant/array.hpp>
#include <atomic>
#include <vector>
namespace zylann::voxel {
// Power-of-two tiles per layer reduce D3D12 subresource bookkeeping.
// GPU copies preserve single-page uploads and exact user-selected capacity.
// Main-thread queue, render-thread RD ownership; callbacks hold this object alive.
class AstraeonPagePool : public ::godot::RefCounted {
    GDCLASS(AstraeonPagePool, ::godot::RefCounted)
public:
    ~AstraeonPagePool();
    void initialize(int pages_per_bank,int banks,int width,int height,bool weather=false);
    void queue_page(int slot,::godot::PackedByteArray bytes);
    void flush();
    bool ready() const {return _ready.load();}
    ::godot::Ref<::godot::Texture2DArrayRD> texture(int bank) const {return _textures[bank];}
    uint64_t render_upload_usec() const {return _render_usec.load();}
    uint64_t render_upload_peak_usec() const {return _peak_usec.load();}
    uint64_t queued_bytes() const {return _queued_bytes.load();}
    int page_shift() const {return _page_shift;}
protected:
    static void _bind_methods();
private:
    void render_create(::godot::Ref<AstraeonPagePool> keep_alive);
    void render_upload(::godot::Array updates,::godot::Ref<AstraeonPagePool> keep_alive);
    int _pages=0,_banks=0,_width=0,_height=0;
    int _page_shift=4;
    bool _weather=false;
    std::vector<::godot::Ref<::godot::Texture2DArrayRD>> _textures;
    std::vector<::godot::RID> _rids;
    ::godot::RID _staging;
    ::godot::Array _pending;
    std::atomic<bool> _ready{false};
    std::atomic<uint64_t> _render_usec{0},_peak_usec{0},_queued_bytes{0};
};
}
