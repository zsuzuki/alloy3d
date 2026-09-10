#pragma once
// Included after shader_def.h; also embedded in runtime custom shader sources.
#include <metal_stdlib>
using namespace metal;

inline half3 EnvironmentAmbient(float3 normal, device const Uniforms &camera)
{
  if (camera.hemisphereUpAndEnabled.w == 0)
    return half3(half(saturate(camera.lightDirectionAndAmbient.w)));
  float t = saturate(dot(normal, camera.hemisphereUpAndEnabled.xyz) * .5f + .5f);
  return half3(mix(camera.hemisphereGround.xyz, camera.hemisphereSky.xyz, t));
}

inline half4 ApplyFog(half4 color, float viewDepth, device const Uniforms &camera)
{
  if (camera.fogColorAndEnabled.w == 0)
    return color;
  float t = saturate((viewDepth - camera.fogParameters.x) * camera.fogParameters.y);
  return half4(half3(mix(float3(color.rgb), camera.fogColorAndEnabled.rgb, t)), color.a);
}
