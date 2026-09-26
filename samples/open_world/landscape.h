#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <vector>
#include <simd/simd.h>

namespace open_world
{
// CPU walking uses the exact same heightfield triangles as the detailed terrain.
// River and bridge descriptions are generated alongside that field, not duplicated formulas.
class Landscape
{
  uint32_t             n_    = 0;
  float                step_ = 0;
  std::vector<float>   heights_;
  std::vector<uint8_t> zones_;

public:
  struct RiverPoint
  {
    float x, z, water, halfWidth;
  };
  struct Bridge
  {
    float x, z, water, halfSpan;
  };
  std::vector<RiverPoint>  river;
  std::vector<Bridge>      bridges;
  std::vector<simd_float2> route;
  explicit Landscape(const std::filesystem::path &root)
  {
    std::ifstream field(root / "heightfield.bin", std::ios::binary);
    field.read(reinterpret_cast<char *>(&n_), sizeof(n_));
    if (!field || n_ != 641)
      throw std::runtime_error("invalid heightfield size");
    heights_.resize(size_t(n_) * n_);
    zones_.resize(heights_.size());
    field.read(reinterpret_cast<char *>(heights_.data()), heights_.size() * sizeof(float));
    field.read(reinterpret_cast<char *>(zones_.data()), zones_.size());
    if (!field ||
        std::any_of(heights_.begin(), heights_.end(), [](float h) { return !std::isfinite(h); }))
      throw std::runtime_error("invalid heightfield data");
    std::ifstream layout(root / "landscape.txt");
    std::string   version;
    unsigned      n = 0, count = 0;
    layout >> version >> n >> step_;
    if (!layout || version != "ALLOY3D_LANDSCAPE_V1" || n != n_ || step_ != 7.8125f)
      throw std::runtime_error("invalid landscape manifest");
    layout >> count;
    if (count != 501)
      throw std::runtime_error("invalid river samples");
    river.resize(count);
    for (auto &p : river)
      layout >> p.x >> p.z >> p.water >> p.halfWidth;
    layout >> count;
    if (count != 2)
      throw std::runtime_error("invalid bridges");
    bridges.resize(count);
    for (auto &b : bridges)
      layout >> b.x >> b.z >> b.water >> b.halfSpan;
    layout >> count;
    if (count < 2 || count > 100)
      throw std::runtime_error("invalid scenic route");
    route.resize(count);
    for (auto &p : route)
    {
      float x = 0, z = 0;
      layout >> x >> z;
      p = {x, z};
    }
    if (!layout)
      throw std::runtime_error("truncated landscape manifest");
  }
  float Ground(float x, float z) const
  {
    const float    fx = std::clamp(x / step_, 0.f, n_ - 1.001f);
    const float    fz = std::clamp(z / step_, 0.f, n_ - 1.001f);
    const unsigned i = unsigned(fx), j = unsigned(fz);
    const float    u = fx - i, v = fz - j;
    const float    a = heights_[j * n_ + i], b = heights_[j * n_ + i + 1];
    const float    c = heights_[(j + 1) * n_ + i], d = heights_[(j + 1) * n_ + i + 1];
    return v >= u ? a + (d - c) * u + (c - a) * v : a + (b - a) * u + (d - b) * v;
  }
  RiverPoint River(float z) const
  {
    float    t = std::clamp(z / 10, 0.f, 499.999f);
    unsigned i = unsigned(t);
    t -= i;
    const auto a = river[i], b = river[i + 1];
    return {a.x + (b.x - a.x) * t,
            z,
            a.water + (b.water - a.water) * t,
            a.halfWidth + (b.halfWidth - a.halfWidth) * t};
  }
  const Bridge *OnBridge(float x, float z) const
  {
    for (const auto &b : bridges)
      if (std::abs(x - b.x) <= b.halfSpan && std::abs(z - b.z) < 3.6f)
        return &b;
    return nullptr;
  }
  float WalkHeight(float x, float z) const
  {
    if (auto b = OnBridge(x, z))
    {
      float t = (x - b->x) / b->halfSpan;
      // The deck has 28 linear segments, matching the generated mesh exactly.
      float q = (t + 1) * 14, i = std::min(27.f, std::floor(q)), f = q - i;
      float a = i / 14 - 1, c = (i + 1) / 14 - 1;
      return b->water + 5 + 1.3f * ((1 - a * a) * (1 - f) + (1 - c * c) * f);
    }
    return Ground(x, z);
  }
  bool Dry(float x, float z) const
  {
    const auto r = River(z);
    return OnBridge(x, z) ||
           (std::abs(x - r.x) > r.halfWidth * 1.2f && Ground(x, z) > r.water + .4f);
  }
  bool GrassAllowed(float x, float z) const
  {
    if (x < 1 || x > 4999 || z < 1 || z > 4999)
      return false;
    const auto i = unsigned(std::round(x / step_)), j = unsigned(std::round(z / step_));
    return zones_[j * n_ + i] == 0 && Dry(x, z);
  }
  simd_float3 Spawn() const { return {bridges.front().x - 170, 0, bridges.front().z}; }
  simd_float3 Tour(float distance, float &yaw) const
  {
    float total = 0;
    for (size_t i = 1; i < route.size(); ++i)
      total += simd_length(route[i] - route[i - 1]);
    float      d       = std::fmod(std::max(0.f, distance), total * 2);
    const bool reverse = d > total;
    if (reverse)
      d = total * 2 - d;
    for (size_t i = 1; i < route.size(); ++i)
    {
      auto  delta = route[i] - route[i - 1];
      float len   = simd_length(delta);
      if (d <= len || i + 1 == route.size())
      {
        auto p = route[i - 1] + delta * (d / len);
        yaw    = std::atan2(reverse ? -delta.x : delta.x, reverse ? delta.y : -delta.y);
        return {p.x, WalkHeight(p.x, p.y) + 1.8f, p.y};
      }
      d -= len;
    }
    return Spawn();
  }
  size_t Bytes() const { return heights_.capacity() * sizeof(float) + zones_.capacity(); }
};
} // namespace open_world
