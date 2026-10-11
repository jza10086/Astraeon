#pragma once
#include <mutex>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
namespace zylann::voxel {
// Current-only container codec. Metadata is canonical UTF-8 JSON containing data only;
// all offsets, sizes and hashes are fixed-width binary fields. No Variant object decoding.
class AstraeonContentPack : public ::godot::RefCounted {
    GDCLASS(AstraeonContentPack, ::godot::RefCounted)
public:
    int rotation_index(::godot::Basis basis) const;
    ::godot::Dictionary compile_visual(::godot::Array faces, int resolution);
    ::godot::Dictionary write_pack(::godot::String path, ::godot::Dictionary definitions, ::godot::Dictionary blobs);
    ::godot::Dictionary open_pack(::godot::String path);
    ::godot::PackedByteArray read_blob(::godot::String hash);
    ::godot::String get_error() const;
    ::godot::Dictionary blob_info(::godot::String hash) const;
    ::godot::Dictionary get_metrics() const;
    static ::godot::PackedByteArray digest(const ::godot::PackedByteArray &bytes);
protected:
    static void _bind_methods();
private:
    mutable std::mutex _read_mutex;
    ::godot::String _path, _error;
    ::godot::Dictionary _index;
    int64_t _reads = 0, _bytes = 0, _decompressed = 0;
};
}
