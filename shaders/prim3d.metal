//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include "shader_def.h"

#include <metal_stdlib>
using namespace metal;

struct v2f
{
  float4 position [[position]];
  float3 normal;
  half4  color;
};

//
//
//
vertex v2f primVert3d(device const VertexDataPrim3D *vertexData [[buffer(0)]],
                      device const Uniforms &cameraData [[buffer(1)]], uint vID [[vertex_id]])
{
  v2f o;

  const device VertexDataPrim3D &vd  = vertexData[vID];
  float4                         pos = float4(vd.position, 1.0);
  pos        = cameraData.perspectiveTransform * cameraData.worldTransform * pos;
  o.position = pos;
  o.normal   = cameraData.worldNormalTransform * vd.normal;
  o.color    = vd.color;

  return o;
}

fragment half4 primFrag3d(v2f in [[stage_in]], device const Uniforms &cameraData [[buffer(1)]])
{
  half4 baseColor    = in.color;
  float normalLength = length(in.normal);
  if (normalLength < 0.001)
  {
    return baseColor;
  }

  float3 n          = in.normal / normalLength;
  float3 l          = normalize(-cameraData.lightDirectionAndAmbient.xyz);
  half   ambient    = half(saturate(cameraData.lightDirectionAndAmbient.w));
  half   diffuse    = half(saturate(dot(n, l)) * saturate(cameraData.lightColorAndDiffuse.w));
  half3  lightColor = half3(cameraData.lightColorAndDiffuse.xyz);
  half3  illum      = baseColor.rgb * (ambient + diffuse * lightColor);

  return half4(illum, baseColor.a);
}
