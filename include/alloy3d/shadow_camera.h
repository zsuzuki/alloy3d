#pragma once
#include <alloy3d/camera.h>
#include <alloy3d/lighting.h>
#include <algorithm>

namespace alloy3d
{
// Build the same conservative orthographic camera as the bundled shadow renderer.
// Supply world bounds containing both receivers and casters. Throws on invalid settings.
inline CameraData BuildDirectionalShadowCamera3D(const DirectionalShadow3D &settings,
                                      simd_float3                         direction)
{
  auto wide = simd_make_double3(direction.x,direction.y,direction.z);
  if (!simd_all(simd_abs(direction) < INFINITY) || simd_length_squared(wide) == 0)
    throw std::invalid_argument("Alloy3D shadow light direction must be finite and nonzero");
  wide = simd_normalize(wide);
  direction = simd_make_float3(wide.x,wide.y,wide.z);
  if (!settings.bounds.isValid() || settings.resolution < 64 || settings.resolution > 4096 ||
      !std::isfinite(settings.depthBias) || settings.depthBias < 0 || settings.depthBias > .1f ||
      !std::isfinite(settings.slopeScale) || settings.slopeScale < 0 || settings.slopeScale > 8 ||
      !std::isfinite(settings.filterRadius) || settings.filterRadius < 0 || settings.filterRadius > 4)
    throw std::invalid_argument("Alloy3D shadow requires finite bounds, resolution 64..4096, bias "
                                "0..0.1 and slope scale 0..8");
  const auto  center = settings.bounds.min * .5f + settings.bounds.max * .5f;
  const float radius =
      std::max(.01f, simd_length(settings.bounds.max * .5f - settings.bounds.min * .5f));
  alloy3d::CameraData camera;
  camera.buildModelView(center - direction * (radius * 2 + 1), center, {0, 1, 0});
  const auto  bounds = settings.bounds.transformed(camera.getModelViewMatrix());
  const float extent = std::max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y);
  const float margin = std::max(.01f, radius * .05f);
  if (settings.stabilize)
  {
    const float texel = std::max(.01f,extent*1.05f)/settings.resolution;
    auto inverse = simd_inverse(camera.getModelViewMatrix());
    auto right = inverse.columns[0].xyz, up = inverse.columns[1].xyz;
    float x = simd_dot(center,right), y = simd_dot(center,up);
    auto snapped = center + right*(std::round(x/texel)*texel-x) + up*(std::round(y/texel)*texel-y);
    camera.buildModelView(snapped-direction*(radius*2+1),snapped,{0,1,0});
  }
  camera.buildOrthographic(std::max(.01f, extent * 1.05f),
                           1,
                           std::max(.001f, -bounds.max.z - margin),
                           -bounds.min.z + margin);
  return camera;
}

} // namespace alloy3d
