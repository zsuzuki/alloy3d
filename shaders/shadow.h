#pragma once
#include <metal_stdlib>
using namespace metal;

inline half ShadowVisibility(float4 position, float4 parameters, depth2d<float> shadowMap)
{
  if (parameters.x == 0 || position.w <= 0)
    return 1;
  float3 ndc = position.xyz / position.w;
  float2 uv  = float2(ndc.x * .5 + .5, .5 - ndc.y * .5);
  if (any(uv < 0) || any(uv > 1) || ndc.z < 0 || ndc.z > 1)
    return 1;
  // Hardware comparison filtering provides a small PCF footprint.
  constexpr sampler compareSampler(
      coord::normalized, address::clamp_to_edge, filter::linear, compare_func::less_equal);
  if (parameters.z <= 0)
    return half(shadowMap.sample_compare(compareSampler, uv, ndc.z - parameters.y));
  float visibility = 0;
  for (int y = -1; y <= 1; ++y)
    for (int x = -1; x <= 1; ++x)
    {
      float2 tap = uv + float2(x, y) * parameters.z * parameters.w;
      visibility += any(tap < 0) || any(tap > 1)
                        ? 1.f
                        : shadowMap.sample_compare(compareSampler, tap, ndc.z - parameters.y);
    }
  return half(visibility / 9.f);
}
