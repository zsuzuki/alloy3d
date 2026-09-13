#include "scene.h"
#include <alloy3d/application.h>
#include <alloy3d/keyboard.h>
#include <chrono>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>

class ForestLoop final : public alloy3d::ApplicationLoop
{
  forest::Scene                                                            scene_;
  std::array<alloy3d::ApplicationContext::ModelPtr, forest::Assets.size()> models_;
  alloy3d::ModelShaderPtr               groundShader_, leafShader_, waterShader_;
  std::array<bool, 256>                 keys_{};
  std::chrono::steady_clock::time_point previous_;
  float                                 width_ = 1440, height_ = 900;
  bool                                  environmentDirty_ = true;

public:
  const char *GetApplicationName() const override { return "Alloy3D · Forest after rain"; }
  alloy3d::RenderOptions GetRenderOptions() const override { return {4}; }
  bool        InitialWindowSize(double &width, double &height, bool &border) override
  {
    width  = width_;
    height = height_;
    border = true;
    return true;
  }
  void ResizeWindow(double width, double height) override
  {
    width_  = width;
    height_ = height;
  }
  void WindowClearColor(double &r, double &g, double &b, double &a) override
  {
    r = forest::SkyColor.x;
    g = forest::SkyColor.y;
    b = forest::SkyColor.z;
    a = 1;
  }
  void Start(alloy3d::ApplicationContext &ctx) override
  {
    ctx.SetModelTextureSampling3D({8,true});
    ctx.SetTransparentBatching3D(true);
    ctx.SetFrustumCulling3D(true);
    for (size_t i = 0; i < models_.size(); ++i)
    {
      models_[i] = ctx.LoadModel(std::string("forest/") + forest::Assets[i] + ".glb");
      if (!models_[i] || !models_[i]->IsLoaded())
        throw std::runtime_error(std::string("Forest asset failed to load: ") + forest::Assets[i]);
    }
    std::string error;
    groundShader_ = ctx.CreateModelShader(forest::GroundShader, error);
    if (!groundShader_)
      std::cerr << "Forest ground shader: " << error << '\n';
    leafShader_ = ctx.CreateModelShader(forest::LeafShader, error);
    if (!leafShader_)
      std::cerr << "Forest leaf shader: " << error << '\n';
    waterShader_ = ctx.CreateModelMaterialShader(forest::WaterShader, error);
    if (!waterShader_)
      std::cerr << "Forest water shader: " << error << '\n';
    // Keep one font size so the host can retain the text bitmap cache.
    ctx.SetTextFontSize(16);
    previous_ = std::chrono::steady_clock::now();
  }
  void WillCloseWindow() override
  {
    for (auto &model : models_)
      model.reset();
    groundShader_.reset();
    leafShader_.reset();
    waterShader_.reset();
  }
  void Update(alloy3d::ApplicationContext &ctx) override
  {
    using Key = alloy3d::keyboard::KeyCode;
    alloy3d::keyboard::Fetch(
        [&](Key key, bool down)
        {
          size_t i = static_cast<size_t>(key);
          if (i >= keys_.size())
            return;
          bool pressed = down && !keys_[i];
          keys_[i]     = down;
          if (!pressed)
            return;
          auto &s = scene_.settings;
          switch (key)
          {
          case Key::N: s.normalMaps = !s.normalMaps; break;
          case Key::M: s.materialDetail = !s.materialDetail; break;
          case Key::T: s.transmission = !s.transmission; break;
          case Key::K: s.softShadows = !s.softShadows; environmentDirty_ = true; break;
          case Key::J: s.heightFog = !s.heightFog; environmentDirty_ = true; break;
          case Key::G:
            s.fog             = !s.fog;
            environmentDirty_ = true;
            break;
          case Key::H:
            s.shadows         = !s.shadows;
            environmentDirty_ = true;
            break;
          case Key::B:
            s.shafts = !s.shafts;
            break;
          case Key::V:
            s.wind = !s.wind;
            break;
          case Key::I:
            s.billboards = !s.billboards;
            break;
          case Key::F:
            s.flow = !s.flow;
            break;
          case Key::P:
            s.droplets = !s.droplets;
            break;
          case Key::SPC:
            s.paused = !s.paused;
            break;
          case Key::TAB:
            s.hud = !s.hud;
            break;
          case Key::R:
            scene_.yaw    = 0;
            scene_.pitch  = .045f;
            scene_.travel = 0;
            break;
          default:
            break;
          }
        });
    auto  now = std::chrono::steady_clock::now();
    float dt  = std::clamp(std::chrono::duration<float>(now - previous_).count(), 0.f, .05f);
    previous_ = now;
    auto held = [&](Key key) { return keys_[static_cast<size_t>(key)] ? 1.f : 0.f; };
    scene_.yaw =
        std::clamp(scene_.yaw + (held(Key::RIGHT) - held(Key::LEFT)) * dt * .35f, -.7f, .7f);
    scene_.pitch =
        std::clamp(scene_.pitch + (held(Key::UP) - held(Key::DOWN)) * dt * .25f, -.15f, .4f);
    scene_.travel = std::clamp(scene_.travel + (held(Key::W) - held(Key::S)) * dt * 2.f, 0.f, 8.f);
    scene_.Camera(ctx.GetCamera(), std::max(width_, 1.f) / std::max(height_, 1.f));
    if (environmentDirty_)
    {
      ctx.SetDirectionalLight3D(scene_.Light());
      ctx.SetHemisphereLight3D(scene_.Ambient());
      ctx.SetFog3D(scene_.Fog());
      ctx.SetHeightFog3D(scene_.HeightFog());
      ctx.SetDirectionalShadow3D(scene_.Shadow());
      environmentDirty_ = false;
    }
    scene_.Animate(scene_.time + (scene_.settings.paused ? 0 : dt),
                   ctx.GetCamera().getEyePosition());
    ctx.SetModelNormalMapping3D({scene_.settings.normalMaps ? 1.f : 0.f});
    scene_.Draw(
        [&](size_t asset, std::span<const alloy3d::ModelInstance> instances)
        {
          ctx.SetModelWind3D(scene_.Wind(asset));
          ctx.SetModelTextureTransform3D(scene_.TextureTransform(asset));
          ctx.SetModelTransmission3D({scene_.settings.transmission && forest::IsFoliage(asset) ? .45f : 0.f,
                                      {.75f, 1.f, .4f}});
          ctx.SetModelMaterialDetail3D({scene_.settings.materialDetail && (asset == forest::Ground || asset == forest::Rock)});
          ctx.SetModelShader(asset == forest::Water     ? waterShader_
                             : asset == forest::Ground  ? groundShader_
                             : forest::IsFoliage(asset) ? leafShader_
                                                        : nullptr,
                             {asset == forest::Water ? scene_.waterTime : scene_.time,
                              scene_.settings.shafts ? 1.f : 0.f,
                              0,
                              0});
          ctx.SetModelHighlight3D({asset == forest::Water    ? .9f
                                     : asset == forest::Rock     ? .20f
                                   : asset == forest::Ground ? .10f
                                                             : .035f,
                                   48});
          ctx.DrawModelInstances3D(models_[asset], instances);
        });
    ctx.SetModelWind3D({});
    ctx.SetModelTextureTransform3D({});
    ctx.SetModelShader(nullptr);
    ctx.SetModelHighlight3D({});
    if (scene_.settings.hud)
    {
      // Print uses logical points; ResizeWindow reports drawable pixels.
      float scale = std::max(1.f, ctx.ContentScale());
      ctx.SetTextColor(.80f, .91f, .80f, 1);
      ctx.Print("AFTER THE RAIN", 28, 30);
      ctx.SetTextColor(.60f, .73f, .64f, 1);
      ctx.Print("A quiet forest  /  Alloy3D", 29, 62);
      ctx.SetTextColor(.78f, .86f, .77f, 1);
      ctx.Print("Arrows  look    W / S  move    R  reset    Space  pause    Tab  hide",
                28,
                height_ / scale - 62);
      const auto &s = scene_.settings;
      ctx.Print(std::string("V  wind ") + (s.wind ? "on" : "off") + "    G  mist " +
                    (s.fog ? "on" : "off") + "    B  sunlight " + (s.shafts ? "on" : "off") +
                    "    H  shadows " + (s.shadows ? "on" : "off") + "    F  stream " +
                    (s.flow ? "on" : "off") + "    I  billboards " + (s.billboards ? "on" : "off") +
                    "    P  drops " + (s.droplets ? "on" : "off") + (s.paused ? "    PAUSED" : ""),
                28,
                height_ / scale - 38);
    }
  }
};

int main()
{
  alloy3d::LaunchApplication(std::make_shared<ForestLoop>());
  return 0;
}
