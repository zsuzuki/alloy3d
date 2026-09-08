#pragma once
#include <simd/simd.h>

namespace alloy3d
{
// One placement of a model. Rotations use radians, as in DrawModel3D.
// color.w is an application fade applied after glTF alpha-mode/cutoff rules.
struct ModelInstance
{
  simd_float3 position = {0, 0, 0};
  simd_float3 rotation = {0, 0, 0};
  simd_float3 scale    = {1, 1, 1};
  simd_float4 color    = {1, 1, 1, 1};
};
} // namespace alloy3d
