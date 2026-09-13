#pragma once
#include <algorithm>
#include <alloy3d/bounds.h>
#include <alloy3d/camera.h>
#include <array>

namespace alloy3d
{
// Metal clip volume: -w <= x,y <= w, 0 <= z <= w. Boundary contact is visible.
// Unknown/invalid bounds stay visible. Supply model-to-world, including mirrored scale.
class Frustum3D
{
  simd_float4x4 clip_;

public:
  explicit Frustum3D(const CameraData &camera)
      : clip_(simd_mul(camera.getProjectionMatrix(), camera.getModelViewMatrix()))
  {
  }
  bool intersects(const Bounds3D &bounds, simd_float4x4 model = matrix_identity_float4x4) const
  {
    if (!bounds.isValid())
      return true;
    auto                       rows   = simd_transpose(simd_mul(clip_, model));
    std::array<simd_float4, 6> planes = {rows.columns[3] + rows.columns[0],
                                         rows.columns[3] - rows.columns[0],
                                         rows.columns[3] + rows.columns[1],
                                         rows.columns[3] - rows.columns[1],
                                         rows.columns[2],
                                         rows.columns[3] - rows.columns[2]};
    auto center = bounds.min * .5f + bounds.max * .5f, extent = bounds.max * .5f - bounds.min * .5f;
    for (auto p : planes)
    {
      float distance = simd_dot(p.xyz, center) + p.w;
      float radius   = simd_dot(simd_abs(p.xyz), extent);
      // Conservative tolerance avoids clipping touching geometry through roundoff.
      if (distance + radius < -1e-5f * (1 + std::abs(distance) + radius))
        return false;
    }
    return true;
  }
};
} // namespace alloy3d
