#include "astraeon_light_field.h"
#include "util/godot/core/class_db.h"
#include <vector>
#include <deque>
#include <algorithm>
namespace zylann::voxel {
Dictionary AstraeonLightField::solve(Ref<godot::VoxelBuffer> snapshot, PackedByteArray opacity, PackedByteArray emission, PackedByteArray sources, PackedByteArray known, int section_size, Vector3i origin) {
    Dictionary result;
    ERR_FAIL_COND_V(snapshot.is_null() || section_size <= 0, result);
    const VoxelBuffer &buffer = snapshot->get_buffer();
    const Vector3i size = buffer.get_size();
    const int sx=size.x, sy=size.y, sz=size.z, count=sx*sy*sz;
    ERR_FAIL_COND_V(count<=0 || sx%section_size || sy%section_size || sz%section_size, result);
    const int bx=sx/section_size, by=sy/section_size;
    ERR_FAIL_COND_V(known.size()!=bx*by*(sz/section_size), result);
    std::vector<uint8_t> op(count,15), sky(count,0), block(count,0);
    std::deque<int> sq,bq;
    Array emitters;
    Ref<Image> height = Image::create_empty(sx,sz,false,Image::FORMAT_RF);
    for(int z=0;z<sz;++z) for(int x=0;x<sx;++x) {
        int sunlight=15; float roof=float(origin.y-1); bool roof_set=false;
        for(int y=sy-1;y>=0;--y) {
            const int i=x+sx*(y+sy*z);
            const bool loaded=known[(x/section_size)+bx*((y/section_size)+by*(z/section_size))]!=0;
            const uint64_t id=buffer.get_voxel(Vector3i(x,y,z),VoxelBuffer::CHANNEL_TYPE);
            op[i]=loaded && id<uint64_t(opacity.size()) ? opacity[id] : 15;
            if(!roof_set && op[i]>0) {roof=float(origin.y+y+1);roof_set=true;}
            sunlight=std::max(0,sunlight-int(op[i]));
            sky[i]=uint8_t(sunlight);
            if(sunlight) sq.push_back(i);
            if(loaded && id<uint64_t(emission.size()) && emission[id]>0) {
                block[i]=emission[id];bq.push_back(i);
            }
            if(loaded && id<uint64_t(sources.size()) && sources[id]>0) {
                Dictionary light;light["position"]=origin+Vector3i(x,y,z);light["state"]=int(id);emitters.append(light);
            }
        }
        height->set_pixel(x,z,Color(roof,0,0,1));
    }
    auto spread=[&](std::vector<uint8_t> &values,std::deque<int> &queue) {
        const int strides[6]={-1,1,-sx,sx,-sx*sy,sx*sy};
        while(!queue.empty()) {
            const int i=queue.front();queue.pop_front();
            const int x=i%sx,y=(i/sx)%sy,z=i/(sx*sy);
            const bool valid[6]={x>0,x+1<sx,y>0,y+1<sy,z>0,z+1<sz};
            for(int d=0;d<6;++d) if(valid[d]) {
                const int n=i+strides[d];
                const int value=int(values[i])-std::max(1,int(op[n]));
                if(value>int(values[n])) {values[n]=uint8_t(value);queue.push_back(n);}
            }
        }
    };
    spread(sky,sq);spread(block,bq);
    TypedArray<Image> images;
    for(int z=0;z<sz;++z) {
        PackedByteArray pixels;pixels.resize(sx*sy*4);uint8_t *dst=pixels.ptrw();
        for(int y=0;y<sy;++y) for(int x=0;x<sx;++x) {
            const int i=x+sx*(y+sy*z),j=4*(x+sx*y);
            dst[j]=sky[i]*17;dst[j+1]=block[i]*17;dst[j+2]=op[i]<15?255:0;dst[j+3]=255;
        }
        images.append(Image::create_from_data(sx,sy,false,Image::FORMAT_RGBA8,pixels));
    }
    result["images"]=images;result["height"]=height;result["emitters"]=emitters;return result;
}
void AstraeonLightField::_bind_methods() {
    ClassDB::bind_method(D_METHOD("solve","snapshot","opacity","emission","sources","known_sections","section_size","origin"), &AstraeonLightField::solve);
}
}
