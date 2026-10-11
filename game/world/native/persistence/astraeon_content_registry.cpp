#include "astraeon_content_registry.h"
#include "astraeon/data/content/astraeon_content_pack.h"
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/crypto.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <filesystem>
#include <cstdio>
#include <cstring>
#include <vector>
#include <set>
#ifdef _WIN32
#include <io.h>
#include <share.h>
#else
#include <unistd.h>
#endif
namespace zylann::voxel {
using namespace ::godot;
namespace {
constexpr uint64_t MAX_SIZE=16ull<<20;
void le(PackedByteArray &b,int o,uint64_t n,int size){for(int i=0;i<size;++i)b.set(o+i,uint8_t(n>>(i*8)));}
uint64_t rd(const PackedByteArray &b,int o,int size){uint64_t n=0;for(int i=0;i<size;++i)n|=uint64_t(b[o+i])<<(i*8);return n;}
Dictionary fail(const String &s){Dictionary d;d["error"]=s;return d;}
FILE *open(const std::filesystem::path &p,bool write){
#ifdef _WIN32
    return _wfsopen(p.c_str(),write?L"wb":L"rb",_SH_DENYWR);
#else
    return fopen(p.c_str(),write?"wb":"rb");
#endif
}
bool durable(FILE *f){
    if(fflush(f)!=0)return false;
#ifdef _WIN32
    return _commit(_fileno(f))==0;
#else
    return fsync(fileno(f))==0;
#endif
}
struct Record { bool exists=false,valid=false;uint64_t generation=0;Dictionary body; };
Record read(const std::filesystem::path &p){
    Record r;std::error_code ec;r.exists=std::filesystem::exists(p,ec);if(ec||!r.exists)return r;
    FILE *f=open(p,false);if(!f)return r;
    unsigned char header[56];if(fread(header,1,56,f)!=56){fclose(f);return r;}
    PackedByteArray h;h.resize(56);memcpy(h.ptrw(),header,56);
    const uint64_t size=rd(h,16,8);r.generation=rd(h,8,8);
    if(memcmp(header,"AEBREG03",8)!=0||size>MAX_SIZE||!r.generation){fclose(f);return r;}
    PackedByteArray bytes;bytes.resize(size);bool good=fread(bytes.ptrw(),1,size,f)==size&&fgetc(f)==EOF&&!ferror(f);fclose(f);
    PackedByteArray checked=h.slice(0,24);checked.append_array(bytes);
    if(!good||AstraeonContentPack::digest(checked)!=h.slice(24,56))return r;
    Ref<JSON> json;json.instantiate();if(json->parse(bytes.get_string_from_utf8())!=OK||json->get_data().get_type()!=Variant::DICTIONARY)return r;
    r.body=json->get_data();
    if(int(r.body.get("format",0))!=3||String(r.body.get("world","" )).length()!=32||r.body.get("states",Variant()).get_type()!=Variant::ARRAY)return r;
    Array states=r.body["states"];if(states.is_empty()||states.size()>65536)return r;
    Dictionary keys;
    for(int i=0;i<states.size();++i){
        if(states[i].get_type()!=Variant::DICTIONARY)return r;Dictionary state=states[i];String name=state.get("key",""),hash=state.get("contract","");
        if(name.is_empty()||keys.has(name)||hash.length()!=64)return r;keys[name]=true;
        if(i==0&&name!="astraeon:air/default")return r;
    }
    r.valid=true;return r;
}
}
Dictionary AstraeonContentRegistry::resolve(String directory,Dictionary contracts,PackedStringArray packages){
    if(contracts.is_empty()||contracts.size()>65536||!contracts.has("astraeon:air/default"))return fail("Invalid state contract table or more than 65536 states");
    Array current=contracts.keys();current.sort();
    for(int i=0;i<current.size();++i)if(current[i].get_type()!=Variant::STRING||String(contracts[current[i]]).length()!=64)return fail("Invalid state contract hash");
    const auto path=std::filesystem::u8path(ProjectSettings::get_singleton()->globalize_path(directory).utf8().get_data());
    std::error_code ec;std::filesystem::create_directories(path,ec);if(ec)return fail("Cannot create registry directory");
    Record records[2]={read(path/"content_registry.0"),read(path/"content_registry.1")};
    int newest=!records[0].valid?(records[1].valid?1:-1):(!records[1].valid||records[0].generation>=records[1].generation?0:1);
    if(newest<0&&(records[0].exists||records[1].exists))return fail("Both content registry records are unsupported or damaged");
    if(records[0].valid&&records[1].valid&&records[0].body["world"]!=records[1].body["world"])return fail("Registry records belong to different worlds");
    Dictionary body;Array states;uint64_t generation=0;bool changed=false;
    if(newest<0){
        for(const auto &entry:std::filesystem::directory_iterator(path,ec))if(entry.path().extension()==".avr")return fail("Unsupported old prototype world: registry is absent; existing files retained");
        if(ec)return fail("Cannot inspect existing world");
        Ref<Crypto> crypto;crypto.instantiate();body["world"]=crypto->generate_random_bytes(16).hex_encode();body["format"]=3;
        Dictionary air;air["key"]="astraeon:air/default";air["contract"]=contracts["astraeon:air/default"];states.append(air);changed=true;
    }else{body=records[newest].body;states=body["states"];generation=records[newest].generation;}
    Dictionary allocated;
    for(int i=0;i<states.size();++i){Dictionary state=states[i];String name=state["key"];if(!contracts.has(name)||contracts[name]!=state["contract"])return fail("Missing content or changed logical contract: "+name);allocated[name]=true;}
    for(int i=0;i<current.size();++i)if(!allocated.has(current[i])){Dictionary state;state["key"]=current[i];state["contract"]=contracts[current[i]];states.append(state);changed=true;}
    Array previous_packages=body.get("packages",Array());
    for(int i=0;i<previous_packages.size();++i)if(!packages.has(previous_packages[i]))return fail("Missing required package: "+String(previous_packages[i]));
    for(int i=0;i<packages.size();++i)if(!previous_packages.has(packages[i])){previous_packages.append(packages[i]);changed=true;}
    previous_packages.sort();body["packages"]=previous_packages;
    body["states"]=states;
    if(changed){
        if(generation==UINT64_MAX)return fail("Registry generation exhausted");
        PackedByteArray bytes=JSON::stringify(body,"",true,true).to_utf8_buffer();if(bytes.size()>MAX_SIZE)return fail("Registry exceeds size limit");
        PackedByteArray h;h.resize(56);h.fill(0);memcpy(h.ptrw(),"AEBREG03",8);le(h,8,++generation,8);le(h,16,bytes.size(),8);
        PackedByteArray checked=h.slice(0,24);checked.append_array(bytes);PackedByteArray hash=AstraeonContentPack::digest(checked);memcpy(h.ptrw()+24,hash.ptr(),32);
        for(int mirror=0;mirror<2;++mirror){int slot=mirror==0?(newest==0?1:0):(newest==0?0:1);FILE *f=open(path/(slot==0?"content_registry.0":"content_registry.1"),true);if(!f)return fail("Cannot write content registry; IDs not published");
        bool ok=fwrite(h.ptr(),1,h.size(),f)==size_t(h.size())&&fwrite(bytes.ptr(),1,bytes.size(),f)==size_t(bytes.size())&&durable(f);fclose(f);
        if(!ok)return fail("Registry durable write failed; IDs not published");}
    }
    PackedStringArray keys;for(int i=0;i<states.size();++i){Dictionary state=states[i];keys.append(state["key"]);}
    Dictionary result;result["state_keys"]=keys;result["world_id"]=body["world"];result["generation"]=generation;result["appended"]=changed;return result;
}
bool AstraeonContentRegistry::validate_table(String directory,PackedStringArray keys,String world_id) {
    auto path=std::filesystem::u8path(ProjectSettings::get_singleton()->globalize_path(directory).utf8().get_data());
    Record a=read(path/"content_registry.0"),b=read(path/"content_registry.1");
    if(a.valid&&b.valid&&a.body["world"]!=b.body["world"])return false;
    const Record *r=!a.valid?(b.valid?&b:nullptr):(!b.valid||a.generation>=b.generation?&a:&b);
    if(r==nullptr||String(r->body["world"])!=world_id)return false;
    Array states=r->body["states"];if(states.size()!=keys.size())return false;
    for(int i=0;i<keys.size();++i){Dictionary state=states[i];if(String(state["key"])!=keys[i])return false;}return true;
}
void AstraeonContentRegistry::_bind_methods(){ClassDB::bind_method(D_METHOD("resolve","directory","contracts","packages"),&AstraeonContentRegistry::resolve);}
}
