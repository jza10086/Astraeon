#include "astraeon_page_pool.h"
#include "util/godot/core/class_db.h"
#include "util/godot/core/callable_mp.h"
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/rd_texture_format.hpp>
#include <godot_cpp/classes/rd_texture_view.hpp>
#include <chrono>
namespace zylann::voxel {
using namespace ::godot;
static void release_page_pool(Array resources) {
    auto rd=RenderingServer::get_singleton()->get_rendering_device();
    if(rd==nullptr)return;
    for(int i=0;i<resources.size();++i){RID rid=resources[i];if(rd->texture_is_valid(rid))rd->free_rid(rid);}
}
AstraeonPagePool::~AstraeonPagePool() {
    auto rs=RenderingServer::get_singleton();if(rs==nullptr)return;
    Array resources;for(RID rid:_rids)if(rid.is_valid())resources.append(rid);
    if(_staging.is_valid())resources.append(_staging);
    // Wrappers may still be referenced by a material queued for deletion this frame.
    // Detach their RenderingServer handles before releasing their borrowed RD storage.
    for(auto &texture:_textures)texture->set_texture_rd_rid(RID());
    _textures.clear();
    rs->call_on_render_thread(callable_mp_static(release_page_pool).bind(resources));
}
void AstraeonPagePool::initialize(int pages_per_bank,int banks,int width,int height,bool weather) {
    _pages=pages_per_bank;_banks=banks;_width=width;_height=height;_weather=weather;
    _page_shift=4;
    if(!weather)while(_page_shift<8 && pages_per_bank%(1<<(_page_shift+1))==0)++_page_shift;
    _textures.resize(banks);_rids.resize(banks);
    for(auto &texture:_textures)texture.instantiate();
    RenderingServer::get_singleton()->call_on_render_thread(Callable(this,"render_create").bind(Ref<AstraeonPagePool>(this)));
}
void AstraeonPagePool::render_create(Ref<AstraeonPagePool> keep_alive) {
    auto rd=RenderingServer::get_singleton()->get_rendering_device();
    ERR_FAIL_NULL(rd);
    Ref<RDTextureFormat> format;format.instantiate();
    format->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D_ARRAY);
    format->set_format(_weather?RenderingDevice::DATA_FORMAT_R32G32_SFLOAT:RenderingDevice::DATA_FORMAT_R8G8B8A8_UNORM);
    format->set_width(_width*(1<<_page_shift));format->set_height(_height);format->set_array_layers(_pages>>_page_shift);
    format->set_usage_bits(RenderingDevice::TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice::TEXTURE_USAGE_CAN_COPY_TO_BIT|RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
    Ref<RDTextureView> view;view.instantiate();
    for(int bank=0;bank<_banks;++bank){
        _rids[bank]=rd->texture_create(format,view);
        ERR_FAIL_COND(!_rids[bank].is_valid());
        _textures[bank]->set_texture_rd_rid(_rids[bank]);
    }
    format->set_texture_type(RenderingDevice::TEXTURE_TYPE_2D);
    format->set_width(_width);format->set_array_layers(1);
    format->set_usage_bits(RenderingDevice::TEXTURE_USAGE_CAN_UPDATE_BIT|RenderingDevice::TEXTURE_USAGE_CAN_COPY_FROM_BIT);
    _staging=rd->texture_create(format,view);
    ERR_FAIL_COND(!_staging.is_valid());
    _ready=true;
}
void AstraeonPagePool::queue_page(int slot,PackedByteArray bytes) {
    _pending.append(slot);_pending.append(bytes);_queued_bytes+=bytes.size();
}
void AstraeonPagePool::flush() {
    if(_pending.is_empty())return;
    Array updates=_pending;_pending=Array();
    RenderingServer::get_singleton()->call_on_render_thread(Callable(this,"render_upload").bind(updates,Ref<AstraeonPagePool>(this)));
}
void AstraeonPagePool::render_upload(Array updates,Ref<AstraeonPagePool> keep_alive) {
    const auto start=std::chrono::steady_clock::now();
    auto rd=RenderingServer::get_singleton()->get_rendering_device();
    for(int i=0;i<updates.size();i+=2) {
        const int slot=updates[i],bank=slot/_pages,page=slot%_pages;
        PackedByteArray bytes=updates[i+1];
        ERR_CONTINUE(rd->texture_update(_staging,0,bytes)!=OK);
        ERR_CONTINUE(rd->texture_copy(_staging,_rids[bank],Vector3(),Vector3((page&((1<<_page_shift)-1))*_width,0,0),Vector3(_width,_height,1),0,0,0,page>>_page_shift)!=OK);
        _queued_bytes-=bytes.size();
    }
    const uint64_t elapsed=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
    _render_usec=elapsed;_peak_usec=std::max(_peak_usec.load(),elapsed);
}
void AstraeonPagePool::_bind_methods() {
    ClassDB::bind_method(D_METHOD("render_create","keep_alive"),&AstraeonPagePool::render_create);
    ClassDB::bind_method(D_METHOD("render_upload","updates","keep_alive"),&AstraeonPagePool::render_upload);
}
}
