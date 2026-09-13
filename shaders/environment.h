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

inline half4 ApplyFog(half4 color, float viewDepth, float3 viewPosition,
                      device const Uniforms &camera)
{
  if (camera.fogColorAndEnabled.w != 0)
  {
    float t   = saturate((viewDepth - camera.fogParameters.x) * camera.fogParameters.y);
    color.rgb = half3(mix(float3(color.rgb), camera.fogColorAndEnabled.rgb, t));
  }
  if (camera.heightFogColorDensity.w > 0)
  {
    float3 origin = camera.heightFogParameters.w != 0 ? float3(0) : float3(viewPosition.xy, 0);
    float  distance =
        camera.heightFogParameters.w != 0 ? length(viewPosition) : max(0.f, -viewPosition.z);
    float start = dot(origin, camera.heightFogWorldUp.xyz) + camera.heightFogWorldUp.w -
                  camera.heightFogParameters.x;
    float end   = dot(viewPosition, camera.heightFogWorldUp.xyz) + camera.heightFogWorldUp.w -
                  camera.heightFogParameters.x;
    float span  = abs(end - start) * camera.heightFogParameters.y;
    // Analytic integral along the ray, using its denser end to avoid exp overflow products.
    float integral = span > .0001f ? (1.f - exp(-min(span, 80.f))) / span : 1.f;
    float density  = camera.heightFogColorDensity.w *
                     exp(clamp(-min(start, end) * camera.heightFogParameters.y, -50.f, 50.f));
    float t =
        min(1.f - exp(-min(density * distance * integral, 80.f)), camera.heightFogParameters.z);
    color.rgb = half3(mix(float3(color.rgb), camera.heightFogColorDensity.rgb, t));
  }
  return color;
}
