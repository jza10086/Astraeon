@tool
extends CompositorEffect
## GPU-only light-shaft integration. Main thread publishes immutable parameters.
## Reference: MakeUp Ultra Fast volumetric_light/composite algorithms; independently
## implemented for Godot reverse-Z and a separate scene occlusion capture.
const CODE: String = """#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform restrict writeonly image2D output_image;
layout(set=0,binding=1) uniform sampler2D scene_color;
layout(set=0,binding=2) uniform sampler2D scene_depth;
layout(set=0,binding=3) uniform sampler2D shafts;
layout(set=0,binding=4) uniform sampler2D shadow_depth;
layout(set=0,binding=5) uniform sampler2D cloud_mask;
layout(set=0,binding=7) uniform sampler2D history_image;
layout(std430,set=0,binding=6) readonly buffer Settings { vec4 v[]; } p;
layout(push_constant,std430) uniform Pass { vec4 control; } pass;
mat4 matrix_at(int i) { return mat4(p.v[i],p.v[i+1],p.v[i+2],p.v[i+3]); }
vec3 view_position(vec2 uv,float depth) {
    // Camera3D projection is OpenGL convention; scene depth is reversed [0,1].
    vec4 q=matrix_at(0)*vec4(uv.x*2.0-1.0,1.0-uv.y*2.0,1.0-2.0*depth,1.0);
    return q.xyz/max(q.w,0.000001);
}
float eye_depth(vec2 uv) { return length(view_position(uv,textureLod(scene_depth,uv,0).r)); }
float hash(vec2 p) { return fract(52.9829189*fract(dot(p,vec2(.06711056,.00583715)))); }
float cloud_visibility(vec3 pos) {
    if(p.v[23].x<=0.0 || p.v[16].y<0.025 || pos.y>=p.v[22].w)return 1.0;
    vec2 q=(pos.xz+p.v[16].xz*((p.v[22].w-pos.y)/p.v[16].y)-p.v[22].xy)/p.v[22].z;
    return 1.0-textureLod(cloud_mask,fract(q),0).r*p.v[23].x;
}
float visibility(vec3 pos) {
    vec3 q=(matrix_at(8)*vec4(pos,1)).xyz;
    vec2 uv=vec2(q.x,-q.y)/p.v[21].x+0.5;
    float edge=min(min(uv.x,uv.y),min(1.0-uv.x,1.0-uv.y));
    if(edge<=0.0 || -q.z<0.0 || -q.z>p.v[21].y)return 0.0;
    float captured=textureLod(shadow_depth,uv,0).r*p.v[21].y;
    return step(-q.z-p.v[21].z,captured)*smoothstep(0.0,0.04,edge)*cloud_visibility(pos);
}
void main() {
    ivec2 pixel=ivec2(gl_GlobalInvocationID.xy),size=imageSize(output_image);
    if(any(greaterThanEqual(pixel,size)))return;
    vec2 uv=(vec2(pixel)+0.5)/vec2(size);
    int stage=int(pass.control.x);
    vec4 color=textureLod(scene_color,uv,0);
    if(stage==0) { imageStore(output_image,pixel,color); return; }
    if(stage==1) {
        float d=textureLod(scene_depth,uv,0).r;
        float linear=p.v[21].y-(p.v[21].y-0.01)*d;
        imageStore(output_image,pixel,vec4(vec3(linear/p.v[21].y),1)); return;
    }
    if(stage==2) {
        vec3 view=view_position(uv,textureLod(scene_depth,uv,0).r);
        vec3 ray=normalize(mat3(matrix_at(4))*normalize(view));
        float alignment=dot(ray,p.v[16].xyz);
        float jitter=hash(vec2(pixel)+vec2(p.v[23].w*5.588));
        float sum=0.0,weight=0.0;
        int count=int(p.v[18].y);
        if(p.v[18].x<2.0) {
            vec2 step_uv=(p.v[17].xy-uv)*p.v[20].x/float(count);
            vec2 q=uv+step_uv*jitter;
            float w=1.0;
            for(int i=0;i<96;i++) {
                if(i>=count)break;
                if(all(greaterThanEqual(q,vec2(0)))&&all(lessThanEqual(q,vec2(1))))
                    sum+=step(textureLod(scene_depth,q,0).r,0.000001)*w;
                weight+=w; w*=p.v[20].y; q+=step_uv;
            }
            sum/=max(weight,0.001);
            vec3 center=normalize(mat3(matrix_at(4))*normalize(view_position(vec2(.5),0.0)));
            alignment=pow(max(0.0,alignment*max(dot(center,p.v[16].xyz),0.0)),p.v[20].w);
            alignment*=p.v[17].z;
        } else {
            float maximum=min(length(view),p.v[18].z);
            vec3 origin=p.v[7].xyz;
            // Exponentially spaced samples, preserving near-field detail.
            for(int i=0;i<64;i++) {
                if(i>=count)break;
                float t=(float(i)+jitter)/float(count);
                float distance=(exp2(t*log2(1.0+p.v[18].z)*p.v[18].w)-1.0)/
                    (exp2(log2(1.0+p.v[18].z)*p.v[18].w)-1.0)*p.v[18].z;
                if(distance>maximum)break;
                sum+=visibility(origin+ray*distance);
            }
            sum=pow(sum/float(count),p.v[19].w);
            alignment=pow(clamp((alignment+0.5)/1.5,0.0,1.0),p.v[20].w);
        }
        float amount=clamp(sum*alignment*p.v[16].w*p.v[17].w,0.0,0.85);
        imageStore(output_image,pixel,vec4(vec3(amount),min(length(view),65000.0)));return;
    }
    if(stage==4) {
        vec4 current=textureLod(shafts,uv,0);
        vec3 endpoint=(matrix_at(4)*vec4(view_position(uv,textureLod(scene_depth,uv,0).r),1)).xyz;
        vec4 previous=matrix_at(12)*vec4(endpoint,1);
        vec2 prev_uv=vec2(previous.x,-previous.y)/max(previous.w,.0001)*.5+.5;
        bool valid=previous.w>0.0 && p.v[23].z<.5 && all(greaterThan(prev_uv,vec2(0))) && all(lessThan(prev_uv,vec2(1)));
        vec4 history=textureLod(history_image,clamp(prev_uv,vec2(0),vec2(1)),0);
        float expected=min(length(endpoint-p.v[24].xyz),65000.0);
        valid=valid && abs(history.a-expected)<max(p.v[24].w,expected*.025);
        float low=1.0,high=0.0;
        vec2 step_uv=1.0/vec2(textureSize(shafts,0));
        for(int y=-1;y<=1;y++)for(int x=-1;x<=1;x++){
            float v=textureLod(shafts,uv+vec2(x,y)*step_uv,0).r;
            low=min(low,v);high=max(high,v);
        }
        float weight=valid?p.v[23].y:0.0;
        current.rgb=vec3(mix(current.r,clamp(history.r,low,high),weight));
        imageStore(output_image,pixel,current);return;
    }
    // Bilateral four-tap upsample keeps illumination off foreground silhouettes.
    vec2 low_size=vec2(textureSize(shafts,0));
    vec2 cell=uv*low_size-0.5,base=floor(cell),f=fract(cell);
    float depth=min(eye_depth(uv),65000.0),sum=0.0,weight=0.0;
    for(int y=0;y<2;y++)for(int x=0;x<2;x++) {
        vec2 q=(base+vec2(x,y)+0.5)/low_size;
        vec4 sample_value=textureLod(shafts,q,0);
        vec2 bilinear=mix(1.0-f,f,vec2(x,y));
        float w=bilinear.x*bilinear.y*exp(-abs(depth-sample_value.a)/max(p.v[20].z,depth*.02));
        sum+=sample_value.r*w;weight+=w;
    }
    float amount=sum/max(weight,.00001);
    // MakeUp-style artistic light mix, independent from global extinction/fog.
    color.rgb=mix(color.rgb,p.v[19].rgb,amount);
    imageStore(output_image,pixel,color);
}
"""
var capture: bool = false
var _mutex: Mutex = Mutex.new()
var _values: PackedFloat32Array = PackedFloat32Array()
var _shadow: RID
var _cloud: RID
var _scale: float = 0.5
var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _sampler: RID
var _nearest: RID
var _buffer: RID
var _scratch: RID
var _rays: RID
var _history: RID
var _filtered: RID
var _size: Vector2i
var _low_size: Vector2i
var _failed: bool = false

func _init() -> void:
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color = true
    access_resolved_depth = true
    enabled = false

func publish(values: PackedFloat32Array, scale: float, shadow: RID, cloud: RID) -> void:
    _mutex.lock()
    _values = values
    _shadow = shadow
    _cloud = cloud
    _scale = scale
    _mutex.unlock()

func _initialize() -> bool:
    if _failed: return false
    if _rd == null: _rd = RenderingServer.get_rendering_device()
    if _rd == null: return false
    if _shader.is_valid(): return true
    var source: RDShaderSource = RDShaderSource.new()
    source.source_compute = CODE
    var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(source)
    if not spirv.compile_error_compute.is_empty():
        push_error("Light shafts shader: " + spirv.compile_error_compute)
        _failed = true
        return false
    _shader = _rd.shader_create_from_spirv(spirv)
    _pipeline = _rd.compute_pipeline_create(_shader)
    var state: RDSamplerState = RDSamplerState.new()
    state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    _sampler = _rd.sampler_create(state)
    state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    _nearest = _rd.sampler_create(state)
    _buffer = _rd.storage_buffer_create(400)
    return true

func _texture(size: Vector2i) -> RID:
    var format: RDTextureFormat = RDTextureFormat.new()
    format.width = size.x
    format.height = size.y
    format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
    return _rd.texture_create(format,RDTextureView.new())

func _dispatch(stage: int, output: RID, color: RID, depth: RID, rays: RID, shadow: RID, cloud: RID, size: Vector2i) -> void:
    var uniforms: Array[RDUniform] = []
    var textures: Array[RID] = [output,color,depth,rays,shadow,cloud]
    for index: int in range(6):
        var uniform: RDUniform = RDUniform.new()
        uniform.binding = index
        uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE if index == 0 else RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        if index != 0: uniform.add_id(_nearest if index in [2,4,5] else _sampler)
        uniform.add_id(textures[index])
        uniforms.append(uniform)
    var data: RDUniform = RDUniform.new()
    data.binding = 6
    data.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
    data.add_id(_buffer)
    uniforms.append(data)
    var history: RDUniform = RDUniform.new()
    history.binding = 7
    history.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    history.add_id(_sampler)
    history.add_id(_history if _history.is_valid() else depth)
    uniforms.append(history)
    var uniform_set: RID = UniformSetCacheRD.get_cache(_shader,0,uniforms)
    var commands: int = _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(commands,_pipeline)
    _rd.compute_list_bind_uniform_set(commands,uniform_set,0)
    _rd.compute_list_set_push_constant(commands,PackedFloat32Array([stage,0,0,0]).to_byte_array(),16)
    _rd.compute_list_dispatch(commands,ceili(size.x/8.0),ceili(size.y/8.0),1)
    _rd.compute_list_end()

func _render_callback(kind: int, data: RenderData) -> void:
    if kind != effect_callback_type or not _initialize(): return
    var buffers: RenderSceneBuffersRD = data.get_render_scene_buffers() as RenderSceneBuffersRD
    if buffers == null: return
    _mutex.lock()
    var values: PackedFloat32Array = _values.duplicate()
    var shadow: RID = _shadow
    var cloud: RID = _cloud
    var scale: float = _scale
    _mutex.unlock()
    if values.size() != 100: return
    var size: Vector2i = buffers.get_internal_size()
    if size.x == 0 or size.y == 0: return
    var low_size: Vector2i = Vector2i(maxi(1,int(size.x*scale)),maxi(1,int(size.y*scale)))
    if not capture and (size != _size or low_size != _low_size):
        if _scratch.is_valid(): _rd.free_rid(_scratch)
        if _rays.is_valid(): _rd.free_rid(_rays)
        if _history.is_valid(): _rd.free_rid(_history)
        if _filtered.is_valid(): _rd.free_rid(_filtered)
        _history = _texture(low_size)
        _filtered = _texture(low_size)
        values[94] = 1.0
        _scratch = _texture(size)
        _rays = _texture(low_size)
        _size = size
        _low_size = low_size
    _rd.buffer_update(_buffer,0,400,values.to_byte_array())
    for view: int in range(buffers.get_view_count()):
        var color: RID = buffers.get_color_layer(view)
        var depth: RID = buffers.get_depth_layer(view)
        var shadow_rd: RID = RenderingServer.texture_get_rd_texture(shadow) if shadow.is_valid() else depth
        var cloud_rd: RID = RenderingServer.texture_get_rd_texture(cloud) if cloud.is_valid() else depth
        if not shadow_rd.is_valid(): shadow_rd = depth
        if not cloud_rd.is_valid(): cloud_rd = depth
        if capture:
            _dispatch(1,color,depth,depth,depth,depth,depth,size)
        else:
            _dispatch(0,_scratch,color,depth,depth,shadow_rd,cloud_rd,size)
            _dispatch(2,_rays,_scratch,depth,depth,shadow_rd,cloud_rd,low_size)
            _dispatch(4,_filtered,_scratch,depth,_rays,shadow_rd,cloud_rd,low_size)
            _dispatch(3,color,_scratch,depth,_filtered,shadow_rd,cloud_rd,size)
            var previous: RID = _history
            _history = _filtered
            _filtered = previous

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and _rd != null:
        for handle: RID in [_shader,_sampler,_nearest,_buffer,_scratch,_rays,_history,_filtered]:
            if handle.is_valid(): _rd.free_rid(handle)
