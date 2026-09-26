#pragma once
namespace open_world
{
// Crossed grass cards should not turn black when their back faces point downward.
inline constexpr const char *GrassSurface = R"metal(
float3 alloy3dShade(ModelSurface s, float4 p)
{
  return max(s.litColor, s.baseColor * .42);
}
)metal";
// Uses the existing per-model material hook; no reflection pass or new renderer feature.
inline constexpr const char *RiverMaterial = R"metal(
ModelMaterial alloy3dMaterial(ModelMaterial m, ModelMaterialContext c, float4 p)
{
  float2 uv=c.texcoord;
  float3 dx=dfdx(c.viewPosition), dy=dfdy(c.viewPosition);
  float2 tx=dfdx(uv), ty=dfdy(uv);
  float det=tx.x*ty.y-tx.y*ty.x;
  float wave=sin(uv.x*4+uv.y*1.3-p.x*1.6)*cos(uv.y*5+p.x*.7);
  if(abs(det)>1e-9)
  {
    float3 tangent=normalize((dx*ty.y-dy*tx.y)/det);
    float3 bitangent=normalize((dy*tx.x-dx*ty.x)/det);
    m.normal=normalize(m.normal+tangent*(wave*.065)+bitangent*(sin(uv.y*7-p.x*1.4)*.035));
  }
  float fresnel=pow(1-saturate(dot(m.normal,c.viewDirection)),4.0);
  m.baseColor=mix(m.baseColor*(.88+wave*.07),float3(.36,.55,.64),fresnel*.65);
  m.emissive=float3(.035,.055,.06)*fresnel;
  m.roughness=.18;
  return m;
}
)metal";
} // namespace open_world
