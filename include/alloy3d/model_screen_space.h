#pragma once
namespace alloy3d
{
// Optional opaque scene lookup on BLEND/faded models. Requires RenderOptions.sceneEffects.
struct ModelScreenSpace3D
{
  float refraction       = 0;   // [0,1]
  float refractionPixels = 8;   // [0,128], normal-based screen offset
  float reflection       = 0;   // [0,1], dielectric Fresnel multiplier
  float maxDistance      = 24;  // (0,1000], view-space ray distance
  float thickness        = .5f; // (0,10], depth intersection tolerance
};
} // namespace alloy3d
