#pragma once
#include <algorithm>
#include <alloy3d/camera.h>
#include <span>

namespace alloy3d
{
// Approximate vertical screen fraction of a world-space sphere, independent of resolution.
// Objects touching the eye plane choose maximum detail. Radius must include placement scale.
inline float ProjectedHeight3D(const CameraData &camera, simd_float3 center, float radius)
{
  if (!std::isfinite(radius) || radius < 0 || !simd_all(simd_abs(center) < INFINITY))
    throw std::invalid_argument(
        "Alloy3D projected size requires finite center and nonnegative radius");
  float scale = std::abs(camera.getProjectionMatrix().columns[1].y);
  if (camera.getProjectionMode() != ProjectionMode::Perspective)
    return radius * scale;
  float depth = -simd_mul(camera.getModelViewMatrix(), simd_make_float4(center, 1)).z;
  return depth <= radius ? INFINITY : radius * scale / depth;
}
struct LodTransition3D
{
  size_t nearLevel = 0, farLevel = 0;
  float  farWeight = 0;
};
// Thresholds are descending screen fractions. Bands may not overlap.
// Stateless transitions stay reproducible when revisiting a camera/time.
inline LodTransition3D SelectLod3D(float size, std::span<const float> thresholds, float band = .1f)
{
  if (std::isnan(size) || size < 0 || !std::isfinite(band) || band < 0 || band >= 1)
    throw std::invalid_argument("Alloy3D LOD requires nonnegative size and band in [0,1)");
  float previous = INFINITY;
  for (float t : thresholds)
  {
    if (!std::isfinite(t) || t <= 0 || t * (1 + band) >= previous)
      throw std::invalid_argument("Alloy3D LOD thresholds must descend with nonoverlapping bands");
    previous = t * (1 - band);
  }
  for (size_t i = 0; i < thresholds.size(); ++i)
  {
    float t = thresholds[i];
    if (size >= t * (1 + band))
      return {i, i, 0};
    if (band > 0 && size > t * (1 - band))
    {
      float w = std::clamp((t * (1 + band) - size) / (2 * t * band), 0.f, 1.f);
      return {i, i + 1, w * w * (3 - 2 * w)};
    }
  }
  return {thresholds.size(), thresholds.size(), 0};
}
} // namespace alloy3d
