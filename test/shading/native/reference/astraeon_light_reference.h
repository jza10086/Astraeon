#pragma once
#include "storage/voxel_buffer_gd.h"
#include "util/godot/core/dictionary.h"
#include "util/godot/core/packed_byte_array.h"
namespace zylann::voxel {
// Derived, disposable snapshot solver. Never mutates authoritative terrain.
class AstraeonLightReference : public RefCounted {
    GDCLASS(AstraeonLightReference, RefCounted)
public:
    Dictionary solve(Ref<godot::VoxelBuffer> snapshot, PackedByteArray opacity, PackedByteArray emission, PackedByteArray sources, PackedByteArray known_sections, int section_size, Vector3i origin);
protected:
    static void _bind_methods();
};
}
