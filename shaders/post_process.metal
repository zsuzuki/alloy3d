#include <metal_stdlib>
using namespace metal;
struct PostVertex { float4 position [[position]]; float2 uv; };
vertex PostVertex postProcessVertex(uint id [[vertex_id]])
{
  float2 p=float2(id==1 ? 3.f : -1.f,id==2 ? 3.f : -1.f);
  return {float4(p,0,1),p*float2(.5,-.5)+.5};
}
fragment half4 toneMapFragment(PostVertex in [[stage_in]],texture2d<half> hdr [[texture(0)]],
                              constant float4 &parameters [[buffer(0)]])
{
  constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
  half4 sample=hdr.sample(s,in.uv);
  float3 color=float3(sample.rgb);
  color=select(clamp(color,0.f,65504.f),float3(0),isnan(color))*parameters.x;
  if(parameters.y==1)color=color/(1+color);
  if(parameters.y==2)color=saturate((color*(2.51f*color+.03f))/(color*(2.43f*color+.59f)+.14f));
  return half4(half3(color),sample.a);
}
