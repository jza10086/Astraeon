#include "astraeon_dropped_items.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>
namespace zylann::voxel {
using namespace ::godot;
namespace {
constexpr double R=0.14;
bool integer(Variant v) { return (v.get_type()==Variant::INT||v.get_type()==Variant::FLOAT)&&std::isfinite(double(v))&&std::floor(double(v))==double(v); }
Array vec(Vector3 v) { Array a; a.append(v.x);a.append(v.y);a.append(v.z);return a; }
bool read_vec(Variant v,Vector3 &p) { if(v.get_type()!=Variant::ARRAY)return false;Array a=v;if(a.size()!=3)return false;for(int i=0;i<3;++i){if(a[i].get_type()!=Variant::INT&&a[i].get_type()!=Variant::FLOAT)return false;if(!std::isfinite(double(a[i])))return false;p[i]=double(a[i]);}return true; }
}
AstraeonDroppedItems::Chunk AstraeonDroppedItems::chunk(Vector3 p){return {int(std::floor(p.x/16.0)),int(std::floor(p.z/16.0))};}
bool AstraeonDroppedItems::valid_position(Vector3 p){return p.is_finite()&&std::abs(p.x)<1048575&&std::abs(p.z)<1048575&&p.y>=-63.8&&p.y<191.8;}
bool AstraeonDroppedItems::fail(const String &s){_error=s;return false;}
bool AstraeonDroppedItems::configure(PackedStringArray keys,PackedInt32Array limits,PackedByteArray solid){
    if(!_keys.is_empty()||keys.size()!=limits.size()||keys.is_empty()||solid.is_empty())return fail("Invalid dropped-item configuration");
    for(int i=0;i<keys.size();++i)if(keys[i].is_empty()||keys.find(keys[i])!=i||limits[i]<1)return fail("Invalid item registry");
    _keys=keys;_limits=limits;_solid=solid;return true;
}
int64_t AstraeonDroppedItems::spawn(String key,int count,Vector3 p,Vector3 v,double delay){
    int item=_keys.find(key);
    if(!_error.is_empty())return 0;
    if(item<0||count<1||count>_limits[item]||!valid_position(p)||!v.is_finite()||v.length()>32||!std::isfinite(delay)||delay<0||delay>10||_records.size()>=65536||_next_id>=9007199254740991LL){fail("Dropped-item generation failed: invalid record or capacity exhausted");return 0;}
    Record r{_next_id++,item,count,p,v,delay};_records[r.id]=r;_chunks[chunk(p)].insert(r.id);return r.id;
}
bool AstraeonDroppedItems::take(int64_t id,int count){
    auto it=_records.find(id);if(!_error.is_empty())return false;
    if(it==_records.end()||count<1||count>it->second.count)return fail("Invalid dropped-item removal");
    it->second.count-=count;if(it->second.count==0){Chunk c=chunk(it->second.position);_chunks[c].erase(id);if(_chunks[c].empty())_chunks.erase(c);_records.erase(it);}return true;
}
Dictionary AstraeonDroppedItems::view(const Record &r) const{Dictionary d;d["id"]=r.id;d["item"]=_keys[r.item];d["count"]=r.count;d["position"]=r.position;d["velocity"]=r.velocity;d["delay"]=r.delay;d["sleeping"]=r.sleeping;return d;}
Array AstraeonDroppedItems::nearby(Vector3 center,double radius,bool pickable) const{
    Array out;if(!center.is_finite()||!std::isfinite(radius)||radius<0||radius>64)return out;
    Chunk lo=chunk(center-Vector3(radius,0,radius)),hi=chunk(center+Vector3(radius,0,radius));
    for(int x=lo.first;x<=hi.first;++x)for(int z=lo.second;z<=hi.second;++z){auto bucket=_chunks.find({x,z});if(bucket==_chunks.end())continue;
        for(int64_t id:bucket->second){const Record&r=_records.at(id);if((!pickable||r.delay<=0)&&r.position.distance_squared_to(center)<=radius*radius)out.append(view(r));}}
    return out;
}
bool AstraeonDroppedItems::collides(Vector3 p,const Ref<VoxelTool>&tool)const{
    int x0=int(std::floor(p.x-R)),x1=int(std::floor(p.x+R)),y0=int(std::floor(p.y-R)),y1=int(std::floor(p.y+R)),z0=int(std::floor(p.z-R)),z1=int(std::floor(p.z+R));
    for(int x=x0;x<=x1;++x)for(int y=y0;y<=y1;++y)for(int z=z0;z<=z1;++z){uint64_t v=tool->get_voxel(::godot::Vector3i(x,y,z));if(v<uint64_t(_solid.size())&&_solid[int(v)]!=0)return true;}return false;
}
void AstraeonDroppedItems::step(double dt,Vector3 center,Ref<VoxelTool> terrain){
    if(!_error.is_empty()||terrain.is_null()||!std::isfinite(dt)||dt<=0)return;
    dt=std::min(dt,0.1);Array active=nearby(center,32,false);
    for(int i=0;i<active.size();++i){Dictionary d=active[i];Record&r=_records.at(int64_t(d["id"]));Vector3 p=r.position;
        Box3i box(int(std::floor(p.x))-2,int(std::floor(p.y))-2,int(std::floor(p.z))-2,5,5,5);
        if(!terrain->is_area_editable(box))continue;
        r.delay=std::max(0.0,r.delay-dt);
        if(r.sleeping&&collides(p-Vector3(0,0.035,0),terrain))continue;
        r.sleeping=false;
        int steps=std::max(1,int(std::ceil((r.velocity.length()+24*dt)*dt/0.08)));double h=dt/steps;
        bool ground=false;
        for(int n=0;n<steps;++n){r.velocity.y=std::max(-20.0,double(r.velocity.y)-24*h);
            for(int axis: {0,2,1}){Vector3 next=r.position;next[axis]+=r.velocity[axis]*h;
                if(!valid_position(next)||collides(next,terrain)){if(axis==1&&r.velocity.y<0)ground=true;r.velocity[axis]=0;}else r.position=next;}
            if(ground){r.velocity.x*=std::max(0.0,1-12*h);r.velocity.z*=std::max(0.0,1-12*h);}}
        if(ground&&r.velocity.length_squared()<0.0025){r.velocity=Vector3();r.sleeping=true;}
        Chunk from=chunk(p),to=chunk(r.position);if(from!=to){_chunks[from].erase(r.id);if(_chunks[from].empty())_chunks.erase(from);_chunks[to].insert(r.id);}
    }
}
Dictionary AstraeonDroppedItems::snapshot() const{
    Dictionary out,chunks;out["next_id"]=_next_id;
    for(const auto &bucket:_chunks){Array rows;for(int64_t id:bucket.second){const Record&r=_records.at(id);Dictionary d;d["id"]=r.id;d["item"]=_keys[r.item];d["count"]=r.count;d["position"]=vec(r.position);d["velocity"]=vec(r.velocity);d["delay"]=r.delay;rows.append(d);}chunks[String::num_int64(bucket.first.first)+","+String::num_int64(bucket.first.second)]=rows;}
    out["chunks"]=chunks;return out;
}
bool AstraeonDroppedItems::restore(Dictionary data){
    if(!_error.is_empty())return false;
    if(!_records.empty()||_keys.is_empty()||!integer(data.get("next_id",Variant()))||double(data["next_id"])<1||double(data["next_id"])>9007199254740991LL||data.get("chunks",Variant()).get_type()!=Variant::DICTIONARY)return fail("Invalid dropped-item snapshot");
    Dictionary buckets=data["chunks"];Array names=buckets.keys();std::map<int64_t,Record> records;std::map<Chunk,std::set<int64_t>> chunks;
    for(int b=0;b<names.size();++b){if(buckets[names[b]].get_type()!=Variant::ARRAY)return fail("Invalid dropped-item chunk");Array rows=buckets[names[b]];
        for(int i=0;i<rows.size();++i){if(rows[i].get_type()!=Variant::DICTIONARY)return fail("Invalid dropped-item row");Dictionary d=rows[i];Record r;Vector3 p,v;
            int item=_keys.find(String(d.get("item","")));if(!integer(d.get("id",Variant()))||!integer(d.get("count",Variant()))||item<0||!read_vec(d.get("position",Variant()),p)||!read_vec(d.get("velocity",Variant()),v)||!valid_position(p)||v.length()>32)return fail("Unknown or invalid dropped item");
            Variant delay_value=d.get("delay",Variant());
            if(double(d["id"])<1||double(d["id"])>=double(data["next_id"])||double(d["count"])<1||double(d["count"])>_limits[item]||(delay_value.get_type()!=Variant::INT&&delay_value.get_type()!=Variant::FLOAT))return fail("Invalid dropped-item numeric data");
            double delay=delay_value;r={int64_t(d["id"]),item,int(d["count"]),p,v,delay};Chunk c=chunk(p);
            if(r.id<1||r.id>=int64_t(data["next_id"])||records.count(r.id)||r.count<1||r.count>_limits[item]||!std::isfinite(delay)||delay<0||delay>10||String(names[b])!=String::num_int64(c.first)+","+String::num_int64(c.second)||records.size()>=65536)return fail("Invalid dropped-item identity/count/chunk");
            records[r.id]=r;chunks[c].insert(r.id);}}
    _records=std::move(records);_chunks=std::move(chunks);_next_id=data["next_id"];return true;
}
void AstraeonDroppedItems::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","keys","limits","solid"),&AstraeonDroppedItems::configure);
    ClassDB::bind_method(D_METHOD("spawn","item","count","position","velocity","delay"),&AstraeonDroppedItems::spawn);
    ClassDB::bind_method(D_METHOD("take","id","count"),&AstraeonDroppedItems::take);
    ClassDB::bind_method(D_METHOD("step","delta","center","terrain"),&AstraeonDroppedItems::step);
    ClassDB::bind_method(D_METHOD("nearby","center","radius","pickable"),&AstraeonDroppedItems::nearby);
    ClassDB::bind_method(D_METHOD("snapshot"),&AstraeonDroppedItems::snapshot);
    ClassDB::bind_method(D_METHOD("restore","snapshot"),&AstraeonDroppedItems::restore);
    ClassDB::bind_method(D_METHOD("get_error"),&AstraeonDroppedItems::get_error);
    ClassDB::bind_method(D_METHOD("get_count"),&AstraeonDroppedItems::get_count);
}
}

