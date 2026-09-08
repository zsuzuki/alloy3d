#pragma once
#include <cmath>
#include <simd/simd.h>
#include <stdexcept>

namespace alloy3d
{
// Axis-aligned bounds. Default construction creates an empty accumulator.
struct Bounds3D
{
  simd_float3 min = {INFINITY, INFINITY, INFINITY};
  simd_float3 max = {-INFINITY, -INFINITY, -INFINITY};

  bool isValid() const
  {
    for (int i = 0; i < 3; ++i)
      if (!std::isfinite(min[i]) || !std::isfinite(max[i]) || min[i] > max[i])
        return false;
    return true;
  }

  void include(simd_float3 point)
  {
    for (int i = 0; i < 3; ++i)
      if (!std::isfinite(point[i]))
        throw std::invalid_argument("Alloy3D bounds require finite points");
    min = simd_min(min, point);
    max = simd_max(max, point);
  }

  void include(const Bounds3D &other)
  {
    if (other.isValid())
    {
      include(other.min);
      include(other.max);
    }
  }

  // Placement transforms must be finite and affine (not projection matrices).
  Bounds3D transformed(const simd_float4x4 &matrix) const
  {
    for (int col = 0; col < 4; ++col)
      for (int row = 0; row < 4; ++row)
        if (!std::isfinite(matrix.columns[col][row]))
          throw std::invalid_argument("Alloy3D bounds require a finite affine transform");
    if (matrix.columns[0].w != 0 || matrix.columns[1].w != 0 || matrix.columns[2].w != 0 ||
        matrix.columns[3].w != 1)
      throw std::invalid_argument("Alloy3D bounds require an affine transform");
    Bounds3D result;
    if (!isValid())
      return result;
    for (int corner = 0; corner < 8; ++corner)
    {
      auto point = simd_make_float4(
          corner & 1 ? max.x : min.x, corner & 2 ? max.y : min.y, corner & 4 ? max.z : min.z, 1);
      result.include(simd_mul(matrix, point).xyz);
    }
    return result;
  }
};
} // namespace alloy3d
