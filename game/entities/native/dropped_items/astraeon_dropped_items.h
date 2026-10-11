#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include "edition/voxel_tool.h"
#include <map>
#include <set>
namespace zylann::voxel {
// Main-thread compact records; no scene nodes, rigid bodies or per-voxel script calls.
class AstraeonDroppedItems : public ::godot::RefCounted {
    GDCLASS(AstraeonDroppedItems, ::godot::RefCounted)
public:
    bool configure(::godot::PackedStringArray keys, ::godot::PackedInt32Array limits, ::godot::PackedByteArray solid);
    int64_t spawn(::godot::String key, int count, ::godot::Vector3 position, ::godot::Vector3 velocity, double delay);
    bool take(int64_t id, int count);
    void step(double delta, ::godot::Vector3 center, ::godot::Ref<VoxelTool> terrain);
    ::godot::Array nearby(::godot::Vector3 center, double radius, bool pickable) const;
    ::godot::Dictionary snapshot() const;
    bool restore(::godot::Dictionary snapshot);
    ::godot::String get_error() const { return _error; }
    int get_count() const { return int(_records.size()); }
protected:
    static void _bind_methods();
private:
    struct Record { int64_t id; int item, count; ::godot::Vector3 position, velocity; double delay; bool sleeping=false; };
    using Chunk = std::pair<int,int>;
    static Chunk chunk(::godot::Vector3 p);
    static bool valid_position(::godot::Vector3 p);
    bool collides(::godot::Vector3 p, const ::godot::Ref<VoxelTool> &terrain) const;
    ::godot::Dictionary view(const Record &r) const;
    bool fail(const ::godot::String &message);
    std::map<int64_t,Record> _records;
    std::map<Chunk,std::set<int64_t>> _chunks;
    ::godot::PackedStringArray _keys;
    ::godot::PackedInt32Array _limits;
    ::godot::PackedByteArray _solid;
    ::godot::String _error;
    int64_t _next_id=1;
};
}
