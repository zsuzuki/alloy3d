#pragma once

#include <cstddef>

namespace alloy3d
{
struct TextCacheBudget
{
  // Combined 2D + 3D limits. Each renderer receives half of each budget.
  std::size_t bitmapBytes  = 8 * 1024 * 1024;
  std::size_t textureBytes = 16 * 1024 * 1024;
};

struct RenderMemoryStats
{
  // Library-owned capacity across all three frame pages, not process RSS.
  std::size_t vertexBufferBytes     = 0;
  std::size_t instanceBufferBytes   = 0;
  std::size_t shadowMapBytes        = 0; // Depth texels across frame pages (plus 1 fallback texel).
  std::size_t textBitmapCacheBytes  = 0;
  std::size_t textTextureCacheBytes = 0;
  std::size_t textCacheEntries      = 0;
  // True until all frame pages scheduled for release have been reused safely.
  bool        releasePending   = false;
  std::size_t postProcessBytes = 0; // Optional HDR targets across all frame pages.
};
} // namespace alloy3d
