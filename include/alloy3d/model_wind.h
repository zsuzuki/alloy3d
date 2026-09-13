#pragma once
#include <simd/simd.h>
namespace alloy3d
{
struct ModelWind3D
{
  float strength = 0; // Maximum displacement in model units, [0,10]. Zero disables.
  float time = 0; // Application-controlled seconds; frozen time freezes both color and shadow.
  simd_float2 direction = {1,0}; // Model-space XZ direction, normalized by the setter.
  float baseHeight = 0; // Model-space Y fixed below this height, after skinning.
  float tipHeight = 1; // Smooth quadratic bend reaches full amplitude here.
  float frequency = 1.35f; // Radians per second, [0,100].
};
} // namespace alloy3d
