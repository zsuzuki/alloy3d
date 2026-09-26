#include "world.h"
#include "materials.h"
#include <alloy3d/application.h>
#include <alloy3d/keyboard.h>
#import <AppKit/AppKit.h>
#include <mach/mach.h>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <iostream>

class OpenWorldLoop final : public alloy3d::ApplicationLoop
{
  using Clock = std::chrono::steady_clock;
  std::unique_ptr<open_world::World<alloy3d::Model>> world_;
  alloy3d::ModelShaderPtr                            riverShader_, grassShader_;
  float                                              tourDistance_ = 0;
  std::array<bool, 256>                              keys_{};
  simd_float3                                        eye_{1250, 0, 1100};
  float             yaw_ = 1.5707963f, pitch_ = -.06f, width_ = 1280, height_ = 800, elapsed_ = 0,
                    statsTime_ = 1;
  bool              tour_ = false, map_ = true;
  Clock::time_point previous_;
  alloy3d::ModelResourceStats resources_;
  uint64_t                    footprint_ = 0, peak_ = 0;
  std::ofstream               csv_;
  unsigned                    frames_ = 0, frameLimit_ = 0;

public:
  const char *GetApplicationName() const override { return "Alloy3D · Open world / 5 km"; }
  alloy3d::RenderOptions GetRenderOptions() const override { return {2, false, false}; }
  bool                   InitialWindowSize(double &w, double &h, bool &border) override
  {
    w      = width_;
    h      = height_;
    border = true;
    return true;
  }
  void ResizeWindow(double w, double h) override
  {
    width_  = w;
    height_ = h;
  }
  void WindowClearColor(double &r, double &g, double &b, double &a) override
  {
    r = .48;
    g = .66;
    b = .79;
    a = 1;
  }
  void Start(alloy3d::ApplicationContext &ctx) override
  {
    std::filesystem::path root;
    if (const char *path = std::getenv("ALLOY3D_WORLD_ASSETS"))
      root = path;
    else
      root = std::filesystem::path([[[NSBundle mainBundle] resourceURL] fileSystemRepresentation]) /
             "open-world";
    auto loader = ctx.CreateModelLoader();
    if (!loader)
      throw std::runtime_error("background model loading is unsupported");
    world_ = std::make_unique<open_world::World<alloy3d::Model>>(
        root,
        [loader](const auto &path)
        {
          auto model = loader(path.string());
          return model && model->IsLoaded() ? model : nullptr;
        });
    eye_ = world_->landscape.Spawn();
    std::string error;
    riverShader_ = ctx.CreateModelMaterialShader(open_world::RiverMaterial, error);
    if (!riverShader_)
      std::cerr << "River material: " << error << '\n';
    grassShader_ = ctx.CreateModelShader(open_world::GrassSurface, error);
    if (!grassShader_)
      std::cerr << "Grass material: " << error << '\n';
    ctx.SetModelTextureSampling3D({4, true});
    ctx.SetFrustumCulling3D(true);
    ctx.SetShadowCulling3D(true);
    ctx.SetDirectionalLight3D({{-.5f, -1, .3f}, {1, .96f, .86f}, .3f, .8f});
    ctx.SetHemisphereLight3D({true, {.7f, .82f, 1}, {.25f, .3f, .15f}, {0, 1, 0}, .3f});
    ctx.SetFog3D({true, {.48f, .66f, .79f}, 2000, 6000});
    ctx.SetTextFontSize(16);
    if (const char *path = std::getenv("ALLOY3D_WORLD_CSV"))
    {
      csv_.open(path);
      csv_ << "seconds,x,z,resident,pending,failed,loaded,evicted,model_buffer_bytes,model_texture_"
              "bytes,placement_bytes,renderer_bytes,footprint_bytes,peak_footprint_bytes\n";
    }
    if (const char *value = std::getenv("ALLOY3D_WORLD_FRAMES"))
      frameLimit_ = std::strtoul(value, nullptr, 10);
    tour_     = std::getenv("ALLOY3D_WORLD_TOUR") != nullptr;
    previous_ = Clock::now();
  }
  void WillCloseWindow() override
  {
    world_.reset();
    riverShader_.reset();
    grassShader_.reset();
    if (csv_)
      csv_.flush();
  }
  void Update(alloy3d::ApplicationContext &ctx) override
  {
    using Key = alloy3d::keyboard::KeyCode;
    alloy3d::keyboard::Fetch(
        [&](Key key, bool down)
        {
          auto i = size_t(key);
          if (i >= keys_.size())
            return;
          bool pressed = down && !keys_[i];
          keys_[i]     = down;
          if (pressed && key == Key::T)
          {
            tour_ = !tour_;
            if (tour_)
              tourDistance_ = 0;
          }
          if (pressed && key == Key::M)
            map_ = !map_;
          if (pressed && key == Key::R)
          {
            eye_  = world_->landscape.Spawn();
            yaw_  = 1.5707963f;
            tour_ = false;
          }
        });
    auto  now = Clock::now();
    float dt  = std::clamp(std::chrono::duration<float>(now - previous_).count(), 0.f, .1f);
    previous_ = now;
    elapsed_ += dt;
    auto held = [&](Key key) { return keys_[size_t(key)] ? 1.f : 0.f; };
    if (tour_)
    {
      tourDistance_ += dt * 100;
      eye_ = world_->landscape.Tour(tourDistance_, yaw_);
    }
    else
    {
      yaw_ += (held(Key::RIGHT) - held(Key::LEFT)) * dt;
      pitch_ = std::clamp(pitch_ + (held(Key::UP) - held(Key::DOWN)) * dt * .5f, -.8f, .6f);
      float       speed = held(Key::LSHT) ? 100 : 12;
      simd_float3 delta{std::sin(yaw_) * (held(Key::W) - held(Key::S)) +
                            std::cos(yaw_) * (held(Key::D) - held(Key::A)),
                        0,
                        -std::cos(yaw_) * (held(Key::W) - held(Key::S)) +
                            std::sin(yaw_) * (held(Key::D) - held(Key::A))};
      if (simd_length_squared(delta) > 1)
        delta = simd_normalize(delta);
      eye_ = world_->Move(eye_, delta * speed * dt);
    }
    eye_.y       = world_->landscape.WalkHeight(eye_.x, eye_.z) + 1.8f;
    auto &camera = ctx.GetCamera();
    camera.buildPerspective(.95f, width_ / std::max(1.f, height_), .25f, 7500);
    camera.buildModelView(
        eye_, eye_ + simd_float3{std::sin(yaw_), std::sin(pitch_), -std::cos(yaw_)}, {0, 1, 0});
    alloy3d::DirectionalShadow3D shadow;
    shadow.enabled    = true;
    shadow.resolution = 1024;
    shadow.bounds     = {eye_ - simd_float3{180, 45, 180}, eye_ + simd_float3{180, 65, 180}};
    shadow.stabilize  = true;
    ctx.SetDirectionalShadow3D(shadow);
    world_->Update(eye_, dt);
    world_->Draw(camera,
                 [&](auto model, auto placements, auto visibility, auto style)
                 {
                   using World      = open_world::World<alloy3d::Model>;
                   const bool grass = style == World::Grass, tree = style == World::Vegetation;
                   ctx.SetModelWind3D({grass  ? .12f
                                       : tree ? .15f
                                              : 0.f,
                                       elapsed_,
                                       {1, .4f},
                                       grass ? 0.f : 3.f,
                                       grass ? .8f : 14.f,
                                       1.3f});
                   ctx.SetModelShader(style == World::Water ? riverShader_
                                      : grass               ? grassShader_
                                                            : nullptr,
                                      {elapsed_, 0, 0, 0});
                   ctx.SetModelHighlight3D({style == World::Water ? .55f : 0.f, 80});
                   ctx.SetModelVisibility3D(visibility);
                   ctx.DrawModelInstances3D(model, placements);
                 });
    ctx.SetModelVisibility3D({});
    ctx.SetModelWind3D({});
    ctx.SetModelShader(nullptr);
    ctx.SetModelHighlight3D({});
    auto s = world_->Stats();
    statsTime_ += dt;
    auto   r        = ctx.GetRenderMemoryStats();
    size_t renderer = r.vertexBufferBytes + r.instanceBufferBytes + r.shadowMapBytes +
                      r.textBitmapCacheBytes + r.textTextureCacheBytes + r.postProcessBytes;
    if (statsTime_ >= .5f)
    {
      statsTime_ = 0;
      resources_ = ctx.GetModelResourceStats(world_->Models());
      task_vm_info_data_t    info{};
      mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
      if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS)
        footprint_ = info.phys_footprint;
      peak_ = std::max(peak_, footprint_);
      if (csv_)
        csv_ << elapsed_ << ',' << eye_.x << ',' << eye_.z << ',' << s.resident << ',' << s.pending
             << ',' << s.failed << ',' << s.loaded << ',' << s.evicted << ','
             << resources_.bufferBytes << ',' << resources_.textureBytes << ','
             << world_->PlacementBytes() << ',' << renderer << ',' << footprint_ << ',' << peak_
             << '\n';
    }
    constexpr double MiB   = 1024 * 1024;
    float            scale = ctx.ContentScale();
    char             text[512];
    ctx.FillRect(
        {12, 12}, {std::min(width_ / scale - 12, 1050.f), 104}, {.025f, .045f, .065f, .88f});
    ctx.FillRect({12, height_ / scale - 44},
                 {std::min(width_ / scale - 12, 780.f), height_ / scale - 8},
                 {.025f, .045f, .065f, .88f});
    ctx.SetTextColor(1, 1, 1, 1);
    ctx.Print("OPEN WORLD  /  5 x 5 km  /  river valley + villages", 24, 24);
    std::snprintf(
        text,
        sizeof(text),
        "Cell %d,%d | resident %zu / 400 | pending %zu | loaded %llu / evicted %llu | failures %zu",
        int(eye_.x / 250),
        int(eye_.z / 250),
        s.resident,
        s.pending,
        (unsigned long long)s.loaded,
        (unsigned long long)s.evicted,
        s.failed);
    ctx.Print(text, 24, 48);
    std::snprintf(text,
                  sizeof(text),
                  "Models %.1f MiB | renderer %.1f MiB | process %.1f MiB (peak %.1f)",
                  (resources_.bufferBytes + resources_.textureBytes) / MiB,
                  renderer / MiB,
                  footprint_ / MiB,
                  peak_ / MiB);
    ctx.Print(text, 24, 72);
    ctx.Print("WASD move | arrows look | Shift drive | T tour | M map | R reset",
              24,
              height_ / scale - 32);
    if (s.failed)
      ctx.Print("Streaming error: " + world_->Failures().begin()->second, 24, 112);
    if (map_)
    {
      float x = width_ / scale - 154, y = height_ / scale - 240;
      // North is -Z. UI coordinates increase downward, so +Z maps to +Y.
      auto mapPoint = [=](float worldX, float worldZ) -> simd_float2
      { return {x + worldX / open_world::Extent * 120, y + worldZ / open_world::Extent * 120}; };
      ctx.FillRect({x - 24, y - 26}, {x + 146, y + 148}, {.025f, .045f, .065f, .88f});
      ctx.Print("N", x + 55, y - 23);
      ctx.Print("S", x + 55, y + 123);
      ctx.Print("W", x - 20, y + 50);
      ctx.Print("E", x + 125, y + 50);
      for (unsigned key = 0; key < open_world::Count; ++key)
      {
        bool near   = open_world::Distance(key, eye_) < 450;
        auto bounds = open_world::CellBounds(key);
        ctx.FillRect(mapPoint(bounds.min.x, bounds.min.z),
                     mapPoint(bounds.max.x, bounds.max.z) - simd_float2{1, 1},
                     {near ? .2f : .08f, near ? .65f : .2f, .22f, .8f});
      }
      for (size_t i = 1; i < world_->landscape.river.size(); ++i)
      {
        const auto a = world_->landscape.river[i - 1], b = world_->landscape.river[i];
        ctx.DrawLine(mapPoint(a.x, a.z), mapPoint(b.x, b.z), {.3f, .7f, .9f, 1});
      }
      for (const auto &b : world_->landscape.bridges)
        ctx.DrawLine(
            mapPoint(b.x - b.halfSpan, b.z), mapPoint(b.x + b.halfSpan, b.z), {1, .9f, .65f, 1});
      const auto        point = mapPoint(eye_.x, eye_.z);
      const simd_float2 forward{std::sin(yaw_), -std::cos(yaw_)};
      const simd_float2 right{std::cos(yaw_), std::sin(yaw_)};
      const auto        tip = point + forward * 12;
      const simd_float4 color{1, .7f, .2f, 1};
      ctx.FillRect(point - simd_float2{2, 2}, point + simd_float2{2, 2}, color);
      ctx.DrawLine(point, tip, color);
      ctx.DrawLine(tip, tip - forward * 5 + right * 4, color);
      ctx.DrawLine(tip, tip - forward * 5 - right * 4, color);
    }
    if (frameLimit_ && ++frames_ >= frameLimit_)
      dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
      });
  }
};
int main()
{
  alloy3d::LaunchApplication(std::make_shared<OpenWorldLoop>());
  return 0;
}
