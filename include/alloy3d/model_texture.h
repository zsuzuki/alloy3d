#pragma once
#include <simd/vector_types.h>
#include <cstdint>

namespace alloy3d
{
struct ModelNormalMapping3D
{
  // Multiplier for glTF normalTexture.scale. Finite [0,8]; zero disables mapping.
  float strength = 1;
};

struct ModelTextureSampling3D
{
  // 1 disables anisotropic filtering. Integer range [1,16].
  uint32_t maxAnisotropy = 1;
};

// Base-color and normal-map UV transform: sampledUV = meshUV * scale + offset.
// Persistent draw state, captured for each model draw or instance batch.
// All components must be finite. Negative/zero scales are allowed.
struct ModelTextureTransform3D
{
  simd_float2 scale  = {1, 1};
  simd_float2 offset = {0, 0};
};
} // namespace alloy3d
