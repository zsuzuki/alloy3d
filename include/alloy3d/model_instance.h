#pragma once
#include <simd/simd.h>

namespace alloy3d
{
// Select color visibility and shadow casting independently (per draw).
struct ModelVisibility3D
{
  bool visible    = true;
  bool castShadow = true;
};

// One placement of a model. Rotations use radians, as in DrawModel3D.
// color.w is an application fade applied after glTF alpha-mode/cutoff rules.
struct ModelInstance
{
  simd_float3 position = {0, 0, 0};
  simd_float3 rotation = {0, 0, 0};
  simd_float3 scale    = {1, 1, 1};
  simd_float4 color    = {1, 1, 1, 1};
  // Dither coverage interval in [0,1]. Complementary intervals crossfade without blending.
  simd_float2 coverage = {0, 1};
};
} // namespace alloy3d
