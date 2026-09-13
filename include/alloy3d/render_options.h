#pragma once
#include <cstdint>

namespace alloy3d
{
struct RenderOptions
{
  // Requested at launch. 1 (default), 2, 4 or 8 samples per pixel.
  // The bundled host falls back to the highest supported count <= this value.
  uint32_t sampleCount = 1;
};
} // namespace alloy3d
