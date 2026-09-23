#pragma once
#include "terrain/fixed_lod/voxel_terrain.h"
#include "util/godot/core/packed_byte_array.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include "section_light_cache.h"
#include "astraeon_page_pool.h"
namespace zylann::voxel {
class AstraeonSectionCache : public RefCounted {
    GDCLASS(AstraeonSectionCache, RefCounted)
public:
    struct State;
    AstraeonSectionCache();
    ~AstraeonSectionCache();
    bool configure(VoxelTerrain *terrain, PackedByteArray opacity, PackedByteArray emission, PackedByteArray sources, Dictionary policy);
    void set_interest(Vector3 position, int horizontal, int vertical, Vector3 velocity);
    void invalidate_section(Vector3i position);
    void invalidate_area(Vector3i position, Vector3i size);
    void invalidate_sections(Array changes);
    bool apply_cache_policy(Dictionary policy);
    void bind_weather_material(Ref<::godot::ShaderMaterial> material);
    void set_weather(double rain, double accumulation, double drying, bool enabled);
    void bind_material(Ref<::godot::ShaderMaterial> material);
    void commit();
    void shutdown();
    Dictionary get_cache_metrics() const;
    Array get_light_sources() const;
    bool is_ready() const;
    void set_suspended(bool enabled);
protected:
    static void _bind_methods();
private:
    void schedule();
    void rebuild_table();
    std::shared_ptr<State> _state;
    Ref<AstraeonPagePool> _pool, _weather_pool;
    std::array<Ref<::godot::Texture2DArrayRD>,4> _banks;
    Ref<::godot::ImageTexture> _table, _weather_table;
    Ref<::godot::Texture2DArrayRD> _weather_pages;
    std::vector<Ref<::godot::ShaderMaterial>> _weather_materials;
    std::unordered_map<astraeon::SectionKey,int,astraeon::SectionHash> _weather_slots;
    std::vector<int> _free_weather_slots;
    uint64_t _world_instance=0;
    uint64_t _weather_uploads=0,_table_upload_bytes=0,_source_revision=0;
    std::vector<Ref<::godot::ShaderMaterial>> _materials;
    struct Page { int slot; uint64_t revision, light_revision; bool shared=false; };
    std::unordered_map<uint32_t,int> _uniform_slots;
    std::unordered_map<astraeon::SectionKey,Page,astraeon::SectionHash> _pages;
    std::vector<int> _free_slots;
    std::vector<uint32_t> _slot_refs, _slot_values;
    Array _sources;
    std::vector<astraeon::SectionKey> _newly_ready;
    astraeon::SectionKey _center{INT32_MAX,0,0};
    Vector3i _table_origin, _table_size;
    int _horizontal=0,_vertical=0,_layers=1024;
    uint64_t _upload_usec=750,_upload_bytes=2097152,_published=0,_stale=0,_gpu_evictions=0,_capacity_pressure=0;
    uint64_t _last_upload_usec=0,_peak_upload_usec=0,_uploaded_bytes=0;
    bool _table_dirty=false,_bindings_dirty=true,_suspended=false,_capacity_blocked=false;
};
}
