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
  return half(shadowMap.sample_compare(compareSampler, uv, ndc.z - parameters.y));
}
