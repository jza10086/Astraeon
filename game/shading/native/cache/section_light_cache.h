#pragma once
#include <array>
#include <vector>
#include <deque>
#include <unordered_map>
#include <unordered_set>
#include <memory>
#include <algorithm>
#include <cstdint>
#include <chrono>

namespace astraeon {
struct SectionKey {
    int x=0,y=0,z=0;
    bool operator==(const SectionKey &b) const { return x==b.x && y==b.y && z==b.z; }
    SectionKey operator+(const SectionKey &b) const { return {x+b.x,y+b.y,z+b.z}; }
};
struct SectionHash {
    size_t operator()(const SectionKey &p) const {
        return uint64_t(uint32_t(p.x))*0x9e3779b185ebca87ull ^ uint64_t(uint32_t(p.y))*0xc2b2ae3d27d4eb4full ^ uint64_t(uint32_t(p.z))*0x165667b19e3779f9ull;
    }
};
// Uniform arrays avoid allocating 20 KiB for every empty section above terrain.
struct LightBytes {
    uint8_t uniform=0;
    std::vector<uint8_t> values;
    uint8_t get(int i) const { return values.empty()?uniform:values[i]; }
    bool set(int i, uint8_t v) {
        if(get(i)==v) return false;
        if(values.empty()) values.assign(4096,uniform);
        values[i]=v;return true;
    }
    void fill(uint8_t v) { uniform=v;std::vector<uint8_t>().swap(values); }
    void compact() {
        if(values.empty()) return;
        const uint8_t v=values[0];
        if(std::all_of(values.begin(),values.end(),[v](uint8_t a){return a==v;})) fill(v);
    }
};
struct LightSection {
    uint64_t revision=0, completed_revision=0, light_revision=0;
    std::array<uint64_t,6> boundary_version{};
    LightBytes opacity, emission, sky, block, direct;
    bool queued=false;
    struct Source { uint16_t index; uint32_t state; };
    std::vector<Source> sources;
    uint64_t bytes() const {
        return sizeof(LightSection)+opacity.values.capacity()+emission.values.capacity()+sky.values.capacity()+block.values.capacity()+direct.values.capacity()+sources.capacity()*sizeof(Source);
    }
};
class SectionLightCache {
public:
    using Map=std::unordered_map<SectionKey,std::unique_ptr<LightSection>,SectionHash>;
    static constexpr SectionKey DIRECTIONS[6]={{-1,0,0},{1,0,0},{0,-1,0},{0,1,0},{0,0,-1},{0,0,1}};
    Map sections;
    std::unordered_set<SectionKey,SectionHash> changed;
    uint64_t visits=0, passes=0, solved=0;
    int min_section_y=-4,max_section_y=12;
    static int index(int x,int y,int z) {return x+16*(y+16*z);}
    LightSection *find(SectionKey key) const {auto it=sections.find(key);return it==sections.end()?nullptr:it->second.get();}
    void dirty(SectionKey key, bool removal=false) {
        LightSection *s=find(key); if(!s || s->queued)return;
        s->queued=true;(removal?decrease:increase).push_back(key);
    }
    void replace(SectionKey key, std::unique_ptr<LightSection> input) {
        LightSection *old=find(key);
        if(old) {
            input->sky=std::move(old->sky); input->block=std::move(old->block); input->direct=std::move(old->direct);
            input->boundary_version=old->boundary_version;input->light_revision=old->light_revision;
            // Existing queued keys keep their position, including an interrupted work slice.
            input->queued=old->queued;
        }
        sections[key]=std::move(input);
        if(active && current==key){cursor=0;did_change=false;direct_changed=false;boundary_changed.fill(false);}
        dirty(key,true); changed.insert(key);
        for(auto d:DIRECTIONS) dirty(key+d,true);
    }
    void erase(SectionKey key) {
        sections.erase(key);changed.erase(key);
        for(auto d:DIRECTIONS) dirty(key+d,true);
    }
    bool pending() const { return active || !decrease.empty() || !increase.empty(); }
    size_t queue_size() const {return decrease.size()+increase.size()+(active?1:0);}
    // A single worker owns this solver. Main thread only sees immutable finished pages.
    bool step(unsigned max_visits=4096, uint64_t max_usec=2000) {
        const auto start=std::chrono::steady_clock::now(); unsigned count=0;
        while(count<max_visits) {
            if(!active) {
                if(decrease.empty() && increase.empty()) return false;
                auto &queue=decrease.empty()?increase:decrease;
                current=queue.front();queue.pop_front();
                if(!find(current))continue;
                active=true;cursor=0;did_change=false;boundary_changed.fill(false);direct_changed=false;
            }
            LightSection *s=find(current);
            if(!s){active=false;continue;}
            // Exact constant-value cases: solid sections cannot receive light, and
            // open full-sky sections without nearby block light are already solved.
            // This avoids scanning 4096 identical cells above/below the terrain.
            if(cursor==0 && s->opacity.values.empty() && s->emission.values.empty()) {
                bool uniform=s->opacity.uniform==15;
                uint8_t target_sky=0,target_block=s->emission.uniform;
                if(s->opacity.uniform==0 && target_block==0) {
                    const auto above=find(current+SectionKey{0,1,0});
                    uniform=current.y+1>=max_section_y || (above && above->direct.values.empty() && above->direct.uniform==15);
                    for(auto direction:DIRECTIONS) {
                        const auto neighbor=find(current+direction);
                        if(neighbor && (!neighbor->block.values.empty() || neighbor->block.uniform!=0))uniform=false;
                    }
                    target_sky=15;
                }
                if(uniform) {
                    const bool changed_sky=!s->sky.values.empty() || s->sky.uniform!=target_sky;
                    const bool changed_block=!s->block.values.empty() || s->block.uniform!=target_block;
                    const bool changed_direct=!s->direct.values.empty() || s->direct.uniform!=target_sky;
                    s->sky.fill(target_sky);s->block.fill(target_block);s->direct.fill(target_sky);
                    s->queued=false;active=false;++passes;++visits;++count;
                    if(changed_sky || changed_block) {
                        ++s->light_revision;changed.insert(current);
                        for(int d=0;d<6;++d){++s->boundary_version[d];dirty(current+DIRECTIONS[d]);}
                    }
                    if(changed_direct)dirty(current+SectionKey{0,-1,0},true);
                    s->completed_revision=s->revision;++solved;
                    if(uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count())>=max_usec)break;
                    continue;
                }
            }
            // Top to bottom, with each x/z column contiguous. Direct skylight is independent of diffuse light.
            const int y=15-(cursor%16), x=(cursor/16)%16,z=cursor/256;
            const int i=index(x,y,z);const int attenuation=s->opacity.get(i);
            LightSection *above=y==15?find(current+SectionKey{0,1,0}):s;
            const int incoming=y<15?s->direct.get(index(x,y+1,z)):
                (current.y+1>=max_section_y?15:(above?above->direct.get(index(x,0,z)):0));
            const uint8_t direct=uint8_t(std::max(0,incoming-attenuation));
            if(s->direct.set(i,direct) && y==0)direct_changed=true;
            int sky=direct,block=s->emission.get(i);
            if(attenuation<15) {
                for(int d=0;d<6;++d) {
                    const SectionKey delta=DIRECTIONS[d];
                    const int nx=x+delta.x,ny=y+delta.y,nz=z+delta.z;
                    LightSection *n=s;
                    if(nx<0||nx>15||ny<0||ny>15||nz<0||nz>15)n=find(current+delta);
                    if(!n)continue;
                    const int j=index(nx&15,ny&15,nz&15);
                    sky=std::max(sky,int(n->sky.get(j))-std::max(1,attenuation));
                    block=std::max(block,int(n->block.get(j))-std::max(1,attenuation));
                }
            }
            const bool a=s->sky.set(i,uint8_t(sky)),b=s->block.set(i,uint8_t(block));
            if(a||b) {
                did_change=true;
                if(x==0)boundary_changed[0]=true;if(x==15)boundary_changed[1]=true;
                if(y==0)boundary_changed[2]=true;if(y==15)boundary_changed[3]=true;
                if(z==0)boundary_changed[4]=true;if(z==15)boundary_changed[5]=true;
            }
            ++cursor;++count;++visits;
            if(cursor==4096) {
                s->queued=false;active=false;++passes;
                if(did_change) {++s->light_revision;changed.insert(current);dirty(current);}
                for(int d=0;d<6;++d)if(boundary_changed[d]){++s->boundary_version[d];dirty(current+DIRECTIONS[d]);}
                if(direct_changed)dirty(current+SectionKey{0,-1,0},true);
                s->sky.compact();s->block.compact();s->direct.compact();
                if(!s->queued){s->completed_revision=s->revision;++solved;}
            }
            if((count&63)==0 && uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count())>=max_usec)break;
        }
        return pending();
    }
    std::array<uint8_t,16384> pack(const LightSection &s) const {
        std::array<uint8_t,16384> bytes{};
        for(int i=0;i<4096;++i) {bytes[i*4]=s.sky.get(i)*17;bytes[i*4+1]=s.block.get(i)*17;bytes[i*4+2]=s.opacity.get(i)<15?255:0;bytes[i*4+3]=255;}
        return bytes;
    }
    uint64_t bytes() const {uint64_t n=0;for(auto &p:sections)n+=sizeof(SectionKey)+p.second->bytes();return n+(decrease.size()+increase.size())*sizeof(SectionKey);}
private:
    std::deque<SectionKey> decrease,increase;
    SectionKey current;
    bool active=false,did_change=false,direct_changed=false;
    int cursor=0;
    std::array<bool,6> boundary_changed{};
};
}
