#pragma once
#include <alloy3d/bounds.h>
#include <cstdint>

namespace alloy3d
{
struct DirectionalLight3D
{
  // World-space direction in which light travels. Finite, nonzero.
  simd_float3 direction = {-.4f, -.8f, -.6f};
  simd_float3 color     = {1, 1, 1};
  float       ambient   = .25f;
  float       diffuse   = .85f;
};

struct DirectionalShadow3D
{
  bool enabled = false;
  // Square depth map, allocated lazily for each of three frame pages. 64..4096.
  uint32_t resolution = 1024;
  // World-space region containing both casters and receivers. No automatic scene scan.
  Bounds3D bounds{{-10, -10, -10}, {10, 10, 10}};
  // Bias in normalized light depth. Valid range [0, 0.1].
  float depthBias = .001f;
  // Caster slope bias, [0,8]; 0 disables. Internal normalized depth clamp is 0.01.
  float slopeScale = 2.0f;
};
} // namespace alloy3d
