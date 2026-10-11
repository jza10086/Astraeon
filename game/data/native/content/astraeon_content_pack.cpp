#include "astraeon_content_pack.h"
#include "util/math/ortho_basis.h"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <cstring>
#ifdef _WIN32
#include <windows.h>
#endif
namespace zylann::voxel {
using namespace godot;
namespace {
constexpr uint64_t HEADER = 64, ENTRY = 88, MAX_META = 16 * 1024 * 1024, MAX_BLOB = 64 * 1024 * 1024;
constexpr uint64_t MAX_ENTRIES = 65536, MAX_FILE = uint64_t(8) * 1024 * 1024 * 1024;
void put(PackedByteArray &b, uint64_t offset, uint64_t v, int count) {
    for (int i=0;i<count;++i) b.set(offset+i, uint8_t(v>>(i*8)));
}
uint64_t read_le(const PackedByteArray &b, uint64_t offset, int count) {
    uint64_t v=0; for(int i=0;i<count;++i) v |= uint64_t(b[offset+i]) << (i*8); return v;
}
bool safe_id(const String &s) {
    if(s.is_empty() || s.length()>160) return false;
    for(int i=0;i<s.length();++i) {
        const char32_t c=s[i]; if(!((c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'||c=='-'||c==':'||c=='/'||c=='.')) return false;
    }
    return true;
}
bool package_id(const String &s) {
    if(s.is_empty()||s.length()>80)return false;
    for(int i=0;i<s.length();++i){char32_t c=s[i];if(!((c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'||c=='-'))return false;}
    return true;
}
bool data_only(const Variant &v, int depth=0) {
    if(depth>24) return false;
    switch(v.get_type()) {
        case Variant::NIL: case Variant::BOOL: case Variant::INT: case Variant::STRING: return true;
        case Variant::FLOAT: return std::isfinite(double(v));
        case Variant::ARRAY: { Array a=v; if(a.size()>65536) return false; for(int i=0;i<a.size();++i) if(!data_only(a[i],depth+1)) return false; return true; }
        case Variant::DICTIONARY: { Dictionary d=v; if(d.size()>65536) return false; Array keys=d.keys(); for(int i=0;i<keys.size();++i) if(keys[i].get_type()!=Variant::STRING || !data_only(d[keys[i]],depth+1)) return false; return true; }
        default: return false;
    }
}
bool numbers(const Variant &v,int size,double minimum=-1e12,double maximum=1e12) {
    if(v.get_type()!=Variant::ARRAY)return false;Array a=v;if(a.size()!=size)return false;
    for(int i=0;i<a.size();++i)if((a[i].get_type()!=Variant::INT&&a[i].get_type()!=Variant::FLOAT)||double(a[i])<minimum||double(a[i])>maximum)return false;
    return true;
}
bool mining_tag(const Variant &v) {
    if(v.get_type()!=Variant::STRING)return false;
    String s=v;
    return safe_id(s)&&s.count(":")==1&&!s.contains("/")&&!s.get_slice(":",0).is_empty()&&!s.get_slice(":",1).is_empty();
}
bool number_range(const Variant &v, double lo, double hi) {
    return (v.get_type()==Variant::INT||v.get_type()==Variant::FLOAT)&&std::isfinite(double(v))&&double(v)>=lo&&double(v)<=hi;
}
bool visual_parameters(const Dictionary &b) {
    if(String(b.get("kind",""))=="water"){
        if(b.get("water",Variant()).get_type()!=Variant::DICTIONARY||!String(b.get("visual","")).is_empty())return false;
        Dictionary w=b["water"];
        for(const char *field:{"shallow_color","deep_color","underwater_color"})if(!numbers(w.get(field,Variant()),4,0,1))return false;
        for(const char *field:{"absorption","opacity","uniform_opacity","roughness","specular","wave_strength","wave_scale","wave_speed","sky_strength","scene_reflection_strength","underwater_attenuation_rate","underwater_attenuation_start"})if(!w.has(field)||(w[field].get_type()!=Variant::INT&&w[field].get_type()!=Variant::FLOAT)||double(w[field])<0)return false;
        return true;
    }
    if(String(b.get("kind",""))!="cube"||b.get("surface",Variant()).get_type()!=Variant::DICTIONARY)return false;
    Dictionary s=b["surface"];int resolution=s.get("resolution",-1),alpha=s.get("alpha",-1);
    if(resolution<0||resolution>1024||alpha<0||alpha>1)return false;
    if((resolution==0)!=String(b.get("visual","")).is_empty())return false;
    if(s.get("colors",Variant()).get_type()!=Variant::ARRAY||s.get("orm",Variant()).get_type()!=Variant::ARRAY||s.get("glow",Variant()).get_type()!=Variant::ARRAY)return false;
    Array colors=s["colors"],orm=s["orm"],glow=s["glow"];
    if(colors.size()!=6||orm.size()!=6||glow.size()!=6)return false;
    for(int i=0;i<6;++i)if(!numbers(colors[i],4,0,1)||!numbers(orm[i],2,0,1)||!numbers(glow[i],3,0,1e9))return false;
    if(!s.has("cutoff")||!s.has("double_sided")||!s.has("specular")||!s.has("foliage_layers"))return false;
    if(double(s["cutoff"])<0||double(s["cutoff"])>1||double(s["specular"])<0||double(s["specular"])>1)return false;
    if(b.has("light")) {
        if(b["light"].get_type()!=Variant::DICTIONARY)return false;Dictionary l=b["light"];
        if(!numbers(l.get("color",Variant()),4,0,1)||!numbers(l.get("offset",Variant()),3))return false;
        for(const char *field:{"energy","range","attenuation","radius","shadow_policy"})if(!l.has(field)||double(l[field])<0)return false;
    }
    return true;
}
bool valid_definitions(const Dictionary &d, const Dictionary &blobs) {
    if(!data_only(d) || int(d.get("api",0))!=1 || !package_id(d.get("id",""))) return false;
    if(d.get("blocks",Variant()).get_type()!=Variant::ARRAY || d.get("items",Variant()).get_type()!=Variant::ARRAY || d.get("dependencies",Variant()).get_type()!=Variant::ARRAY) return false;
    Array blocks=d["blocks"], items=d["items"], deps=d["dependencies"]; Dictionary ids; uint64_t count=0;
    for(int i=0;i<deps.size();++i) if(deps[i].get_type()!=Variant::STRING || !package_id(deps[i])) return false;
    for(int i=0;i<blocks.size();++i) {
        if(blocks[i].get_type()!=Variant::DICTIONARY) return false;
        Dictionary b=blocks[i]; String id=b.get("id","");
        if(!safe_id(id) || id.count(":")!=1 || ids.has(id) || b.get("states",Variant()).get_type()!=Variant::ARRAY) return false;
        if(!id.begins_with(String(d["id"])+":")||!visual_parameters(b)||!b.has("collision")||!b.has("name"))return false;
        if(String(b["kind"])=="cube") {
            Variant tag=b.get("required_tool_tag",Variant());
            if(tag.get_type()!=Variant::STRING||(!String(tag).is_empty()&&!mining_tag(tag))||!number_range(b.get("hardness",Variant()),0,1e12)||!number_range(b.get("mining_recovery_seconds",Variant()),0,3600))return false;
        }
        ids[id]=true; Array states=b["states"]; count+=states.size();
        if(states.is_empty() || count>65535 || (String(b.get("load_policy",""))!="preload" && String(b.get("load_policy",""))!="on_demand")) return false;
        String visual=b.get("visual",""); if(!visual.is_empty() && !blobs.has(visual)) return false;
        Dictionary names;
        for(int j=0;j<states.size();++j) {
            if(states[j].get_type()!=Variant::DICTIONARY) return false;
            Dictionary state=states[j]; String name=state.get("name","");
            if(!safe_id(name)||name.contains("/")||names.has(name)||int(state.get("rotation",-1))<0||int(state.get("rotation",-1))>=24) return false;
            if(int(state.get("logical_rotation",-1))<0||int(state.get("logical_rotation",-1))>=24)return false;
            if(state.has("light_offset")&&!numbers(state["light_offset"],3))return false;
            names[name]=true;
        }
        if(!names.has(b.get("default_state","default"))) return false;
        if(int(b.get("opacity",-1))<0||int(b.get("opacity",16))>15||int(b.get("emission",-1))<0||int(b.get("emission",16))>15) return false;
    }
    Dictionary item_ids;
    for(int i=0;i<items.size();++i) {
        if(items[i].get_type()!=Variant::DICTIONARY) return false;
        Dictionary item=items[i]; String id=item.get("id","");
        if(!safe_id(id)||id.count(":")!=1||item_ids.has(id)) return false;
        if(!id.begins_with(String(d["id"])+":")||(!item.has("block")||item["block"].get_type()!=Variant::STRING||(!String(item["block"]).is_empty()&&!safe_id(item["block"]))||(String(item["block"]).is_empty()&&bool(item.get("orient_to_face",false))))||!item.has("name")||!item.has("group")||item.get("tags",Variant()).get_type()!=Variant::ARRAY||!item.has("orient_to_face")||!numbers(item.get("color",Variant()),4,0,1)||int(item.get("max_stack",0))<1||int(item.get("max_stack",1000))>999)return false;
        if(item.get("tool_tags",Variant()).get_type()!=Variant::ARRAY||!number_range(item.get("mining_speed",Variant()),1,1000))return false;
        Array tool_tags=item["tool_tags"]; Dictionary seen_tags;
        for(int t=0;t<tool_tags.size();++t){Variant tag=tool_tags[t];if(!mining_tag(tag)||seen_tags.has(tag))return false;seen_tags[tag]=true;}
        if(item.has("icon")&&(int(item.get("icon_width",0))<1||int(item.get("icon_height",0))<1||int64_t(item.get("icon_width",0))*int64_t(item.get("icon_height",0))*4>MAX_BLOB))return false;
        item_ids[id]=true; String icon=item.get("icon",""); if(!icon.is_empty()&&!blobs.has(icon)) return false;
    }
    return true;
}
Dictionary failure(const String &s) { Dictionary d; d["error"]=s; return d; }
}
PackedByteArray AstraeonContentPack::digest(const PackedByteArray &bytes) {
    Ref<HashingContext> h; h.instantiate(); h->start(HashingContext::HASH_SHA256); h->update(bytes); return h->finish();
}
Dictionary AstraeonContentPack::compile_visual(Array faces, int resolution) {
    if(faces.size()!=6 || resolution<1 || resolution>1024) return failure("Expected six faces and resolution 1..1024");
    bool textured=false; Array colors, orm, glow;
    for(int i=0;i<6;++i) {
        Dictionary f=faces[i]; Ref<Image> im=f.get("image",Variant()); textured |= im.is_valid();
        Color color=f.get("color",Color(1,1,1,1)); Array c; c.append(color.r);c.append(color.g);c.append(color.b);c.append(color.a);colors.append(c);
        Array o; o.append(double(f.get("roughness",1.0)));o.append(double(f.get("metallic",0.0)));orm.append(o);
        Color e=f.get("emission",Color(0,0,0)); Array g;g.append(e.r);g.append(e.g);g.append(e.b);glow.append(g);
    }
    Dictionary out;out["colors"]=colors;out["orm"]=orm;out["glow"]=glow;out["resolution"]=textured?resolution:0;
    if(!textured) {out["pixels"]=PackedByteArray();return out;}
    Ref<Image> atlas=Image::create_empty(resolution*6,resolution,false,Image::FORMAT_RGBA8);
    for(int face=0;face<6;++face) {
        Dictionary f=faces[face]; Ref<Image> im=f.get("image",Variant());
        if(im.is_valid() && (im->is_compressed() || im->is_empty())) return failure("Source image must be decoded by authoring frontend");
        Color base=f.get("color",Color(1,1,1,1)); int turns=int(f.get("rotation",0))/90;
        Vector2i mirror=f.get("mirror",Vector2i());
        for(int y=0;y<resolution;++y) for(int x=0;x<resolution;++x) {
            Color c=base;
            if(im.is_valid()) {
                double u=(x+.5)/resolution, v=(y+.5)/resolution;
                if(mirror.x) u=1-u; if(mirror.y) v=1-v;
                for(int t=0;t<turns;++t){double old=u;u=1-v;v=old;}
                c=c*im->get_pixel(std::min(im->get_width()-1,int(u*im->get_width())),std::min(im->get_height()-1,int(v*im->get_height())));
            }
            atlas->set_pixel(face*resolution+x,y,c);
        }
    }
    out["pixels"]=atlas->get_data(); return out;
}
Dictionary AstraeonContentPack::write_pack(String path, Dictionary definitions, Dictionary blobs) {
    if(!valid_definitions(definitions,blobs) || blobs.size()>MAX_ENTRIES) return failure("Invalid content schema or references");
    PackedByteArray meta=JSON::stringify(definitions,"",true,true).to_utf8_buffer();
    if(meta.size()>MAX_META) return failure("Metadata exceeds limit");
    Array keys=blobs.keys();keys.sort(); PackedByteArray index;index.resize(keys.size()*ENTRY);index.fill(0);
    Array payloads; uint64_t offset=HEADER+meta.size()+index.size(), raw_total=0;
    for(int i=0;i<keys.size();++i) {
        PackedByteArray raw=blobs[keys[i]]; PackedByteArray hash=digest(raw);
        if(raw.is_empty()||raw.size()>MAX_BLOB||hash.hex_encode()!=String(keys[i])) return failure("Invalid visual content hash or size");
        PackedByteArray compressed=raw.compress(FileAccess::COMPRESSION_ZSTD);
        if(compressed.is_empty()) return failure("Compression failed");
        uint64_t at=i*ENTRY; for(int j=0;j<32;++j) index.set(at+j,hash[j]);
        put(index,at+32,offset,8);put(index,at+40,compressed.size(),8);put(index,at+48,raw.size(),8);
        PackedByteArray stored_hash=digest(compressed);for(int j=0;j<32;++j) index.set(at+56+j,stored_hash[j]);
        offset+=compressed.size();raw_total+=raw.size();payloads.append(compressed);
    }
    if(offset>MAX_FILE) return failure("Pack exceeds maximum size");
    PackedByteArray header;header.resize(HEADER);header.fill(0);const char *magic="AEBPACK1";for(int i=0;i<8;++i) header.set(i,magic[i]);
    put(header,8,1,4);put(header,12,keys.size(),4);put(header,16,meta.size(),8);put(header,24,offset,8);
    PackedByteArray signed_index=meta;signed_index.append_array(index);PackedByteArray hash=digest(signed_index);
    for(int i=0;i<32;++i) header.set(32+i,hash[i]);
    String temp=path+".pending";
    Ref<FileAccess> file=FileAccess::open(temp,FileAccess::WRITE);
    if(file.is_null()) return failure("Cannot create temporary package");
    file->store_buffer(header);file->store_buffer(meta);file->store_buffer(index);
    for(int i=0;i<payloads.size();++i) file->store_buffer(payloads[i]);
    file->flush();if(file->get_error()!=OK) return failure("Package write failed; previous output preserved");file.unref();
#ifdef _WIN32
    String source=ProjectSettings::get_singleton()->globalize_path(temp), dest=ProjectSettings::get_singleton()->globalize_path(path);
    if(!MoveFileExW((LPCWSTR)source.utf16().get_data(),(LPCWSTR)dest.utf16().get_data(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)) return failure("Atomic package replacement failed");
#else
    if(DirAccess::rename_absolute(temp,path)!=OK) return failure("Atomic package replacement failed");
#endif
    Dictionary result;result["bytes"]=offset;result["raw_bytes"]=raw_total;result["unique_blobs"]=keys.size();result["index_sha256"]=hash.hex_encode();return result;
}
Dictionary AstraeonContentPack::open_pack(String path) {
    _path="";_index.clear();_error="";
    Ref<FileAccess> file=FileAccess::open(path,FileAccess::READ);
    if(file.is_null()) return failure(_error="Cannot open content package: "+path);
    uint64_t length=file->get_length();if(length<HEADER||length>MAX_FILE) return failure(_error="Invalid package size");
    PackedByteArray h=file->get_buffer(HEADER);
    if(h.slice(0,8).get_string_from_ascii()!="AEBPACK1"||read_le(h,8,4)!=1||read_le(h,24,8)!=length) return failure(_error="Unsupported or truncated package");
    uint64_t count=read_le(h,12,4), meta_size=read_le(h,16,8);
    if(count>MAX_ENTRIES||meta_size>MAX_META||HEADER+meta_size+count*ENTRY>length) return failure(_error="Invalid package index bounds");
    PackedByteArray meta=file->get_buffer(meta_size), index=file->get_buffer(count*ENTRY), combined=meta;combined.append_array(index);
    if(digest(combined)!=h.slice(32,64)) return failure(_error="Package metadata checksum mismatch");
    Dictionary pending;uint64_t next=HEADER+meta_size+count*ENTRY;
    for(uint64_t i=0;i<count;++i) {
        uint64_t at=i*ENTRY, offset=read_le(index,at+32,8), compressed=read_le(index,at+40,8), raw=read_le(index,at+48,8);
        String hash=index.slice(at,at+32).hex_encode();
        if(pending.has(hash)||offset!=next||compressed==0||compressed>MAX_BLOB+1024*1024||raw==0||raw>MAX_BLOB||offset>length||compressed>length-offset) return failure(_error="Invalid visual block bounds");
        Dictionary e;e["offset"]=offset;e["compressed"]=compressed;e["raw"]=raw;e["checksum"]=index.slice(at+56,at+88);pending[hash]=e;next+=compressed;
    }
    if(next!=length) return failure(_error="Unexpected package trailing data");
    Ref<JSON> json;json.instantiate();if(json->parse(meta.get_string_from_utf8())!=OK||json->get_data().get_type()!=Variant::DICTIONARY) return failure(_error="Invalid metadata encoding");
    Dictionary d=json->get_data();if(!valid_definitions(d,pending)) return failure(_error="Invalid package definitions");
    _path=path;_index=pending;_bytes+=HEADER+meta_size+count*ENTRY;return d;
}
PackedByteArray AstraeonContentPack::read_blob(String hash) {
    std::lock_guard<std::mutex> guard(_read_mutex);
    if(!_index.has(hash)){_error="Unknown visual hash";return {};}
    Dictionary e=_index[hash];Ref<FileAccess> f=FileAccess::open(_path,FileAccess::READ);
    if(f.is_null()){_error="Cannot reopen visual package";return {};}
    f->seek(int64_t(e["offset"]));PackedByteArray compressed=f->get_buffer(int64_t(e["compressed"]));
    _reads++;_bytes+=compressed.size();
    if(compressed.size()!=int64_t(e["compressed"])||digest(compressed)!=PackedByteArray(e["checksum"])){_error="Visual payload checksum mismatch";return {};}
    PackedByteArray raw=compressed.decompress(int64_t(e["raw"]),FileAccess::COMPRESSION_ZSTD);
    if(raw.size()!=int64_t(e["raw"])||digest(raw).hex_encode()!=hash){_error="Visual decompression/hash mismatch";return {};}
    _decompressed+=raw.size();return raw;
}
String AstraeonContentPack::get_error() const {std::lock_guard<std::mutex> guard(_read_mutex);return _error;}
Dictionary AstraeonContentPack::blob_info(String hash) const {return _index.get(hash,Dictionary());}
Dictionary AstraeonContentPack::get_metrics() const { std::lock_guard<std::mutex> guard(_read_mutex);Dictionary d;d["blob_reads"]=_reads;d["read_bytes"]=_bytes;d["decompressed_bytes"]=_decompressed;return d; }
int AstraeonContentPack::rotation_index(Basis b) const {
    for(int i=0;i<24;++i) {
        auto o=math::get_ortho_basis_from_index(i);
        if(b.get_column(0).is_equal_approx(Vector3(o.x.x,o.x.y,o.x.z)) && b.get_column(1).is_equal_approx(Vector3(o.y.x,o.y.y,o.y.z)) && b.get_column(2).is_equal_approx(Vector3(o.z.x,o.z.y,o.z.z))) return i;
    }
    return -1;
}
void AstraeonContentPack::_bind_methods() {
    ClassDB::bind_method(D_METHOD("rotation_index","basis"),&AstraeonContentPack::rotation_index);
    ClassDB::bind_method(D_METHOD("compile_visual","faces","resolution"),&AstraeonContentPack::compile_visual);
    ClassDB::bind_method(D_METHOD("write_pack","path","definitions","blobs"),&AstraeonContentPack::write_pack);
    ClassDB::bind_method(D_METHOD("open_pack","path"),&AstraeonContentPack::open_pack);
    ClassDB::bind_method(D_METHOD("read_blob","hash"),&AstraeonContentPack::read_blob);
    ClassDB::bind_method(D_METHOD("get_error"),&AstraeonContentPack::get_error);
    ClassDB::bind_method(D_METHOD("get_metrics"),&AstraeonContentPack::get_metrics);
}
}
