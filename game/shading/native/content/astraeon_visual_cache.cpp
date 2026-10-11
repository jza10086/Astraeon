#include "astraeon_visual_cache.h"
#include "astraeon/data/content/astraeon_content_pack.h"
#include "engine/voxel_engine.h"
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
namespace zylann::voxel {
using namespace ::godot;
namespace { uint64_t clock_usec(){return Time::get_singleton()->get_ticks_usec();} std::string key(String s){return s.utf8().get_data();} }
AstraeonVisualCache::~AstraeonVisualCache(){shutdown();}
bool AstraeonVisualCache::configure(Dictionary p) {
    int cpu=p.get("visual_cpu_mib",64),gpu=p.get("visual_gpu_mib",128),jobs=p.get("visual_jobs",2),us=p.get("visual_upload_usec",500),bytes=p.get("visual_upload_bytes",2097152);
    double warm=p.get("visual_warm_seconds",30.0);
    if(cpu<1||cpu>8192||gpu<1||gpu>8192||jobs<1||jobs>8||us<1||bytes<1||warm<0||warm>3600)return false;
    uint64_t pinned=0;for(const auto &[hash,e]:_entries)if(e.pinned)pinned+=uint64_t(e.width)*e.height*4;
    if(pinned>(uint64_t(cpu)<<20)||pinned>(uint64_t(gpu)<<20)){_pressure="Pinned visual capacity exceeded";return false;}
    _cpu_limit=uint64_t(cpu)<<20;_gpu_limit=uint64_t(gpu)<<20;_max_jobs=jobs;_upload_usec=us;_upload_bytes=bytes;_warm_usec=uint64_t(warm*1000000);return true;
}
bool AstraeonVisualCache::register_visual(String hash,String pack,int width,int height,bool pinned) {
    for(const auto &[k,e]:_entries)if(e.job)return false;
    if(_closed||hash.length()!=64||width<1||height<1||uint64_t(width)*height*4>(64ull<<20))return false;
    auto found=_entries.find(key(hash));
    if(found!=_entries.end()){if(found->second.width!=width||found->second.height!=height)return false;found->second.pinned|=pinned;return true;}
    if(_readers.find(key(pack))==_readers.end()){
        Ref<AstraeonContentPack> reader;reader.instantiate();Dictionary metadata=reader->open_pack(pack);
        if(metadata.has("error"))return false;
        _read_bytes+=int64_t(reader->get_metrics()["read_bytes"]);_readers[key(pack)]=reader;
    }
    Dictionary info=_readers[key(pack)]->blob_info(hash);
    if(info.is_empty()||int64_t(info["raw"])!=int64_t(width)*height*4+16)return false;
    auto &e=_entries[key(hash)];e.path=pack;e.width=width;e.height=height;e.pinned=pinned;e.touched=clock_usec();return true;
}
void AstraeonVisualCache::bind_material(String hash,Ref<ShaderMaterial> material) {
    auto it=_entries.find(key(hash));if(it==_entries.end()||material.is_null())return;
    it->second.materials.append(material);material->set_shader_parameter("block_atlas",it->second.gpu);
}
bool AstraeonVisualCache::request(String owner,PackedStringArray hashes) {
    if(_closed)return false;
    for(int i=0;i<hashes.size();++i)if(_entries.find(key(hashes[i]))==_entries.end())return false;
    release(owner);Dictionary unique;
    for(int i=0;i<hashes.size();++i) {
        if(unique.has(hashes[i]))continue;unique[hashes[i]]=true;
        auto &e=_entries[key(hashes[i])];++e.references;e.touched=clock_usec();
        if(e.gpu.is_valid())++_hits;else {++_misses;if(e.requested==0)e.requested=clock_usec();}
    }
    _owners[owner]=unique.keys();return true;
}
void AstraeonVisualCache::release(String owner) {
    if(!_owners.has(owner))return;
    Array hashes=_owners[owner];for(int i=0;i<hashes.size();++i){auto &e=_entries[key(hashes[i])];--e.references;e.touched=clock_usec();}
    _owners.erase(owner);
}
bool AstraeonVisualCache::is_ready(PackedStringArray hashes) const {
    for(int i=0;i<hashes.size();++i){auto it=_entries.find(key(hashes[i]));if(it==_entries.end()||it->second.gpu.is_null())return false;}return !_closed;
}
Ref<ImageTexture> AstraeonVisualCache::texture(String hash) const {auto i=_entries.find(key(hash));return i==_entries.end()?Ref<ImageTexture>():i->second.gpu;}
void AstraeonVisualCache::read_job(String hash) {
    auto job=_entries.at(key(hash)).job;
    job->bytes=job->reader->read_blob(hash);
    const auto &entry=_entries.at(key(hash));
    if(!job->bytes.is_empty()) {
        if(job->bytes.size()<16||job->bytes.decode_u32(0)!=0x31545641||job->bytes.decode_u32(4)!=entry.width||job->bytes.decode_u32(8)!=entry.height||job->bytes.decode_u32(12)!=1){job->bytes.clear();job->error="Invalid visual interpretation header";}
        else job->bytes=job->bytes.slice(16);
    }
    if(job->bytes.is_empty()&&job->error.is_empty())job->error=job->reader->get_error();
    job->read_bytes=int64_t(job->reader->blob_info(hash)["compressed"]);
    job->done.store(true,std::memory_order_release);
}
void AstraeonVisualCache::commit() {
    if(_closed)return;
    auto &engine=VoxelEngine::get_singleton();const uint64_t start=clock_usec(),limit=std::min<uint64_t>(_upload_usec,engine.get_remaining_commit_usec());
    uint64_t cpu=0,gpu=0,reserved=0,uploaded=0;int running=0;_pressure="";
    for(auto &[hash,e]:_entries) {
        cpu+=e.cpu.size();if(e.gpu.is_valid())gpu+=uint64_t(e.width)*e.height*4;
        if(e.job) {
            if(!e.job->done.load(std::memory_order_acquire)){++running;reserved+=uint64_t(e.width)*e.height*8+16+int64_t(_readers.at(key(e.path))->blob_info(String(hash.c_str()))["compressed"]);continue;}
            WorkerThreadPool::get_singleton()->wait_for_task_completion(e.job->task);
            _reads++;_read_bytes+=e.job->read_bytes;e.error=e.job->error;
            if(!_closed&&(e.pinned||e.references>0)){e.cpu=e.job->bytes;cpu+=e.cpu.size();}
            e.job.reset();
        }
    }
    // Evict only unreferenced entries, oldest first. Referenced and pinned data may exceed the soft limits.
    uint64_t next_cpu=0,next_gpu=0;
    for(const auto &[hash,e]:_entries)if((e.pinned||e.references>0)&&e.gpu.is_null()){
        const uint64_t size=uint64_t(e.width)*e.height*4;next_gpu=std::max(next_gpu,size);if(e.cpu.is_empty()&&!e.job)next_cpu=std::max(next_cpu,size);
    }
    std::vector<Entry*> warm;
    for(auto &[hash,e]:_entries)if(!e.pinned&&e.references==0&&!e.job)warm.push_back(&e);
    std::sort(warm.begin(),warm.end(),[](Entry *a,Entry *b){return a->touched<b->touched;});
    for(Entry *e:warm)if(clock_usec()-e->touched>=_warm_usec||cpu+reserved+next_cpu>_cpu_limit||gpu+next_gpu>_gpu_limit) {
        if(e->gpu.is_valid()){gpu-=uint64_t(e->width)*e->height*4;for(int i=0;i<e->materials.size();++i){Ref<ShaderMaterial> m=e->materials[i];m->set_shader_parameter("block_atlas",Variant());}e->gpu.unref();++_evictions;}
        cpu-=e->cpu.size();e->cpu=PackedByteArray();e->requested=0;
    }
    for(auto &[hash,e]:_entries) {
        if((!e.pinned&&e.references==0)||!e.error.is_empty()||e.gpu.is_valid())continue;
        const uint64_t size=uint64_t(e.width)*e.height*4;
        if(e.cpu.is_empty()&&!e.job) {
            if(running>=_max_jobs)continue;
            const uint64_t task_reserve=size*2+16+int64_t(_readers.at(key(e.path))->blob_info(String(hash.c_str()))["compressed"]);
            if(cpu+reserved+task_reserve>_cpu_limit){_pressure="CPU visual capacity";continue;}
            e.job=std::make_shared<Job>();e.job->pack=e.path;e.job->hash=String(hash.c_str());e.job->reader=_readers.at(key(e.path));
            
            e.job->task=WorkerThreadPool::get_singleton()->add_task(Callable(this,"_read_job").bind(e.job->hash),false,"Content visual read");
            ++running;reserved+=task_reserve;continue;
        }
        if(e.cpu.is_empty()||limit==0||clock_usec()-start>=limit)continue;
        if(gpu+size>_gpu_limit){_pressure="GPU visual capacity";continue;}
        if(uploaded>0&&uploaded+size>_upload_bytes)continue;
        if(e.cpu.size()!=int64_t(size)){e.error="Visual dimensions do not match payload";continue;}
        Ref<Image> im=Image::create_from_data(e.width,e.height,false,Image::FORMAT_RGBA8,e.cpu);
        uint64_t before=clock_usec();e.gpu=ImageTexture::create_from_image(im);
        for(int i=0;i<e.materials.size();++i){Ref<ShaderMaterial> m=e.materials[i];m->set_shader_parameter("block_atlas",e.gpu);}
        if(clock_usec()-before>_upload_usec||size>_upload_bytes)++_overruns;
        _uploads++;_uploaded+=size;uploaded+=size;gpu+=size;
        if(e.requested)_max_latency=std::max(_max_latency,clock_usec()-e.requested);
    }
    engine.charge_commit_usec(clock_usec()-start);
}
void AstraeonVisualCache::shutdown() {
    if(_closed)return;_closed=true;
    for(auto &[hash,e]:_entries)if(e.job){WorkerThreadPool::get_singleton()->wait_for_task_completion(e.job->task);e.job.reset();}
    _owners.clear();_entries.clear();_readers.clear();
}
Dictionary AstraeonVisualCache::get_metrics() const {
    uint64_t cpu=0,gpu=0,pinned=0,temporary=0;int pending=0,queued=0;Array failures;
    for(const auto &[hash,e]:_entries){if((e.pinned||e.references>0)&&e.gpu.is_null()&&!e.job&&e.error.is_empty())++queued;cpu+=e.cpu.size();if(e.gpu.is_valid()){gpu+=uint64_t(e.width)*e.height*4;if(e.pinned)pinned+=uint64_t(e.width)*e.height*4;}if(e.job){temporary+=uint64_t(e.width)*e.height*8+16+int64_t(_readers.at(key(e.path))->blob_info(String(hash.c_str()))["compressed"]);++pending;}if(!e.error.is_empty())failures.append(String(hash.c_str())+": "+e.error);}
    Dictionary d;d["cpu_bytes"]=cpu;d["gpu_bytes"]=gpu;d["pinned_gpu_bytes"]=pinned;d["temporary_bytes"]=temporary;d["pending"]=pending;d["queued"]=queued;d["hits"]=_hits;d["misses"]=_misses;d["reads"]=_reads;d["read_bytes"]=_read_bytes;d["upload_bytes"]=_uploaded;d["uploads"]=_uploads;d["evictions"]=_evictions;d["upload_overruns"]=_overruns;d["max_visible_latency_usec"]=_max_latency;d["pressure"]=_pressure;d["failures"]=failures;return d;
}
void AstraeonVisualCache::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","policy"),&AstraeonVisualCache::configure);
    ClassDB::bind_method(D_METHOD("register_visual","hash","pack","width","height","pinned"),&AstraeonVisualCache::register_visual);
    ClassDB::bind_method(D_METHOD("bind_material","hash","material"),&AstraeonVisualCache::bind_material);
    ClassDB::bind_method(D_METHOD("request","owner","hashes"),&AstraeonVisualCache::request);
    ClassDB::bind_method(D_METHOD("release","owner"),&AstraeonVisualCache::release);
    ClassDB::bind_method(D_METHOD("is_ready","hashes"),&AstraeonVisualCache::is_ready);
    ClassDB::bind_method(D_METHOD("texture","hash"),&AstraeonVisualCache::texture);
    ClassDB::bind_method(D_METHOD("commit"),&AstraeonVisualCache::commit);
    ClassDB::bind_method(D_METHOD("shutdown"),&AstraeonVisualCache::shutdown);
    ClassDB::bind_method(D_METHOD("get_metrics"),&AstraeonVisualCache::get_metrics);
    ClassDB::bind_method(D_METHOD("_read_job","hash"),&AstraeonVisualCache::read_job);
}
}
