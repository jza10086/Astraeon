#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace zylann::voxel {
class AstraeonContentRegistry : public ::godot::RefCounted {
    GDCLASS(AstraeonContentRegistry, ::godot::RefCounted)
public:
    static bool validate_table(::godot::String directory, ::godot::PackedStringArray keys, ::godot::String world_id);
    // Returns the durable ordered states and world identity. Never exposes newly allocated IDs before sync.
    ::godot::Dictionary resolve(::godot::String directory, ::godot::Dictionary contracts, ::godot::PackedStringArray packages);
protected:
    static void _bind_methods();
};
}
