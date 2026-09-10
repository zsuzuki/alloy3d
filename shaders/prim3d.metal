//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include "shader_def.h"
#include "shadow.h"
#include "environment.h"

#include <metal_stdlib>
using namespace metal;

struct v2f
{
  float4 position [[position]];
  float3 normal;
  half4  color;
  float4 shadowPosition;
  float viewDepth;
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
  o.viewDepth = cameraData.fogColorAndEnabled.w != 0 ? -(cameraData.worldTransform * pos).z : 0;
  pos        = cameraData.perspectiveTransform * cameraData.worldTransform * pos;
  o.position = pos;
  o.normal   = cameraData.worldNormalTransform * vd.normal;
  o.color    = vd.color;
  o.shadowPosition =
      cameraData.shadowTransform * cameraData.worldTransform * float4(vd.position, 1);

  return o;
}

fragment half4 primFrag3d(v2f in [[stage_in]], device const Uniforms &cameraData [[buffer(1)]],
                          depth2d<float> shadowMap [[texture(1)]])
{
  half4 baseColor    = in.color;
  float normalLength = length(in.normal);
  if (normalLength < 0.001)
  {
    return ApplyFog(baseColor, in.viewDepth, cameraData);
  }

  float3 n          = in.normal / normalLength;
  float3 l          = normalize(-cameraData.lightDirectionAndAmbient.xyz);
  half3  ambient    = EnvironmentAmbient(n, cameraData);
  half   diffuse    = half(saturate(dot(n, l)) * saturate(cameraData.lightColorAndDiffuse.w));
  diffuse *= ShadowVisibility(in.shadowPosition, cameraData.shadowParameters, shadowMap);
  half3  lightColor = half3(cameraData.lightColorAndDiffuse.xyz);
  half3  illum      = baseColor.rgb * (ambient + diffuse * lightColor);

  return ApplyFog(half4(illum, baseColor.a), in.viewDepth, cameraData);
}

fragment void shadowPrimFrag3d(v2f in [[stage_in]])
{
  if (in.color.a < 1)
    discard_fragment();
}
