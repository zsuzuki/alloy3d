#include <metal_stdlib>
#include "shadow.h"
using namespace metal;
struct PostVertex { float4 position [[position]]; float2 uv; };
vertex PostVertex postProcessVertex(uint id [[vertex_id]])
{
  float2 p=float2(id==1 ? 3.f : -1.f,id==2 ? 3.f : -1.f);
  return {float4(p,0,1),p*float2(.5,-.5)+.5};
}
fragment half4 toneMapFragment(PostVertex in [[stage_in]],texture2d<half> hdr [[texture(0)]],
                              constant float4 &parameters [[buffer(0)]],texture2d<half> bloom [[texture(1)]],
                              texture2d<half> volume [[texture(2)]],texture2d<float> sceneDepth [[texture(3)]])
{
  constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
  half4 sample=hdr.sample(s,in.uv);
  float3 color=float3(sample.rgb);
  if(parameters.z>0)color+=float3(bloom.sample(s,in.uv).rgb)*parameters.z;
  if(parameters.w>0)
  {
    constexpr sampler nearest(coord::normalized,address::clamp_to_edge,filter::nearest);
    float depth=min(sceneDepth.sample(nearest,in.uv).r,10000.f);
    float2 p=in.uv*float2(volume.get_width(),volume.get_height())-.5f;
    int2 base=int2(floor(p));float2 f=fract(p);float total=0;float3 sum=0;
    for(int y=0;y<2;++y)for(int x=0;x<2;++x)
    {
      uint2 q=uint2(clamp(base+int2(x,y),int2(0),int2(volume.get_width()-1,volume.get_height()-1)));
      float4 v=float4(volume.read(q));
      float weight=(x ? f.x : 1-f.x)*(y ? f.y : 1-f.y)/(1+abs(v.a-depth)*8.f);
      sum+=v.rgb*weight;total+=weight;
    }
    color+=sum/max(total,1e-6f);
  }
  color=select(clamp(color,0.f,65504.f),float3(0),isnan(color))*parameters.x;
  if(parameters.y==1)color=color/(1+color);
  if(parameters.y==2)color=saturate((color*(2.51f*color+.03f))/(color*(2.43f*color+.59f)+.14f));
  return half4(half3(color),sample.a);
}

kernel void bloomExtract(texture2d<half,access::read> scene [[texture(0)]],
                         texture2d<half,access::write> bloom [[texture(1)]],
                         constant float4 &p [[buffer(0)]],uint2 id [[thread_position_in_grid]])
{
  if(id.x>=bloom.get_width() || id.y>=bloom.get_height())return;
  float3 sum=0;
  for(uint y=0;y<2;++y)for(uint x=0;x<2;++x)
  {
    float3 color=max(float3(scene.read(min(id*2+uint2(x,y),uint2(scene.get_width()-1,scene.get_height()-1))).rgb),0.f);
  color=select(clamp(color,0.f,65504.f),float3(0),isnan(color));
    float brightness=max(color.x,max(color.y,color.z)),knee=max(p.x*.5f,1e-5f);
    float soft=clamp(brightness-p.x+knee,0.f,2*knee);soft=soft*soft/(4*knee);
    sum+=color*(max(brightness-p.x,soft)/max(brightness,1e-5f));
  }
  bloom.write(half4(half3(sum*.25f),0),id);
}
kernel void bloomBlur(texture2d<half,access::sample> input [[texture(0)]],
                      texture2d<half,access::write> output [[texture(1)]],
                      constant float4 &p [[buffer(0)]],uint2 id [[thread_position_in_grid]])
{
  if(id.x>=output.get_width() || id.y>=output.get_height())return;
  constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
  float2 size=float2(output.get_width(),output.get_height()),uv=(float2(id)+.5f)/size;
  float2 step=p.yz*p.x/(4*size);
  constexpr float weights[5]={.227027027f,.194594595f,.121621622f,.054054054f,.016216216f};
  float3 color=float3(input.sample(s,uv).rgb)*weights[0];
  for(int i=1;i<=4;++i)color+=(float3(input.sample(s,uv+step*float(i)).rgb)+float3(input.sample(s,uv-step*float(i)).rgb))*weights[i];
  output.write(half4(half3(color),0),id);
}

struct SceneDepthUniforms { float4x4 inverseProjection;float4 parameters; };
inline float LinearSceneDepth(float depth,uint2 p,uint2 size,constant SceneDepthUniforms &u)
{
  if(depth>=1)return 1e6f;
  float2 uv=(float2(p)+.5f)/float2(size);
  float4 view=u.inverseProjection*float4(uv.x*2-1,1-uv.y*2,depth,1);
  return view.z/view.w*u.parameters.x;
}
kernel void resolveSceneDepth(depth2d<float,access::read> source [[texture(0)]],
    texture2d<float,access::write> target [[texture(1)]],constant SceneDepthUniforms &u [[buffer(0)]],uint2 p [[thread_position_in_grid]])
{
  uint2 size(target.get_width(),target.get_height());if(any(p>=size))return;
  target.write(float4(LinearSceneDepth(source.read(p),p,size,u)),p);
}
kernel void resolveSceneDepthMS(depth2d_ms<float,access::read> source [[texture(0)]],
    texture2d<float,access::write> target [[texture(1)]],constant SceneDepthUniforms &u [[buffer(0)]],uint2 p [[thread_position_in_grid]])
{
  uint2 size(target.get_width(),target.get_height());if(any(p>=size))return;
  float d=1;for(uint i=0;i<source.get_num_samples();++i)d=min(d,source.read(p,i));
  target.write(float4(LinearSceneDepth(d,p,size,u)),p);
}

struct VolumeUniforms
{
  float4x4 inverseProjection,inverseView,shadowTransform;
  float4 lightDirection,lightColor,shadowParameters,densityParameters,marchParameters;
};
kernel void volumeLight(texture2d<float> depth [[texture(0)]],depth2d<float> shadow [[texture(1)]],
    texture2d<half,access::write> output [[texture(2)]],constant VolumeUniforms &u [[buffer(0)]],uint2 p [[thread_position_in_grid]])
{
  uint2 size(output.get_width(),output.get_height());if(any(p>=size))return;
  float2 uv=(float2(p)+.5f)/float2(size);
  constexpr sampler nearest(coord::normalized,address::clamp_to_edge,filter::nearest);
  float endDepth=depth.sample(nearest,uv).r;
  float4 farPoint=u.inverseProjection*float4(uv.x*2-1,1-uv.y*2,1,1);
  float3 farView=farPoint.xyz/farPoint.w;
  float3 origin=u.marchParameters.w>0 ? float3(0) : float3(farView.xy,0);
  float3 ray=u.marchParameters.w>0 ? normalize(farView) : float3(0,0,u.marchParameters.z);
  float distance=min(u.marchParameters.x,endDepth/max(ray.z*u.marchParameters.z,1e-4f));
  float3 worldOrigin=(u.inverseView*float4(origin,1)).xyz;
  float3 worldRay=normalize((u.inverseView*float4(ray,0)).xyz);
  float g=u.densityParameters.w;
  float cosine=clamp(dot(worldRay,-u.lightDirection.xyz),-1.f,1.f);
  float phase=(1-g*g)/pow(max(1+g*g-2*g*cosine,.01f),1.5f);
  float step=distance/u.marchParameters.y,transmittance=1,scatter=0;
  for(uint i=0;i<uint(u.marchParameters.y);++i)
  {
    float3 point=worldOrigin+worldRay*((float(i)+.5f)*step);
    float density=u.densityParameters.x*exp(clamp(-u.densityParameters.z*(point.y-u.densityParameters.y),-16.f,8.f));
    float extinction=exp(-density*step);
    float visibility=float(ShadowVisibility(u.shadowTransform*float4(point,1),u.shadowParameters,shadow));
    scatter+=transmittance*(1-extinction)*visibility;
    transmittance*=extinction;
  }
  float3 color=u.lightColor.rgb*(u.lightColor.w*phase*scatter);
  output.write(half4(half3(color),half(min(endDepth,10000.f))),p);
}
