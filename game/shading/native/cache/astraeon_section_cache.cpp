#include "astraeon_section_cache.h"
#include "engine/voxel_engine.h"
#include "util/godot/core/class_db.h"
#include "util/tasks/threaded_task.h"
#include "storage/voxel_memory_pool.h"
#include <godot_cpp/classes/time.hpp>
#include <mutex>
#include <atomic>
#include <cstring>
#include <condition_variable>
namespace zylann::voxel {
using astraeon::SectionKey;
using astraeon::SectionHash;
using astraeon::LightSection;
using astraeon::SectionLightCache;
namespace {
Vector3i vec(SectionKey p) {return Vector3i(p.x,p.y,p.z);}
SectionKey key(Vector3i p) {return {p.x,p.y,p.z};}
uint64_t now_usec(){return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();}
bool in_radius(SectionKey p, SectionKey center,int radius) {
    const int64_t x=p.x-center.x,z=p.z-center.z;
    return x*x+z*z<=int64_t(radius)*radius;
}
}
struct AstraeonSectionCache::State {
    std::shared_ptr<VoxelData> data;
    std::vector<uint8_t> opacity,emission,sources;
    std::mutex mutex;
    std::atomic<bool> running{false},closing{false};
    std::unordered_set<SectionKey,SectionHash> requested;
    std::unordered_map<SectionKey,std::pair<uint64_t,uint64_t>,SectionHash> published_versions;
    std::deque<SectionKey> reads;
    SectionLightCache solver;
    std::deque<SectionKey> publish_order;
    std::unordered_set<SectionKey,SectionHash> weather_interest;
    uint64_t work_turn=0;
    struct Column { std::array<float,256> roof; std::array<float,256> wet{}; uint64_t updated=0; };
    std::unordered_map<SectionKey,Column,SectionHash> columns;
    std::unordered_set<SectionKey,SectionHash> dirty_columns;
    std::deque<SectionKey> wet_columns;
    struct WeatherPage {SectionKey position;std::array<float,512> pixels;std::array<uint64_t,16> revisions;};
    std::deque<WeatherPage> weather_ready;
    double rain=0.0,accumulation=0.0,drying=0.0;bool wet_enabled=false;
    uint64_t weather_tick=0;
    uint64_t statistics_tick=0;
    SectionKey center{};
    int horizontal=0,vertical=0,retain=32;
    uint64_t cpu_budget=512ull<<20,slice_usec=2000,queue_visits=4096;
    bool interest_changed=false,map_maintenance_pending=false;
    std::atomic<uint64_t> last_maintenance{0};
    uint64_t oldest_change=0;
    struct ReadyPage {
        SectionKey position;
        uint64_t revision,started,light_revision;
        std::array<uint64_t,6> dependencies;
        std::array<uint8_t,16384> pixels;
        std::vector<LightSection::Source> sources;
    };
    std::deque<ReadyPage> ready;
    std::atomic<uint64_t> light_bytes{0},read_count{0},hits{0},queue_size{0},visits{0},passes{0},stale{0},work_usec{0},peak_slice_usec{0},latency_usec{0};
    std::atomic<uint64_t> weather_bytes{0},queue_bytes{0};
    std::atomic<bool> settled{false};
};
namespace {
class SectionCacheTask : public IThreadedTask {
    std::shared_ptr<AstraeonSectionCache::State> state;
public:
    SectionCacheTask(std::shared_ptr<AstraeonSectionCache::State> s):state(std::move(s)){}
    const char *get_debug_name() const override{return "AstraeonSectionLightSlice";}
    static void StateWeather(AstraeonSectionCache::State &s,SectionKey p,AstraeonSectionCache::State::Column &column) {
        const uint64_t now=now_usec();
        std::lock_guard<std::mutex> guard(s.mutex);
        const float elapsed=column.updated?float(now-column.updated)/1000000.0f:0.0f;
        column.updated=now;
        AstraeonSectionCache::State::WeatherPage page;page.position=p;
        for(int y=-4;y<12;++y){auto section=s.solver.find({p.x,y,p.z});page.revisions[y+4]=section?section->revision:0;}
        for(int i=0;i<256;++i) {
            if(s.wet_enabled)column.wet[i]=std::clamp(column.wet[i]+elapsed*float(s.rain*s.accumulation-(1.0-s.rain)*s.drying),0.0f,1.0f);
            page.pixels[i*2]=column.roof[i];page.pixels[i*2+1]=column.wet[i];
        }
        for(auto &old:s.weather_ready)if(old.position==p){old=page;return;}
        if(s.weather_ready.size()<2048)s.weather_ready.push_back(page);
        else s.wet_columns.push_back(p); // Keep the derived update pending until capacity recovers.
    }
    static bool pack_one(AstraeonSectionCache::State &s,SectionKey center,int horizontal,int vertical) {
        if(s.solver.changed.empty())return false;
        if(s.publish_order.empty()) {
            std::vector<SectionKey> ordered(s.solver.changed.begin(),s.solver.changed.end());
            auto distance=[center](SectionKey p){int64_t x=p.x-center.x,y=p.y-center.y,z=p.z-center.z;return x*x+z*z+y*y*2;};
            std::stable_sort(ordered.begin(),ordered.end(),[&](SectionKey a,SectionKey b){return distance(a)<distance(b);});
            s.publish_order.assign(ordered.begin(),ordered.end());
        }
        const size_t count=std::min<size_t>(s.publish_order.size(),64);
        for(size_t n=0;n<count;++n) {
            auto p=s.publish_order.front();s.publish_order.pop_front();
            if(s.solver.changed.find(p)==s.solver.changed.end())continue;
            auto section=s.solver.find(p);
            if(!section || !in_radius(p,center,(horizontal+15)/16+1) || std::abs(p.y-center.y)>(vertical+15)/16+1) {
                s.solver.changed.erase(p);continue;
            }
            if(section->queued || section->completed_revision!=section->revision){s.publish_order.push_back(p);continue;}
            std::lock_guard<std::mutex> guard(s.mutex);
            const auto published=s.published_versions.find(p);
            if(published!=s.published_versions.end() && published->second==std::make_pair(section->revision,section->light_revision)) {
                s.solver.changed.erase(p);continue;
            }
            if(s.ready.size()>=128) {
                const auto distance=[center](SectionKey q){int64_t x=q.x-center.x,y=q.y-center.y,z=q.z-center.z;return x*x+z*z+y*y*2;};
                auto farthest=std::max_element(s.ready.begin(),s.ready.end(),[&](const auto &a,const auto &b){return distance(a.position)<distance(b.position);});
                if(distance(farthest->position)<=distance(p)){s.publish_order.push_front(p);return false;}
                s.solver.changed.insert(farthest->position);s.publish_order.push_back(farthest->position);s.ready.erase(farthest);
            }
            AstraeonSectionCache::State::ReadyPage output;
            output.position=p;output.revision=section->revision;output.light_revision=section->light_revision;output.started=s.oldest_change;
            output.pixels=s.solver.pack(*section);output.sources=section->sources;
            for(int d=0;d<6;++d){auto neighbor=s.solver.find(p+SectionLightCache::DIRECTIONS[d]);output.dependencies[d]=neighbor?neighbor->revision:0;}
            s.ready.push_back(std::move(output));s.solver.changed.erase(p);
            return true;
        }
        return false;
    }
    void run(ThreadedTaskContext &ctx) override {
        auto &s=*state;
        const uint64_t start=now_usec();
        if(s.closing){s.running=false;return;}
        SectionKey center;int horizontal,vertical,retain;uint64_t cpu_budget,slice_usec,queue_visits;
        bool changed=false;
        {
            std::lock_guard<std::mutex> guard(s.mutex);
            center=s.center;horizontal=s.horizontal;vertical=s.vertical;retain=s.retain;cpu_budget=s.cpu_budget;slice_usec=s.slice_usec;queue_visits=s.queue_visits;
            changed=s.interest_changed;s.interest_changed=false;
            for(auto p:s.requested)s.reads.push_front(p);
            s.requested.clear();
        }
        if(changed) {
            // Superseded prediction/interest scans are metadata only; keep edit notifications.
            std::unordered_set<SectionKey,SectionHash> unique;
            std::deque<SectionKey> current;
            for(auto p:s.reads)if(in_radius(p,center,(horizontal+retain+31)/16) && unique.insert(p).second)current.push_back(p);
            s.reads.swap(current);s.publish_order.clear();
            // Read only revision metadata for retained sections. New sections use one locked snapshot each.
            const int radius=(horizontal+15)/16+1;
            for(int y=11;y>=-4;--y)for(int z=-radius;z<=radius;++z)for(int x=-radius;x<=radius;++x) {
                SectionKey p{center.x+x,y,center.z+z};
                if(in_radius(p,center,radius) && unique.insert(p).second)s.reads.push_back(p);
            }
            std::unordered_set<SectionKey,SectionHash> weather_interest;
            for(auto &p:s.columns)if(in_radius(p.first,center,radius)) {
                weather_interest.insert(p.first);
                if(s.weather_interest.find(p.first)==s.weather_interest.end())s.wet_columns.push_back(p.first);
            }
            s.weather_interest.swap(weather_interest);
            {std::lock_guard<std::mutex> guard(s.mutex);
                for(auto &p:s.solver.sections)if(in_radius(p.first,center,radius) && std::abs(p.first.y-center.y)<=(vertical+15)/16+1 && s.published_versions.find(p.first)==s.published_versions.end())s.solver.changed.insert(p.first);
            }
        }
        if(now_usec()-s.weather_tick>250000 && s.reads.empty() && s.dirty_columns.empty()) {
            s.weather_tick=now_usec();
            std::lock_guard<std::mutex> guard(s.mutex);
            if(s.wet_enabled && s.wet_columns.empty())for(auto &p:s.columns) {
                if(s.rain>0 || std::any_of(p.second.wet.begin(),p.second.wet.end(),[](float w){return w>0;}))s.wet_columns.push_back(p.first);
            }
        }
        // Interleave reads, propagation and locally converged publications. Continuous
        // movement must not require the entire interest volume to become idle first.
        const unsigned turn=unsigned(s.work_turn++%4);
        bool packed=false;
        if(turn==3)for(unsigned n=0;n<32 && now_usec()-start<slice_usec;++n) {
            if(!pack_one(s,center,horizontal,vertical))break;
            packed=true;
        }
        if(packed) {
        } else if(s.solver.pending() && (turn==1 || s.reads.empty())) {
            s.solver.step(unsigned(queue_visits),slice_usec);
        } else if(!s.reads.empty()) {
          for(unsigned metadata_visits=0;metadata_visits<256 && !s.reads.empty() && now_usec()-start<slice_usec;++metadata_visits) {
            const auto p=s.reads.front();s.reads.pop_front();
            const uint64_t revision=s.data->get_section_revision(vec(p));
            auto previous=s.solver.find(p);
            if(revision==0) {if(previous){s.solver.erase(p);s.dirty_columns.insert({p.x,0,p.z});}}
            else if(previous && previous->revision==revision)++s.hits;
            else {
                VoxelBuffer copy(VoxelBuffer::ALLOCATOR_POOL);
                const uint64_t captured=s.data->copy_section(vec(p),copy);
                if(captured!=0) {
                    auto section=std::make_unique<LightSection>();section->revision=captured;
                    section->opacity.fill(15);
                    const uint64_t uniform_id=copy.get_voxel(0,0,0,VoxelBuffer::CHANNEL_TYPE);
                    const bool uniform=copy.get_channel_compression(VoxelBuffer::CHANNEL_TYPE)==VoxelBuffer::COMPRESSION_UNIFORM;
                    if(uniform && (uniform_id>=s.sources.size() || s.sources[uniform_id]==0)) {
                        section->opacity.fill(uniform_id<s.opacity.size()?s.opacity[uniform_id]:15);
                        section->emission.fill(uniform_id<s.emission.size()?s.emission[uniform_id]:0);
                    } else for(int z=0;z<16;++z)for(int y=0;y<16;++y)for(int x=0;x<16;++x) {
                        const uint64_t id=copy.get_voxel(x,y,z,VoxelBuffer::CHANNEL_TYPE);
                        const int i=SectionLightCache::index(x,y,z);
                        section->opacity.set(i,id<s.opacity.size()?s.opacity[id]:15);
                        section->emission.set(i,id<s.emission.size()?s.emission[id]:0);
                        if(id<s.sources.size() && s.sources[id]>0)section->sources.push_back({uint16_t(i),uint32_t(id)});
                    }
                    section->opacity.compact();section->emission.compact();
                    if(s.data->get_section_revision(vec(p))==captured){s.solver.replace(p,std::move(section));s.dirty_columns.insert({p.x,0,p.z});++s.read_count;}
                    else {s.reads.push_back(p);++s.stale;}
                }
                // Snapshots are individually locked and released; the clock bounds
                // a small batch, including constant-value sections with no payload.
                if(metadata_visits>=7)break;
            }
          }
        } else if(!s.dirty_columns.empty()) {
            const SectionKey p=*s.dirty_columns.begin();s.dirty_columns.erase(p);
            auto &column=s.columns[p];
            if(column.updated==0)column.roof.fill(192.0f);
            for(int z=0;z<16;++z)for(int x=0;x<16;++x) {
                float roof=-65.0f;bool found=false;
                for(int sy=11;sy>=-4 && !found;--sy) {
                    auto section=s.solver.find({p.x,sy,p.z});
                    if(!section){roof=float(sy*16+16);break;}
                    for(int y=15;y>=0;--y)if(section->opacity.get(SectionLightCache::index(x,y,z))>0){roof=float(sy*16+y+1);found=true;break;}
                }
                const int i=x+16*z;
                if(column.roof[i]!=roof){column.roof[i]=roof;column.wet[i]=0;}
            }
            s.weather_interest.insert(p);StateWeather(s,p,column);
        } else if(!s.wet_columns.empty()) {
            const auto p=s.wet_columns.front();s.wet_columns.pop_front();
            auto it=s.columns.find(p);if(it!=s.columns.end())StateWeather(s,p,it->second);
        } else {
            pack_one(s,center,horizontal,vertical);
        }
        s.queue_size=s.reads.size()+s.solver.queue_size()+s.solver.changed.size();
        s.queue_bytes=(s.reads.size()+s.publish_order.size()+s.wet_columns.size()+s.dirty_columns.size())*sizeof(SectionKey);
        s.visits=s.solver.visits;s.passes=s.solver.passes;
        if(now_usec()-s.statistics_tick>500000) {
            s.statistics_tick=now_usec();s.light_bytes=s.solver.bytes();
            s.weather_bytes=s.columns.size()*(sizeof(AstraeonSectionCache::State::Column)+sizeof(SectionKey));
        }
        // Avoid scanning every cached section after every 2 ms slice.
        if((s.map_maintenance_pending || now_usec()-s.last_maintenance>500000) && s.reads.empty() && !s.solver.pending() && now_usec()-start<slice_usec) {
            StdVector<Vector3i> removed;
            const uint64_t reserve=cpu_budget/10+s.data->get_derived_cache_bytes()+s.weather_bytes;
            s.data->set_cache_policy(cpu_budget>reserve+s.light_bytes?cpu_budget-reserve-s.light_bytes:1,retain);
            const uint64_t elapsed_before_maintenance=now_usec()-start;
            s.map_maintenance_pending=!s.data->maintain_cache(Vector3i(center.x*16+8,64,center.z*16+8),horizontal+16,128,removed,
                    elapsed_before_maintenance<slice_usec?slice_usec-elapsed_before_maintenance:0);
            if(!s.map_maintenance_pending)s.last_maintenance=now_usec();
            for(auto p:removed){s.solver.erase(key(p));s.dirty_columns.insert({p.x,0,p.z});}
            for(auto it=s.columns.begin();it!=s.columns.end();) {
                if(!in_radius(it->first,center,(horizontal+retain+31)/16)){s.dirty_columns.erase(it->first);it=s.columns.erase(it);}else ++it;
            }
        }
        const uint64_t elapsed=now_usec()-start;
        s.work_usec+=elapsed;s.peak_slice_usec=std::max(s.peak_slice_usec.load(),elapsed);
        bool pending;
        {
            std::lock_guard<std::mutex> guard(s.mutex);
            const bool visual_pending=!s.reads.empty()||!s.dirty_columns.empty()||!s.wet_columns.empty()||s.solver.pending()||!s.solver.changed.empty()||!s.requested.empty()||s.interest_changed;
            // Periodic accounting can span several slices without invalidating already
            // complete light pages. Otherwise larger worlds never remain ready long enough.
            pending=s.map_maintenance_pending||visual_pending;
            s.settled=!visual_pending;
            if(!pending){s.running=false;s.oldest_change=0;}
        }
        if(pending)ctx.status=ThreadedTaskContext::STATUS_POSTPONED;
    }
};
}
AstraeonSectionCache::AstraeonSectionCache():_state(std::make_shared<State>()){}
AstraeonSectionCache::~AstraeonSectionCache(){shutdown();}
void AstraeonSectionCache::shutdown(){_state->closing=true;}
void AstraeonSectionCache::set_suspended(bool enabled){_suspended=enabled;}
bool AstraeonSectionCache::configure(VoxelTerrain *terrain,PackedByteArray opacity,PackedByteArray emission,PackedByteArray sources,Dictionary policy) {
    ERR_FAIL_COND_V(terrain==nullptr || _state->data!=nullptr,false);
    _state->data=terrain->get_shared_data();
    _world_instance=terrain->get_instance_id();
    _state->data->require_light_pages(true);
    _state->opacity.assign(opacity.ptr(),opacity.ptr()+opacity.size());
    _state->emission.assign(emission.ptr(),emission.ptr()+emission.size());
    _state->sources.assign(sources.ptr(),sources.ptr()+sources.size());
    return apply_cache_policy(policy);
}
bool AstraeonSectionCache::apply_cache_policy(Dictionary policy) {
    const Variant format=policy.get("format",Variant());
    ERR_FAIL_COND_V(format.get_type()!=Variant::INT || int(format)!=1,false);
    const int cpu=int(policy.get("cpu_mib",512)), retain=int(policy.get("retain_m",32));
    const int commit=int(policy.get("commit_usec",2000)), upload=int(policy.get("upload_usec",750));
    const int upload_bytes=int(policy.get("upload_bytes",2097152)), visits=int(policy.get("slice_visits",4096)), slice=int(policy.get("slice_usec",2000));
    ERR_FAIL_COND_V(cpu<64 || cpu>8192 || retain<0 || retain>256 || commit<100 || commit>10000 || upload<100 || upload>commit || upload_bytes<16384 || upload_bytes>16777216 || visits<64 || visits>65536 || slice<100 || slice>10000,false);
    const int mib=int(policy.get("gpu_mib",64));
    ERR_FAIL_COND_V(mib<1 || mib>128,false);
    // Resizing a live pool requires the caller to pause/loading; never silently rebuild while moving.
    ERR_FAIL_COND_V(!_pages.empty() && !_suspended && _layers!=mib*16,false);
    {std::lock_guard<std::mutex> guard(_state->mutex);
        _state->cpu_budget=uint64_t(int(policy.get("cpu_mib",512)))<<20;
        _state->retain=int(policy.get("retain_m",32));
        _state->slice_usec=uint64_t(int(policy.get("slice_usec",2000)));
        _state->queue_visits=uint64_t(int(policy.get("slice_visits",4096)));
    }
    _upload_usec=uint64_t(int(policy.get("upload_usec",750)));
    _upload_bytes=uint64_t(int(policy.get("upload_bytes",2097152)));
    VoxelEngine::get_singleton().set_cache_task_limit(unsigned(_state->cpu_budget/10/131072));
    VoxelEngine::get_singleton().set_main_thread_time_budget_usec(unsigned(int(policy.get("commit_usec",2000))));
    if(_banks[0].is_null() || _layers!=mib*16) {
        _layers=mib*16;
        _state->data->clear_light_pages();
        _pages.clear();_free_slots.clear();_uniform_slots.clear();_newly_ready.clear();_bindings_dirty=true;
        _slot_refs.assign(4*_layers,0);_slot_values.assign(4*_layers,0);
        {std::lock_guard<std::mutex> guard(_state->mutex);_state->published_versions.clear();_state->interest_changed=true;_state->settled=false;}
        _pool.instantiate();_pool->initialize(_layers,4,16,256);
        for(int i=0;i<4;++i)_banks[i]=_pool->texture(i);
        for(int i=4*_layers-1;i>=0;--i)_free_slots.push_back(i);
        _table_dirty=true;
        for(auto material:_materials)for(int bank=0;bank<4;++bank)material->set_shader_parameter(String("light_pages_")+String::num_int64(bank),_banks[bank]);
    }
    if(_weather_pages.is_null()) {
        _weather_pool.instantiate();_weather_pool->initialize(2048,1,16,16,true);
        _weather_pages=_weather_pool->texture(0);
        for(int i=0;i<2048;++i)_free_weather_slots.push_back(2047-i);
    }
    _state->data->set_cache_policy(_state->cpu_budget-_state->cpu_budget/10,_state->retain);
    return true;
}
void AstraeonSectionCache::set_interest(Vector3 position,int horizontal,int vertical,Vector3 velocity) {
    if(!_state->data || _state->closing)return;
    const SectionKey center{int(std::floor(position.x/16)),int(std::floor(position.y/16)),int(std::floor(position.z/16))};
    if(center==_center && horizontal==_horizontal && vertical==_vertical)return;
    _center=center;_horizontal=horizontal;_vertical=vertical;
    const int radius=(horizontal+15)/16+1;
    _table_origin=Vector3i(center.x-radius,-4,center.z-radius);
    _table_size=Vector3i(radius*2+1,16,radius*2+1);
    _bindings_dirty=true;
    _table_dirty=true;
    {
        std::lock_guard<std::mutex> guard(_state->mutex);
        _state->center=center;_state->horizontal=horizontal;_state->vertical=vertical;
        _state->interest_changed=true;_state->settled=false;
        if(_state->oldest_change==0)_state->oldest_change=now_usec();
    }
    for(auto it=_weather_slots.begin();it!=_weather_slots.end();) {
        if(!in_radius(it->first,center,radius)){_free_weather_slots.push_back(it->second);it=_weather_slots.erase(it);}else ++it;
    }
    const int previous_sources=_sources.size();
    for(int i=_sources.size()-1;i>=0;--i){Dictionary item=_sources[i];const auto p=key(Vector3i(item["section"]));if(!in_radius(p,center,radius) || std::abs(p.y-center.y)>(vertical+15)/16+1)_sources.remove_at(i);}
    if(previous_sources!=_sources.size())++_source_revision;
    // Remove mappings before reusing any slot. The next table publish occurs before uploads.
    for(auto it=_pages.begin();it!=_pages.end();) {
        if(!in_radius(it->first,center,radius) || std::abs(it->first.y-center.y)>(vertical+15)/16+1) {
            {std::lock_guard<std::mutex> guard(_state->mutex);_state->published_versions.erase(it->first);}
            _state->data->set_light_page_ready(vec(it->first),false);
            const int slot=it->second.slot;
            if(--_slot_refs[slot]==0){if(it->second.shared)_uniform_slots.erase(_slot_values[slot]);_free_slots.push_back(slot);}
            it=_pages.erase(it);++_gpu_evictions;
        } else ++it;
    }
}
void AstraeonSectionCache::invalidate_section(Vector3i position) {
    std::lock_guard<std::mutex> guard(_state->mutex);
    _state->requested.insert(key(position));_state->settled=false;
    if(_state->oldest_change==0)_state->oldest_change=now_usec();
}
void AstraeonSectionCache::invalidate_sections(Array changes) {
    for(int i=0;i<changes.size();++i) {
        Dictionary change=changes[i];
        if(uint64_t(int64_t(change.get("world_instance",0)))!=_world_instance)continue;
        const Vector3i position=change["section"];
        const auto current=_state->data->get_section_identity(position);
        // An old release/load notification must never invalidate a replacement lifetime.
        if(current.lifecycle!=0 && current.lifecycle!=uint64_t(int64_t(change["lifecycle"])))continue;
        invalidate_section(position);
    }
}
void AstraeonSectionCache::invalidate_area(Vector3i position,Vector3i size) {
    const Vector3i begin=position>>4,end=(position+size-Vector3i(1,1,1))>>4;
    for(int z=begin.z;z<=end.z;++z)for(int y=begin.y;y<=end.y;++y)for(int x=begin.x;x<=end.x;++x)invalidate_section(Vector3i(x,y,z));
}
void AstraeonSectionCache::bind_material(Ref<::godot::ShaderMaterial> material) {
    ERR_FAIL_COND(material.is_null());_materials.push_back(material);
    bind_weather_material(material);
    for(int bank=0;bank<4;++bank)material->set_shader_parameter(String("light_pages_")+String::num_int64(bank),_banks[bank]);
    material->set_shader_parameter("light_page_layers",_layers);
    material->set_shader_parameter("light_page_shift",_pool->page_shift());
    if(_table.is_valid())material->set_shader_parameter("light_page_table",_table);
}
void AstraeonSectionCache::bind_weather_material(Ref<::godot::ShaderMaterial> material) {
    _weather_materials.push_back(material);_bindings_dirty=true;
    material->set_shader_parameter("weather_pages",_weather_pages);
    _table_dirty=true;
}
void AstraeonSectionCache::set_weather(double rain,double accumulation,double drying,bool enabled) {
    std::lock_guard<std::mutex> guard(_state->mutex);
    _state->rain=rain;_state->accumulation=accumulation;_state->drying=drying;_state->wet_enabled=enabled;
}
void AstraeonSectionCache::schedule() {
    if(_suspended || !_state->data || _state->closing)return;
    if(_state->settled && now_usec()-_state->last_maintenance<500000)return;
    if(_state->running.exchange(true))return;
    VoxelEngine::get_singleton().push_async_task(ZN_NEW(SectionCacheTask(_state)));
}
void AstraeonSectionCache::rebuild_table() {
    if(_table_size.x==0)return;
    PackedByteArray bytes;bytes.resize(_table_size.x*_table_size.y*_table_size.z*4);
    std::memset(bytes.ptrw(),0,bytes.size());
    uint8_t *mapping=bytes.ptrw();
    for(auto &p:_pages) {
        Vector3i q=vec(p.first)-_table_origin;
        if(q.x<0||q.y<0||q.z<0||q.x>=_table_size.x||q.y>=_table_size.y||q.z>=_table_size.z)continue;
        const int i=4*(q.x+_table_size.x*(q.y+_table_size.y*q.z)),encoded=p.second.slot+1;
        mapping[i]=uint8_t(encoded);mapping[i+1]=uint8_t(encoded>>8);
    }
    Ref<Image> image=Image::create_from_data(_table_size.x,_table_size.y*_table_size.z,false,Image::FORMAT_RGBA8,bytes);
    if(_table.is_null() || _table->get_width()!=image->get_width() || _table->get_height()!=image->get_height())_table=::godot::ImageTexture::create_from_image(image);
    else _table->update(image);
    if(_bindings_dirty)for(auto material:_materials) {
        material->set_shader_parameter("light_page_table",_table);
        material->set_shader_parameter("light_table_origin",Vector3(_table_origin));
        material->set_shader_parameter("light_table_size",Vector3(_table_size));
        material->set_shader_parameter("light_page_layers",_layers);
        material->set_shader_parameter("light_page_shift",_pool->page_shift());
    }
    PackedByteArray weather_bytes;weather_bytes.resize(_table_size.x*_table_size.z*4);std::memset(weather_bytes.ptrw(),0,weather_bytes.size());
    uint8_t *weather_mapping=weather_bytes.ptrw();
    for(auto &p:_weather_slots) {
        const int x=p.first.x-_table_origin.x,z=p.first.z-_table_origin.z;
        if(x<0||z<0||x>=_table_size.x||z>=_table_size.z)continue;
        const int i=4*(x+_table_size.x*z),encoded=p.second+1;
        weather_mapping[i]=uint8_t(encoded);weather_mapping[i+1]=uint8_t(encoded>>8);
    }
    Ref<Image> wi=Image::create_from_data(_table_size.x,_table_size.z,false,Image::FORMAT_RGBA8,weather_bytes);
    if(_weather_table.is_null()||_weather_table->get_width()!=wi->get_width())_weather_table=::godot::ImageTexture::create_from_image(wi);else _weather_table->update(wi);
    if(_bindings_dirty)for(auto material:_weather_materials) {
        material->set_shader_parameter("weather_page_table",_weather_table);
        material->set_shader_parameter("weather_table_origin",Vector2(_table_origin.x,_table_origin.z));
        material->set_shader_parameter("weather_table_size",Vector2(_table_size.x,_table_size.z));
    }
    for(const auto &p:_newly_ready)if(_pages.find(p)!=_pages.end())_state->data->set_light_page_ready(vec(p),true);
    _newly_ready.clear();_bindings_dirty=false;
    _table_upload_bytes+=bytes.size()+weather_bytes.size();
    _table_dirty=false;
}
void AstraeonSectionCache::commit() {
    _last_upload_usec=0;
    _table_upload_bytes=0;
    if(_suspended || !_state->data)return;
    if(!_pool->ready() || !_weather_pool->ready()){schedule();return;}
    auto &engine=VoxelEngine::get_singleton();
    const uint64_t start=now_usec(),limit=std::min<uint64_t>(_upload_usec,engine.get_remaining_commit_usec());
    if(limit>0) {
        if(_table_dirty)rebuild_table();
        uint64_t bytes=0;
        _capacity_blocked=false;
        size_t attempts=128; // Rotate blocked pages so existing near pages can still update.
        std::vector<int> retired_slots;
        const uint64_t table_reserve=uint64_t(_table_size.x)*_table_size.z*(_table_size.y+1)*4;
        while(attempts-- > 0 && now_usec()-start<limit && bytes+_table_upload_bytes+table_reserve+16384<=_upload_bytes) {
            State::ReadyPage page;
            {
                std::lock_guard<std::mutex> guard(_state->mutex);
                if(_state->ready.empty())break;
                page=std::move(_state->ready.front());_state->ready.pop_front();
            }
            bool valid=_state->data->get_section_revision(vec(page.position))==page.revision;
            for(int d=0;d<6;++d) {
                const auto neighbor=vec(page.position+SectionLightCache::DIRECTIONS[d]);
                if(_state->data->get_section_revision(neighbor)!=page.dependencies[d]){valid=false;invalidate_section(neighbor);}
            }
            if(!valid){++_stale;invalidate_section(vec(page.position));continue;}
            if(!in_radius(page.position,_center,(_horizontal+15)/16+1) || std::abs(page.position.y-_center.y)>(_vertical+15)/16+1)continue;
            auto old=_pages.find(page.position);
            if(old!=_pages.end() && old->second.revision==page.revision && old->second.light_revision==page.light_revision)continue;
            uint32_t uniform;std::memcpy(&uniform,page.pixels.data(),4);
            bool same=true;
            for(int i=1;i<4096 && same;++i) {uint32_t value;std::memcpy(&value,page.pixels.data()+i*4,4);same=value==uniform;}
            const auto shared=same?_uniform_slots.find(uniform):_uniform_slots.end();
            int slot=-1;
            if(shared!=_uniform_slots.end()) slot=shared->second;
            else if(old!=_pages.end() && !old->second.shared)slot=old->second.slot;
            else if(!_free_slots.empty()){slot=_free_slots.back();_free_slots.pop_back();}
            else {
                ++_capacity_pressure;_capacity_blocked=true;
                std::lock_guard<std::mutex> guard(_state->mutex);
                _state->ready.push_back(std::move(page));
                continue; // Retain the result; only its new geometry waits for capacity.
            }
            if(shared==_uniform_slots.end()) {
                PackedByteArray pixels;pixels.resize(16384);std::memcpy(pixels.ptrw(),page.pixels.data(),16384);
                _pool->queue_page(slot,pixels);
                if(same){_uniform_slots[uniform]=slot;_slot_values[slot]=uniform;}
                bytes+=16384;
            }
            // Reclaim obsolete private slots only after publishing the new mapping.
            int retired=-1;
            if(old==_pages.end() || old->second.slot!=slot)++_slot_refs[slot];
            if(old!=_pages.end() && old->second.slot!=slot && --_slot_refs[old->second.slot]==0) {
                retired=old->second.slot;
                if(old->second.shared)_uniform_slots.erase(_slot_values[retired]);
            }
            if(old==_pages.end())_newly_ready.push_back(page.position);
            _pages[page.position]={slot,page.revision,page.light_revision,same};_table_dirty=true;
            {std::lock_guard<std::mutex> guard(_state->mutex);_state->published_versions[page.position]={page.revision,page.light_revision};}
            if(retired>=0)retired_slots.push_back(retired);
            // Source selection is independent from surface emission and propagated block light.
            for(int i=_sources.size()-1;i>=0;--i){Dictionary item=_sources[i];if(Vector3i(item["section"])==vec(page.position))_sources.remove_at(i);}
            for(auto source:page.sources){Dictionary item;item["section"]=vec(page.position);item["state"]=int(source.state);item["position"]=vec(page.position)*16+Vector3i(source.index%16,(source.index/16)%16,source.index/256);_sources.append(item);}
            ++_source_revision;
            ++_published;
            if(page.started)_state->latency_usec=now_usec()-page.started;
        }
        while(now_usec()-start<limit && bytes+_table_upload_bytes+table_reserve+2048<=_upload_bytes) {
            State::WeatherPage page;
            {std::lock_guard<std::mutex> guard(_state->mutex);if(_state->weather_ready.empty())break;page=_state->weather_ready.front();_state->weather_ready.pop_front();}
            if(!in_radius(page.position,_center,(_horizontal+15)/16+1))continue;
            bool valid=true;
            for(int y=-4;y<12;++y)if(_state->data->get_section_revision(Vector3i(page.position.x,y,page.position.z))!=page.revisions[y+4])valid=false;
            if(!valid){++_stale;continue;}
            auto it=_weather_slots.find(page.position);
            if(it==_weather_slots.end() && _free_weather_slots.empty()) {
                ++_capacity_pressure;_capacity_blocked=true;
                std::lock_guard<std::mutex> guard(_state->mutex);_state->weather_ready.push_back(std::move(page));break;
            }
            const int slot=it==_weather_slots.end()?_free_weather_slots.back():it->second;
            if(it==_weather_slots.end())_free_weather_slots.pop_back();
            PackedByteArray pixels;pixels.resize(2048);std::memcpy(pixels.ptrw(),page.pixels.data(),2048);
            _weather_pool->queue_page(slot,pixels);
            _weather_slots[page.position]=slot;_table_dirty=true;++_weather_uploads;bytes+=2048;
        }
        _pool->flush();_weather_pool->flush();
        if(_table_dirty)rebuild_table();
        for(int slot:retired_slots)_free_slots.push_back(slot);
        _uploaded_bytes+=bytes+_table_upload_bytes;
        _last_upload_usec=now_usec()-start;_peak_upload_usec=std::max(_peak_upload_usec,_last_upload_usec);
        engine.charge_commit_usec(_last_upload_usec);
    }
    schedule();
}
bool AstraeonSectionCache::is_ready() const {
    std::lock_guard<std::mutex> guard(_state->mutex);
    return _published>0 && _state->settled && _state->ready.empty() && _state->weather_ready.empty()
        && _pool->queued_bytes()==0 && _weather_pool->queued_bytes()==0;
}
Array AstraeonSectionCache::get_light_sources() const{return _sources;}
Dictionary AstraeonSectionCache::get_cache_metrics() const {
    Dictionary d;
    d["capacity_blocked"]=_capacity_blocked;
    uint64_t temporary=_state->queue_bytes;
    {std::lock_guard<std::mutex> guard(_state->mutex);
        temporary+=_state->ready.size()*sizeof(State::ReadyPage)+_state->weather_ready.size()*sizeof(State::WeatherPage)+_state->requested.size()*sizeof(SectionKey);
        for(const auto &page:_state->ready)temporary+=page.sources.capacity()*sizeof(LightSection::Source);
        d["pending_light_uploads"]=int64_t(_state->ready.size());
        d["pending_weather_uploads"]=int64_t(_state->weather_ready.size());
    }
    temporary+=VoxelEngine::get_singleton().get_cache_temporary_bytes();
    d["temporary_bytes"]=int64_t(temporary);
    d["weather_cpu_bytes"]=int64_t(_state->weather_bytes);
    d["source_revision"]=int64_t(_source_revision);
    d["native_voxel_pool_used_bytes"]=int64_t(VoxelMemoryPool::get_singleton().debug_get_used_memory());
    d["native_voxel_pool_reserved_bytes"]=int64_t(VoxelMemoryPool::get_singleton().debug_get_total_memory());
    const auto map=_state->data?_state->data->get_cache_metrics():VoxelData::CacheMetrics{};
    d["voxel_bytes"]=int64_t(map.voxel_bytes);d["warm_bytes"]=int64_t(map.warm_bytes);d["pinned_bytes"]=int64_t(map.pinned_bytes);
    d["map_hits"]=int64_t(map.hits);d["map_misses"]=int64_t(map.misses);d["map_evictions"]=int64_t(map.evictions);d["warm_sections"]=int64_t(map.warm_sections);
    d["derived_bytes"]=int64_t(_state->data?_state->data->get_derived_cache_bytes():0);
    d["light_bytes"]=int64_t(_state->light_bytes);d["light_hits"]=int64_t(_state->hits);d["section_reads"]=int64_t(_state->read_count);
    d["queue"]=int64_t(_state->queue_size);d["visits"]=int64_t(_state->visits);d["passes"]=int64_t(_state->passes);
    d["stale_results"]=int64_t(_stale+_state->stale);d["work_usec"]=int64_t(_state->work_usec);d["peak_slice_usec"]=int64_t(_state->peak_slice_usec);
    d["pages"]=int64_t(_pages.size());d["page_uploads"]=int64_t(_published);d["gpu_bytes"]=int64_t(_layers*4*16384);d["gpu_evictions"]=int64_t(_gpu_evictions);d["capacity_pressure"]=int64_t(_capacity_pressure);
    d["physical_light_pages"]=int64_t(_layers*4-_free_slots.size());
    d["weather_uploads"]=int64_t(_weather_uploads);d["weather_gpu_bytes"]=int64_t(2048*2048);
    d["upload_usec"]=int64_t(_last_upload_usec);d["peak_upload_usec"]=int64_t(_peak_upload_usec);d["uploaded_bytes"]=int64_t(_uploaded_bytes);d["light_latency_usec"]=int64_t(_state->latency_usec);
    d["render_upload_peak_usec"]=int64_t(_pool.is_valid()?_pool->render_upload_peak_usec():0);
    d["render_queued_bytes"]=int64_t((_pool.is_valid()?_pool->queued_bytes():0)+(_weather_pool.is_valid()?_weather_pool->queued_bytes():0));
    d["queue_wait_peak_usec"]=int64_t(VoxelEngine::get_singleton().get_queue_wait_peak_usec());
    d["native_tasks"]=int64_t(VoxelEngine::get_singleton().get_cache_task_count());
    d["commit_peak_usec"]=int64_t(VoxelEngine::get_singleton().get_commit_peak_usec());
    d["single_task_peak_usec"]=int64_t(VoxelEngine::get_singleton().get_single_task_peak_usec());
    d["single_task_peak_name"]=String(VoxelEngine::get_singleton().get_single_task_peak_name());
    d["unreclaimable_over_budget"]=map.pinned_bytes+_state->light_bytes+_state->weather_bytes+temporary>_state->cpu_budget;
    return d;
}
void AstraeonSectionCache::_bind_methods() {
    ClassDB::bind_method(D_METHOD("bind_weather_material","material"),&AstraeonSectionCache::bind_weather_material);
    ClassDB::bind_method(D_METHOD("set_weather","rain","accumulation","drying","enabled"),&AstraeonSectionCache::set_weather);
    ClassDB::bind_method(D_METHOD("configure","terrain","opacity","emission","sources","policy"),&AstraeonSectionCache::configure);
    ClassDB::bind_method(D_METHOD("set_interest","position","horizontal","vertical","velocity"),&AstraeonSectionCache::set_interest);
    ClassDB::bind_method(D_METHOD("invalidate_section","position"),&AstraeonSectionCache::invalidate_section);
    ClassDB::bind_method(D_METHOD("invalidate_area","position","size"),&AstraeonSectionCache::invalidate_area);
    ClassDB::bind_method(D_METHOD("apply_cache_policy","policy"),&AstraeonSectionCache::apply_cache_policy);
    ClassDB::bind_method(D_METHOD("bind_material","material"),&AstraeonSectionCache::bind_material);
    ClassDB::bind_method(D_METHOD("commit"),&AstraeonSectionCache::commit);
    ClassDB::bind_method(D_METHOD("shutdown"),&AstraeonSectionCache::shutdown);
    ClassDB::bind_method(D_METHOD("is_ready"),&AstraeonSectionCache::is_ready);
    ClassDB::bind_method(D_METHOD("set_suspended","enabled"),&AstraeonSectionCache::set_suspended);
    ClassDB::bind_method(D_METHOD("invalidate_sections","changes"),&AstraeonSectionCache::invalidate_sections);
    ClassDB::bind_method(D_METHOD("get_cache_metrics"),&AstraeonSectionCache::get_cache_metrics);
    ClassDB::bind_method(D_METHOD("get_light_sources"),&AstraeonSectionCache::get_light_sources);
}
}
