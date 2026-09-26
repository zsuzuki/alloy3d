#pragma once
#include "landscape.h"
#include <alloy3d/model_instance.h>
#include <alloy3d/streaming_cache.h>
#include <alloy3d/visibility.h>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <stdexcept>

namespace open_world
{
constexpr int            Grid = 20, Count = Grid * Grid;
constexpr float          Cell = 250, Extent = Cell * Grid;
inline alloy3d::Bounds3D CellBounds(unsigned key)
{
  float x = (key % Grid) * Cell, z = (key / Grid) * Cell;
  return {{x, -50, z}, {x + Cell, 750, z + Cell}};
}
inline float Distance(unsigned key, simd_float3 eye)
{
  const auto  b = CellBounds(key);
  const float x = std::max({b.min.x - eye.x, 0.f, eye.x - b.max.x});
  const float z = std::max({b.min.z - eye.z, 0.f, eye.z - b.max.z});
  return std::hypot(x, z);
}

template <class Model> class World
{
public:
  using Ptr  = std::shared_ptr<Model>;
  using Load = std::function<Ptr(const std::filesystem::path &)>;
  struct Placement
  {
    alloy3d::ModelInstance instance;
    unsigned               kind;
  };
  struct Chunk
  {
    Ptr terrain;
    // 16 spatial buckets; avoid individual work for invisible parts of a cell.
    std::array<std::vector<Placement>, 16> buckets;
    size_t                                 Bytes() const
    {
      size_t bytes = sizeof(Chunk);
      for (const auto &bucket : buckets)
        bytes += bucket.capacity() * sizeof(Placement);
      return bytes;
    }
  };
  using Stream = alloy3d::StreamingCache<Chunk>;
  enum Style
  {
    Solid,
    Vegetation,
    Grass,
    Water
  };
  static constexpr unsigned Kinds = 5, Assets = Kinds * 2;
  Landscape                 landscape;
  struct FrameStats
  {
    size_t detailCells = 0, farCells = 0, placements = 0;
  } frame;

private:
  std::filesystem::path                                       root_;
  Load                                                        load_;
  std::array<Ptr, Count>                                      far_;
  std::array<Ptr, Assets>                                     shared_;
  Ptr                                                         grass_, river_, structures_, paths_;
  std::vector<alloy3d::ModelInstance>                         grassInstances_, visibleGrass_;
  simd_int2                                                   grassCell_{-10000, -10000};
  std::unique_ptr<Stream>                                     stream_;
  std::array<std::vector<alloy3d::ModelInstance>, Assets * 3> batches_;
  simd_float3                                                 eye_{};
  bool                                                        first_          = true;
  float                                                       schedulingTime_ = 0;
  std::vector<unsigned>                                       desired_;
  std::shared_ptr<Chunk>                                      LoadChunk(unsigned key)
  {
    auto          result = std::make_shared<Chunk>();
    std::ifstream file(root_ / (std::to_string(key) + ".cell"));
    std::string   version;
    size_t        count = 0;
    if (!(file >> version >> count) || version != "ALLOY3D_CELL_V2" || count > 4096)
      throw std::runtime_error("invalid cell " + std::to_string(key));
    const auto bounds = CellBounds(key);
    for (size_t n = 0; n < count; ++n)
    {
      Placement  p{};
      float      scale = 0, x = 0, y = 0, z = 0, angle = 0;
      auto      &i      = p.instance;
      const bool parsed = bool(file >> p.kind >> x >> y >> z >> angle >> scale);
      i.position        = {x, y, z};
      i.rotation.y      = angle;
      if (!parsed || p.kind >= Kinds || !std::isfinite(scale) || scale <= 0 || scale > 10 ||
          (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) ||
          !std::isfinite(i.rotation.y) || i.position.x < bounds.min.x ||
          i.position.x > bounds.max.x || i.position.z < bounds.min.z || i.position.z > bounds.max.z)
        throw std::runtime_error("invalid placement in cell " + std::to_string(key));
      i.scale = {scale, scale, scale};
      int bx  = std::clamp(int((i.position.x - bounds.min.x) / (Cell / 4)), 0, 3);
      int bz  = std::clamp(int((i.position.z - bounds.min.z) / (Cell / 4)), 0, 3);
      result->buckets[bz * 4 + bx].push_back(p);
    }
    result->terrain = load_(root_ / (std::to_string(key) + ".glb"));
    if (!result->terrain)
      throw std::runtime_error("missing terrain " + std::to_string(key));
    return result;
  }

public:
  World(std::filesystem::path root, Load load)
      : landscape(root), root_(std::move(root)), load_(std::move(load))
  {
    std::ifstream file(root_ / "world.txt");
    std::string   version;
    int           extent = 0, grid = 0, cell = 0;
    if (!(file >> version >> extent >> grid >> cell) || version != "ALLOY3D_WORLD_V2" ||
        extent != Extent || grid != Grid || cell != Cell)
      throw std::runtime_error("invalid world manifest");
    const char *names[] = {"oak",
                           "pine",
                           "cottage",
                           "farmhouse",
                           "rock",
                           "oak_low",
                           "pine_low",
                           "cottage_low",
                           "farmhouse_low",
                           "rock_low"};
    for (unsigned i = 0; i < Assets; ++i)
      shared_[i] = load_(root_ / (std::string(names[i]) + ".glb"));
    grass_      = load_(root_ / "grass.glb");
    river_      = load_(root_ / "river.glb");
    structures_ = load_(root_ / "structures.glb");
    paths_      = load_(root_ / "paths.glb");
    if (!grass_ || !river_ || !structures_ || !paths_)
      throw std::runtime_error("missing landscape assets");
    for (unsigned i = 0; i < Count; ++i)
      far_[i] = load_(root_ / (std::to_string(i) + "_far.glb"));
    if (std::any_of(shared_.begin(), shared_.end(), [](const auto &p) { return !p; }) ||
        std::any_of(far_.begin(), far_.end(), [](const auto &p) { return !p; }))
      throw std::runtime_error("missing shared/far world assets");
    stream_ = std::make_unique<Stream>([this](unsigned key) { return LoadChunk(key); }, 4);
  }
  ~World() { stream_.reset(); }
  void Update(simd_float3 eye, float dt)
  {
    eye_ = eye;
    schedulingTime_ += dt;
    // Spatial scheduling at 10 Hz; ready work is integrated every frame (one cell max).
    if (first_ || schedulingTime_ >= .1f)
    {
      desired_.clear();
      first_          = false;
      schedulingTime_ = 0;
      for (unsigned i = 0; i < Count; ++i)
        if (Distance(i, eye) < 600 || (stream_->Find(i) && Distance(i, eye) < 800))
          desired_.push_back(i);
      std::sort(desired_.begin(),
                desired_.end(),
                [&](unsigned a, unsigned b) { return Distance(a, eye) < Distance(b, eye); });
    }
    stream_->Update(desired_, 1);
    simd_int2 cell{int(eye.x / 3), int(eye.z / 3)};
    if (simd_any(cell != grassCell_))
    {
      grassCell_ = cell;
      grassInstances_.clear();
      for (int z = cell.y - 23; z <= cell.y + 23; ++z)
        for (int x = cell.x - 23; x <= cell.x + 23; ++x)
        {
          uint32_t hash = uint32_t(x) * 73856093u ^ uint32_t(z) * 19349663u;
          hash ^= hash >> 13;
          hash *= 1274126177u;
          const float px = x * 3.f + float(hash & 255) / 255 * 2,
                      pz = z * 3.f + float((hash >> 8) & 255) / 255 * 2;
          if (!landscape.GrassAllowed(px, pz) || !ClearObjects(px, pz, 1.2f, true))
            continue;
          alloy3d::ModelInstance plant;
          plant.position   = {px, landscape.Ground(px, pz) - .04f, pz};
          plant.rotation.y = float((hash >> 16) & 255) / 255 * 6.2831853f;
          float scale      = .7f + float((hash >> 24) & 255) / 255 * .6f;
          plant.scale      = {scale, scale, scale};
          grassInstances_.push_back(plant);
        }
    }
  }
  template <class Submit> void Draw(const alloy3d::CameraData &camera, Submit submit)
  {
    frame = {};
    for (auto &batch : batches_)
      batch.clear();
    const alloy3d::Frustum3D     frustum(camera);
    const alloy3d::ModelInstance identity;
    for (unsigned key = 0; key < Count; ++key)
    {
      auto       chunk    = stream_->Find(key);
      const bool detailed = chunk && Distance(key, eye_) < 450;
      const auto bounds   = CellBounds(key);
      const bool visible  = frustum.intersects(bounds);
      if (visible)
      {
        submit(detailed ? chunk->terrain : far_[key],
               std::span(&identity, 1),
               alloy3d::ModelVisibility3D{true, false},
               Solid);
        if (detailed)
          ++frame.detailCells;
        else
          ++frame.farCells;
      }
      if (!detailed)
        continue;
      for (unsigned b = 0; b < 16; ++b)
      {
        auto box = bounds;
        box.min.x += (b % 4) * (Cell / 4);
        box.min.z += (b / 4) * (Cell / 4);
        box.max.x = box.min.x + Cell / 4;
        box.max.z = box.min.z + Cell / 4;
        // Bounds include maximum crown overhang. Shadow-only buckets remain submitted.
        box.min -= simd_float3{12, 0, 12};
        box.max += simd_float3{12, 0, 12};
        const bool  show   = visible && frustum.intersects(box);
        const float dx     = std::max({box.min.x - eye_.x, 0.f, eye_.x - box.max.x});
        const float dz     = std::max({box.min.z - eye_.z, 0.f, eye_.z - box.max.z});
        const bool  shadow = std::hypot(dx, dz) < 180;
        if (!show && !shadow)
          continue;
        for (const auto &p : chunk->buckets[b])
        {
          const float    distance   = simd_length(p.instance.position - eye_);
          const unsigned asset      = p.kind + (distance > 145 ? Kinds : 0);
          const unsigned visibility = show ? (shadow ? 0 : 1) : 2;
          batches_[visibility * Assets + asset].push_back(p.instance);
          ++frame.placements;
        }
      }
    }
    for (unsigned i = 0; i < batches_.size(); ++i)
      if (!batches_[i].empty())
        submit(shared_[i % Assets],
               std::span<const alloy3d::ModelInstance>(batches_[i]),
               alloy3d::ModelVisibility3D{i / Assets != 2, i / Assets != 1},
               i % Kinds < 2 ? Vegetation : Solid);
    submit(paths_, std::span(&identity, 1), alloy3d::ModelVisibility3D{true, false}, Solid);
    submit(structures_, std::span(&identity, 1), alloy3d::ModelVisibility3D{true, true}, Solid);
    submit(river_, std::span(&identity, 1), alloy3d::ModelVisibility3D{true, false}, Water);
    visibleGrass_.clear();
    for (auto plant : grassInstances_)
    {
      const float d = simd_length(plant.position - eye_);
      if (d > 65 || !frustum.intersects({plant.position - simd_float3{2, 1, 2},
                                         plant.position + simd_float3{2, 2, 2}}))
        continue;
      // Scale down over the outer 15m; avoid transparent overdraw and hard pop-in.
      plant.scale.y *= std::clamp((65 - d) / 15, 0.f, 1.f);
      visibleGrass_.push_back(plant);
    }
    if (!visibleGrass_.empty())
      submit(grass_,
             std::span<const alloy3d::ModelInstance>(visibleGrass_),
             alloy3d::ModelVisibility3D{true, false},
             Grass);
  }
  bool ClearObjects(float x, float z, float radius = .35f, bool onlyBuildings = false) const
  {
    const int cx = int(x / Cell), cz = int(z / Cell);
    for (int j = std::max(0, cz - 1); j <= std::min(Grid - 1, cz + 1); ++j)
      for (int i = std::max(0, cx - 1); i <= std::min(Grid - 1, cx + 1); ++i)
        if (const auto chunk = stream_->Find(j * Grid + i))
          for (unsigned b = 0; b < 16; ++b)
          {
            float bx = i * Cell + (b % 4) * Cell / 4, bz = j * Cell + (b / 4) * Cell / 4;
            if (x < bx - 12 || x > bx + Cell / 4 + 12 || z < bz - 12 || z > bz + Cell / 4 + 12)
              continue;
            for (const auto &p : chunk->buckets[b])
            {
              const float dx = x - p.instance.position.x, dz = z - p.instance.position.z,
                          s = p.instance.scale.x;
              if (p.kind == 2 || p.kind == 3)
              {
                float c = std::cos(p.instance.rotation.y), si = std::sin(p.instance.rotation.y);
                if (std::abs(c * dx - si * dz) < 5.4f * s + radius &&
                    std::abs(si * dx + c * dz) < 4.4f * s + radius)
                  return false;
              }
              else if (!onlyBuildings &&
                       std::hypot(dx, dz) < (p.kind == 4 ? 1.15f : .42f) * s + radius)
                return false;
            }
          }
    return true;
  }
  simd_float3 Move(simd_float3 from, simd_float3 delta) const
  {
    const int steps = std::max(1, int(std::ceil(simd_length(delta))));
    delta /= float(steps);
    auto allowed = [&](simd_float3 p)
    {
      float distance = std::hypot(p.x - from.x, p.z - from.z);
      return p.x >= 1 && p.x <= 4999 && p.z >= 1 && p.z <= 4999 && landscape.Dry(p.x, p.z) &&
             std::abs(landscape.WalkHeight(p.x, p.z) - landscape.WalkHeight(from.x, from.z)) <=
                 distance * .9f + .05f &&
             ClearObjects(p.x, p.z);
    };
    for (int i = 0; i < steps; ++i)
    {
      auto p = from + delta;
      if (allowed(p))
        from = p;
      else
      {
        p = from + simd_float3{delta.x, 0, 0};
        if (allowed(p))
          from = p;
        p = from + simd_float3{0, 0, delta.z};
        if (allowed(p))
          from = p;
      }
    }
    from.y = landscape.WalkHeight(from.x, from.z) + 1.8f;
    return from;
  }
  auto        Stats() const { return stream_->Stats(); }
  const auto &Failures() const { return stream_->Failures(); }
  size_t      PlacementBytes() const
  {
    size_t size = landscape.Bytes() + grassInstances_.capacity() * sizeof(alloy3d::ModelInstance);
    for (const auto &[key, c] : stream_->Residents())
      size += c->Bytes();
    return size;
  }
  std::vector<Ptr> Models() const
  {
    std::vector<Ptr> result(far_.begin(), far_.end());
    result.insert(result.end(), shared_.begin(), shared_.end());
    result.insert(result.end(), {grass_, river_, structures_, paths_});
    for (const auto &[key, c] : stream_->Residents())
      result.push_back(c->terrain);
    return result;
  }
};
} // namespace open_world
