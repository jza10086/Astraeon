#include "../../../game/shading/native/cache/section_light_cache.h"
#include <iostream>
#include <stdexcept>
#include <random>
using namespace astraeon;
static int checks=0;
void check(bool value,const char *message){++checks;if(!value)throw std::runtime_error(message);}
void settle(SectionLightCache &c){int n=0;while(c.step(4096,1000000)){if(++n>20000)throw std::runtime_error("no convergence");}}
std::unique_ptr<LightSection> air(uint64_t revision){auto s=std::make_unique<LightSection>();s->revision=revision;return s;}
void compare_reference(SectionLightCache &cache) {
 const int sx=32,sy=32,sz=16,count=sx*sy*sz;
 std::vector<uint8_t> op(count),seed(count),sky(count),block(count);
 auto at=[](int x,int y,int z){return x+32*(y+32*z);};
 for(int z=0;z<sz;++z)for(int x=0;x<sx;++x){int sunlight=15;
  for(int y=sy-1;y>=0;--y){auto section=cache.find({x/16-1,y/16,z/16});int i=at(x,y,z),j=SectionLightCache::index(x%16,y%16,z%16);
   op[i]=section->opacity.get(j);seed[i]=section->emission.get(j);sunlight=std::max(0,sunlight-int(op[i]));sky[i]=sunlight;block[i]=seed[i];}}
 auto flood=[&](std::vector<uint8_t>& values){std::deque<int> queue;for(int i=0;i<count;++i)if(values[i])queue.push_back(i);
  while(!queue.empty()){int i=queue.front();queue.pop_front();int x=i%sx,y=i/sx%sy,z=i/(sx*sy);
   for(auto d:SectionLightCache::DIRECTIONS){int nx=x+d.x,ny=y+d.y,nz=z+d.z;if(nx<0||ny<0||nz<0||nx>=sx||ny>=sy||nz>=sz)continue;
    int j=at(nx,ny,nz),v=int(values[i])-std::max(1,int(op[j]));if(v>values[j]){values[j]=v;queue.push_back(j);}}}};
 flood(sky);flood(block);
 for(int z=0;z<sz;++z)for(int y=0;y<sy;++y)for(int x=0;x<sx;++x){auto section=cache.find({x/16-1,y/16,0});int i=at(x,y,z),j=SectionLightCache::index(x%16,y%16,z);
  check(section->sky.get(j)==sky[i],"incremental sky differs from independent flood solver");check(section->block.get(j)==block[i],"incremental emission differs from independent flood solver");}
}
void randomized_edits() {
 SectionLightCache c;c.min_section_y=0;c.max_section_y=2;std::mt19937 rng(916);
 for(int x=-1;x<=0;++x)for(int y=1;y>=0;--y){auto section=air(1);for(int i=0;i<4096;++i){int r=rng()%100;section->opacity.set(i,r<18?15:(r<23?1:0));if(rng()%2048==0)section->emission.set(i,15);}c.replace({x,y,0},std::move(section));}
 settle(c);compare_reference(c);
 for(int batch=0;batch<4;++batch){
  // Exercise an edit while a previous incremental work slice is still in progress.
  for(int n=0;n<128;++n){SectionKey p{int(rng()%2)-1,int(rng()%2),0};auto old=c.find(p);auto next=std::make_unique<LightSection>(*old);next->revision=2+batch*128+n;int i=rng()%4096;next->opacity.set(i,rng()%2?15:0);next->emission.set(i,rng()%8==0?15:0);c.replace(p,std::move(next));c.step(64,1000000);}
  settle(c);compare_reference(c);
 }
}
void full_height_shaft() {
 SectionLightCache c;
 auto shaft=[](uint64_t revision){auto s=air(revision);s->opacity.fill(15);for(int y=0;y<16;++y)s->opacity.set(SectionLightCache::index(8,y,8),0);return s;};
 // Load bottom-first to exercise unknown above and cross-region vertical dependencies.
 for(int sy=-4;sy<12;++sy){c.replace({-5,sy,-1},shaft(sy+5));c.step(64,1000000);}
 settle(c);
 for(int sy=-4;sy<12;++sy)for(int y=0;y<16;++y)check(c.find({-5,sy,-1})->sky.get(SectionLightCache::index(8,y,8))==15,"full-height direct shaft");
 auto closed=shaft(100);closed->opacity.set(SectionLightCache::index(8,8,8),15);c.replace({-5,4,-1},std::move(closed));settle(c);
 for(int sy=-4;sy<4;++sy)check(c.find({-5,sy,-1})->sky.get(SectionLightCache::index(8,0,8))==0,"roof removal must traverse more than one neighbor");
 c.replace({-5,4,-1},shaft(101));settle(c);
 check(c.find({-5,-4,-1})->sky.get(SectionLightCache::index(8,0,8))==15,"reopened full shaft reaches world bottom");
 c.erase({-5,8,-1});settle(c);
 check(c.find({-5,-4,-1})->sky.get(SectionLightCache::index(8,0,8))==0,"unloaded middle section blocks sky");
 c.replace({-5,8,-1},shaft(102));settle(c);
 check(c.find({-5,-4,-1})->sky.get(SectionLightCache::index(8,0,8))==15,"reloaded middle section restores sky");
}
int main(){try {
 full_height_shaft();
 randomized_edits();
 SectionLightCache c;c.min_section_y=0;c.max_section_y=2;
 c.replace({-1,0,0},air(1));settle(c);
 check(c.find({-1,0,0})->sky.get(0)==0,"unknown above must occlude");
 c.replace({-1,1,0},air(2));settle(c);
 for(auto &p:c.sections)for(int i=0;i<4096;++i)check(p.second->sky.get(i)==15,"skylight shaft continuity");
 auto lamp=air(3);lamp->emission.set(SectionLightCache::index(15,8,8),15);c.replace({-1,0,0},std::move(lamp));
 c.replace({0,0,0},air(4));c.replace({0,1,0},air(5));settle(c);
 check(c.find({0,0,0})->block.get(SectionLightCache::index(0,8,8))==14,"negative section boundary propagation");
 auto other=air(6);other->emission.set(SectionLightCache::index(4,8,8),15);c.replace({0,0,0},std::move(other));settle(c);
 c.replace({-1,0,0},air(7));settle(c);
 check(c.find({0,0,0})->block.get(SectionLightCache::index(0,8,8))==11,"overlap removal must restore surviving source");
 c.replace({0,0,0},air(8));settle(c);
 for(auto &p:c.sections)for(int i=0;i<4096;++i)check(p.second->block.get(i)==0,"removed source retained phantom light");
 auto roof=air(9);roof->opacity.fill(15);c.replace({-1,1,0},std::move(roof));c.erase({0,1,0});c.erase({0,0,0});settle(c);
 for(int i=0;i<4096;++i)check(c.find({-1,0,0})->sky.get(i)==0,"sky removal must reach full column");
 auto hole=air(10);hole->opacity.fill(15);hole->opacity.set(SectionLightCache::index(8,15,8),0);c.replace({-1,1,0},std::move(hole));settle(c);
 check(c.find({-1,1,0})->sky.get(SectionLightCache::index(8,15,8))==15,"top opening");
 check(c.find({-1,0,0})->sky.get(SectionLightCache::index(8,15,8))==0,"opaque shaft still blocks");
 auto shaft=air(11);shaft->opacity.fill(15);for(int y=0;y<16;++y)shaft->opacity.set(SectionLightCache::index(8,y,8),0);c.replace({-1,1,0},std::move(shaft));settle(c);
 check(c.find({-1,0,0})->sky.get(SectionLightCache::index(8,0,8))==15,"direct light through shaft reaches lower section bottom");
 std::cout<<"SECTION_CACHE PASS checks="<<checks<<" visits="<<c.visits<<" bytes="<<c.bytes()<<"\n";
 }catch(const std::exception &e){std::cerr<<e.what()<<"\n";return 1;}}
