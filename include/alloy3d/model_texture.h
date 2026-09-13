#pragma once
#include <simd/vector_types.h>

namespace alloy3d
{
// Base-color UV transform: sampledUV = meshUV * scale + offset.
// Persistent draw state, captured for each model draw or instance batch.
// All components must be finite. Negative/zero scales are allowed.
struct ModelTextureTransform3D
{
  simd_float2 scale  = {1, 1};
  simd_float2 offset = {0, 0};
};
} // namespace alloy3d
