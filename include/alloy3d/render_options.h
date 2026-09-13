#pragma once
#include <cstdint>

namespace alloy3d
{
struct RenderOptions
{
  // Requested at launch. 1 (default), 2, 4 or 8 samples per pixel.
  // The bundled host falls back to the highest supported count <= this value.
  uint32_t sampleCount = 1;
  // Optional linear RGBA16Float scene target, tone mapped before the 2D overlay.
  bool hdr = false;
  // Opaque color/depth snapshots for soft particles and screen-space surfaces; requires HDR.
  bool sceneEffects = false;
};
} // namespace alloy3d
