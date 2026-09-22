#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1) in;
layout(rgba16f,set=0,binding=0) uniform restrict writeonly image2D output_image;
layout(set=0,binding=1) uniform sampler2D scene_color;
layout(set=0,binding=2) uniform sampler2D scene_depth;
layout(set=0,binding=3) uniform sampler2D scene_velocity;
layout(set=0,binding=4) uniform sampler2D ray_image;
layout(push_constant,std430) uniform Params {
	vec4 size_mode_strength;
	vec4 sun;
	vec4 controls;
	vec4 extras;
	mat4 inv_projection;
} p;
float linear_depth(vec2 uv) {
	float d=textureLod(scene_depth,uv,0.0).r;
	vec4 view=p.inv_projection*vec4(uv*2.0-1.0,d,1.0);
	return abs(view.z/max(abs(view.w),0.00001));
}
void main() {
	ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);
	ivec2 size=imageSize(output_image);
	if(any(greaterThanEqual(pixel,size)))return;
	vec2 uv=(vec2(pixel)+0.5)/vec2(size);
	int mode=int(p.size_mode_strength.z);
	vec4 color=textureLod(scene_color,uv,0.0);
	if(mode==0 && p.extras.w<0.5) {
		vec2 velocity=textureLod(scene_velocity,uv,0.0).xy*p.size_mode_strength.w;
		vec2 pixel_velocity=velocity*p.size_mode_strength.xy;
		float magnitude=length(pixel_velocity);
		velocity*=min(1.0,p.controls.y/max(magnitude,0.0001));
		float depth=linear_depth(uv),weight=1.0;
		vec3 sum=color.rgb;
		int steps=int(p.controls.x);
		for(int i=1;i<32;i++) {
			if(i>=steps)break;
			vec2 q=uv-velocity*(float(i)/float(steps-1)-0.5);
			if(any(lessThan(q,vec2(0)))||any(greaterThan(q,vec2(1))))continue;
			float accept=1.0-smoothstep(p.controls.z,p.controls.z*2.0,abs(linear_depth(q)-depth));
			sum+=textureLod(scene_color,q,0.0).rgb*accept;weight+=accept;
		}
		color.rgb=sum/weight;
	} else if(mode==1) {
		float sum=0.0,weight=1.0,norm=0.0;
		int steps=int(p.controls.x);
		vec2 step_uv=(p.sun.xy-uv)*p.controls.y/float(steps);
		vec2 q=uv;
		for(int i=0;i<96;i++) {
			if(i>=steps)break;
			q+=step_uv;
			if(all(greaterThanEqual(q,vec2(0)))&&all(lessThanEqual(q,vec2(1)))) {
				float sky=step(textureLod(scene_depth,q,0.0).r,0.000001);
				float disc=exp(-dot(q-p.sun.xy,q-p.sun.xy)*50.0);
				sum+=sky*disc*weight;
			}
			norm+=weight;weight*=p.sun.w;
		}
		uint packed_color=uint(p.extras.w);
		vec3 tint=vec3((packed_color>>16)&255u,(packed_color>>8)&255u,packed_color&255u)/255.0;
		color=vec4(tint*(sum/max(norm,0.001)*p.sun.z*p.size_mode_strength.w),1.0);
	} else if(mode==2) {
		if(p.controls.w>0.0) {
			vec2 direction=(uv-0.5)*2.0;
			float r=length(direction);
			float amount=pow(clamp((r-p.extras.x)/max(1.0-p.extras.x,0.01),0.0,1.0),p.extras.y);
			vec2 shift=normalize(direction+vec2(0.000001))*p.controls.w*amount/p.size_mode_strength.xy;
			color.r=textureLod(scene_color,clamp(uv+shift,vec2(0),vec2(1)),0.0).r;
			color.b=textureLod(scene_color,clamp(uv-shift,vec2(0),vec2(1)),0.0).b;
		}
		if(p.extras.z>0.5) {
			// Depth-aware upsampling: reject low-resolution rays across foreground edges.
			vec2 ray_size=vec2(textureSize(ray_image,0));
			vec2 low_uv=(floor(uv*ray_size)+0.5)/ray_size;
			float edge=1.0-smoothstep(p.controls.z,p.controls.z*2.0,abs(linear_depth(uv)-linear_depth(low_uv)));
			color.rgb+=textureLod(ray_image,uv,0.0).rgb*edge;
		}
	}
	imageStore(output_image,pixel,color);
}
