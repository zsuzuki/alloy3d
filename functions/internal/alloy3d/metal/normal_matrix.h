#pragma once
#include <algorithm>
#include <cmath>
#include <simd/simd.h>

namespace alloy3d::metal
{
// Direction-equivalent inverse transpose. Remove a positive uniform scale first
// to avoid overflow/underflow. Singular transforms have no well-defined normal.
inline simd_float3x3 NormalMatrix(const simd_float4x4 &matrix)
{
  auto  a     = matrix.columns[0].xyz;
  auto  b     = matrix.columns[1].xyz;
  auto  c     = matrix.columns[2].xyz;
  float scale = std::max(
      {simd_reduce_max(simd_abs(a)), simd_reduce_max(simd_abs(b)), simd_reduce_max(simd_abs(c))});
  if (!(scale > 0) || !std::isfinite(scale))
    return simd_float3x3{};
  a /= scale;
  b /= scale;
  c /= scale;
  auto  x = simd_cross(b, c), y = simd_cross(c, a), z = simd_cross(a, b);
  float det = simd_dot(a, x);
  if (std::fabs(det) < 1e-8f)
    return simd_float3x3{};
  return simd_matrix(x / det, y / det, z / det);
}
} // namespace alloy3d::metal
