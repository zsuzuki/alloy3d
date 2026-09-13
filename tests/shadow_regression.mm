#include "render_harness.h"
#include <alloy3d/shadow_camera.h>

static int      Red(uint32_t pixel) { return (pixel >> 16) & 255; }
static uint32_t At(const Pixels &pixels, float x, float y = 0)
{
  return pixels[int((1 - y / 2) * 128) * 256 + int((x / 2 + 1) * 128)];
}
static void Quad(Draw3D *draw, float x, float z, float size = 4)
{
  const float r = size / 2;
  [draw drawTriangle:{x - r, -r, z} p1:{x + r, -r, z} p2:{x + r, r, z} color:{1, 1, 1, 1}];
  [draw drawTriangle:{x - r, -r, z} p1:{x + r, r, z} p2:{x - r, r, z} color:{1, 1, 1, 1}];
}
static void Model(Draw3D *draw, MetalModel *model, float x = -.3f, float z = 1, float scale = .6f,
                  float alpha = 1)
{
  [draw drawModel:model
         position:{x, 0, z}
         rotation:{0, 0, 0}
            scale:{scale, scale, scale}
            color:{1, 1, 1, alpha}];
}
static void Test(Harness &h, const std::filesystem::path &root)
{
  alloy3d::CameraData camera;
  camera.buildModelView({0, 0, 5}, {0, 0, 0}, {0, 1, 0});
  camera.buildOrthographic(4, 1, .1, 20);
  alloy3d::DirectionalLight3D light;
  light.direction = {.8f, 0, -1};
  light.ambient   = .2f;
  light.diffuse   = .8f;
  [h.draw setDirectionalLight:light];
  alloy3d::DirectionalShadow3D shadow;
  shadow.resolution = 512;
  shadow.bounds     = {{-2, -2, -.2f}, {2, 2, 2}};
  shadow.depthBias  = .002f;
  auto caster = h.Load(root / "single_sided.glb"), mask = h.Load(root / "mask_checker.glb");
  auto blend = h.Load(root / "blend_red.glb"), unlit = h.Load(root / "unlit.glb");
  auto mirrored = h.Load(root / "mirrored_skin.glb");
  auto blendLit = h.Load(root / "blend_lit.glb");
  auto scene    = [&](MetalModel *model, float alpha = 1)
  {
    Quad(h.draw, 0, 0);
    if (model)
      Model(h.draw, model, -.3, 1, .6, alpha);
  };
  auto noShadow = h.Run(camera, [&] { scene(caster); });
  Check([h.draw shadowDrawCallCount] == 0 && [h.draw memoryStats].shadowMapBytes == 4,
        "disabled shadows allocated a map or encoded a pass");
  shadow.enabled = true;
  [h.draw setDirectionalShadow:shadow];
  auto withShadow = h.Run(camera, [&] { scene(caster); });
  std::printf("receiver red: lit=%d shadow=%d\n", Red(At(noShadow, .5)), Red(At(withShadow, .5)));
  Check(Red(At(noShadow, .5)) > 180 && Red(At(withShadow, .5)) >= 48 &&
            Red(At(withShadow, .5)) <= 55,
        "caster did not shadow receiver while preserving ambient");
  Check(std::abs(Red(At(noShadow, 1.5, 1.5)) - Red(At(withShadow, 1.5, 1.5))) <= 2,
        "unshadowed floor changed or self-shadow acne");
  Check([h.draw shadowDrawCallCount] == 2, "primitive and model shadow draw count incorrect");
  auto softSettings         = shadow;
  softSettings.filterRadius = 2;
  [h.draw setDirectionalShadow:softSettings];
  auto soft = h.Run(camera, [&] { scene(caster); });
  Check(soft != withShadow, "PCF filter did not change shadow edges");
  size_t hardEdges = 0, softEdges = 0;
  for (int y = 102; y < 154; ++y)
    for (int x = 145; x < 188; ++x)
    {
      int a = Red(withShadow[y * 256 + x]), b = Red(soft[y * 256 + x]);
      hardEdges += a > 60 && a < 185;
      softEdges += b > 60 && b < 185;
    }
  Check(softEdges > hardEdges, "PCF did not broaden shadow transition");
  Check(std::abs(Red(At(soft, .5)) - Red(At(withShadow, .5))) <= 2,
        "PCF lightened shadow interior");
  [h.draw setDirectionalShadow:shadow];
  Check(withShadow == h.Run(camera, [&] { scene(caster); }),
        "disabling PCF did not restore baseline");

  auto shadowOnly = h.Run(camera,
                          [&]
                          {
                            Quad(h.draw, 0, 0);
                            [h.draw setModelVisibility:(alloy3d::ModelVisibility3D{false, true})];
                            Model(h.draw, caster);
                            [h.draw setModelVisibility:alloy3d::ModelVisibility3D{}];
                          });
  Check([h.draw modelDrawCallCount] == 0 && Red(At(shadowOnly, .5)) < 60,
        "hidden proxy did not cast a shadow");
  auto noCast = h.Run(camera,
                      [&]
                      {
                        Quad(h.draw, 0, 0);
                        [h.draw setModelVisibility:(alloy3d::ModelVisibility3D{true, false})];
                        Model(h.draw, caster);
                        [h.draw setModelVisibility:alloy3d::ModelVisibility3D{}];
                      });
  Check(noCast == noShadow, "visible noncaster changed color or cast shadow");
  auto primitive = h.Run(camera,
                         [&]
                         {
                           Quad(h.draw, 0, 0);
                           Quad(h.draw, -.3, 1, .6);
                         });
  Check(Red(At(primitive, .5)) <= 55, "primitive did not cast shadow");
  auto flipped = h.Run(camera, [&] { scene(mirrored); });
  Check(Red(At(flipped, .5)) <= 55, "mirrored skin did not cast shadow");
  auto   holes        = h.Run(camera, [&] { scene(mask); });
  size_t holesVisible = 0, covered = 0;
  for (int y = 111; y < 145; ++y)
    for (int x = 148; x < 178; ++x)
    {
      holesVisible += Red(holes[y * 256 + x]) - Red(withShadow[y * 256 + x]) > 80;
      covered += Red(holes[y * 256 + x]) < 70;
    }
  Check(holesVisible > 30 && covered > 30, "MASK did not preserve holes in shadow");
  for (auto model : {blend, unlit})
  {
    auto pixels = h.Run(camera, [&] { scene(model); });
    if (model == blend)
      Check(Red(At(pixels, .5)) > 180, "BLEND unexpectedly cast opaque shadow");
    else
      Check(Red(At(pixels, .5)) < 60, "opaque unlit did not cast shadow");
  }
  Check(Red(At(h.Run(camera, [&] { scene(caster, .5); }), .5)) > 180,
        "faded model cast opaque shadow");
  auto litReceiver = h.Run(camera,
                           [&]
                           {
                             Model(h.draw, caster, 0, 0, 4);
                             Model(h.draw, caster);
                           });
  Check(Red(At(litReceiver, .5)) >= 8 && Red(At(litReceiver, .5)) <= 13,
        "model did not receive shadow");
  auto unlitReceiver = h.Run(camera,
                             [&]
                             {
                               Model(h.draw, unlit, 0, 0, 4);
                               Model(h.draw, caster);
                             });
  Check(std::abs(Red(At(unlitReceiver, .5)) - 51) <= 2, "unlit material received shadow");

  auto blendedReceiver = h.Run(camera,
                               [&]
                               {
                                 Model(h.draw, blendLit, 0, 0, 4);
                                 Model(h.draw, caster);
                               });
  Check(Red(At(blendedReceiver, .5)) >= 23 && Red(At(blendedReceiver, .5)) <= 28,
        "lit BLEND material did not receive shadow");
  auto outside   = shadow;
  outside.bounds = {{10, 10, 10}, {11, 11, 11}};
  [h.draw setDirectionalShadow:outside];
  Check(noShadow == h.Run(camera, [&] { scene(caster); }), "outside shadow frustum was darkened");
  [h.draw setDirectionalShadow:shadow];
  auto originalCamera = camera;
  camera.buildModelView({3, 2, 5}, {0, 0, 0}, {0, 1, 0});
  camera.buildPerspective(.9, 1, .1, 20);
  auto viewed = h.Run(camera, [&] { scene(caster); });
  auto clip   = simd_mul(camera.getProjectionMatrix(),
                         simd_mul(camera.getModelViewMatrix(), simd_make_float4(.5, 0, 0, 1)));
  auto sample = viewed[int((1 - clip.y / clip.w) * 128) * 256 + int((clip.x / clip.w + 1) * 128)];
  Check(Red(sample) >= 48 && Red(sample) <= 60, "shadow moves with perspective camera");
  camera = originalCamera;

  std::array<Instance, 2> placements;
  placements[0].position = {-.7f, 0, 1};
  placements[1].position = {.5f, 0, 1};
  placements[0].scale    = {.4f, .4f, .4f};
  placements[1].scale    = {-.4f, .4f, .4f};
  auto scalar            = h.Run(camera,
                                 [&]
                                 {
                        Quad(h.draw, 0, 0);
                        for (const auto &i : placements)
                          [h.draw drawModel:caster
                                   position:i.position
                                   rotation:i.rotation
                                      scale:i.scale
                                      color:i.color];
                                 });
  auto batched           = h.Run(camera,
                                 [&]
                                 {
                         Quad(h.draw, 0, 0);
                         [h.draw drawModelInstances:caster instances:placements];
                                 });
  Check(scalar == batched, "instance shadow differs from individual shadow");
  Check([h.draw shadowDrawCallCount] == 2, "shadow pass lost instancing");

  auto animated = h.Load(root / "animated_caster.glb");
  [animated setAnimationIndex:0];
  [animated setAnimationTime:0];
  auto clone = [animated newInstance];
  auto first = h.Run(camera, [&] { scene(animated); });
  [animated setAnimationTime:1];
  auto next = h.Run(camera, [&] { scene(animated); });
  Check(first != next, "animated caster shadow did not move");
  Check(first == h.Run(camera, [&] { scene(clone); }), "clone shadow shares mutable pose");
  [animated release];
  Check(first == h.Run(camera, [&] { scene(clone); }),
        "shadow lost resources after source release");
  [clone release];

  // Invalid inputs keep the previous lighting/shadow setup intact.
  auto reference = h.Run(camera, [&] { scene(caster); });
  for (int test = 0; test < 5; ++test)
  {
    bool rejected = false;
    try
    {
      if (test < 3)
      {
        auto invalid = shadow;
        if (test == 0)
          invalid.resolution = 0;
        if (test == 1)
          invalid.bounds = {};
        if (test == 2)
          invalid.depthBias = NAN;
        [h.draw setDirectionalShadow:invalid];
      }
      else
      {
        auto invalid = light;
        if (test == 3)
          invalid.direction = {0, 0, 0};
        else
          invalid.color.x = INFINITY;
        [h.draw setDirectionalLight:invalid];
      }
    }
    catch (const std::invalid_argument &)
    {
      rejected = true;
    }
    Check(rejected, "invalid lighting settings accepted");
    Check(reference == h.Run(camera, [&] { scene(caster); }),
          "rejected settings changed rendered result");
  }
  light.color = {1, 0, 0};
  [h.draw setDirectionalLight:light];
  auto colored = At(h.Run(camera, [&] { scene(caster); }), 1.5);
  Check(Red(colored) > 180 && std::abs(int((colored >> 8) & 255) - 51) <= 2 &&
            std::abs(int(colored & 255) - 51) <= 2,
        "directional light RGB not applied independently of ambient");
  light.color = {1, 1, 1};
  [h.draw setDirectionalLight:light];

  shadow.resolution = 128;
  [h.draw setDirectionalShadow:shadow];
  std::array<Pixels, 3> expected;
  for (int slot = 0; slot < 3; ++slot)
    expected[slot] = h.Run(camera,
                           [&]
                           {
                             Quad(h.draw, 0, 0);
                             Model(h.draw, caster, -.5f + .3f * slot);
                           });
  Check([h.draw memoryStats].shadowMapBytes == 4 + 3 * 128 * 128 * 4,
        "shadow maps did not resize across all pages");
  // Three submitted frames must retain different depth maps and pose buffers.
  for (int slot = 0; slot < 3; ++slot)
  {
    h.Begin(slot);
    Quad(h.draw, 0, 0);
    Model(h.draw, caster, -.5f + .3f * slot);
    h.Encode(slot, camera);
    [h.commands[slot] commit];
  }
  for (int slot = 0; slot < 3; ++slot)
    Check(expected[slot] == h.Read(slot), "in-flight shadow map overwritten");
  // Depth-only work still consumes a frame page if the color pass is discarded.
  h.Begin(0);
  scene(caster);
  h.commands[0] = [[h.queue commandBuffer] retain];
  [h.draw encodeShadowMap:h.commands[0] camera:&camera];
  [h.draw discardFrame];
  [h.commands[0] commit];
  for (int n = 0; n < 3; ++n)
    h.Run(camera, [&] { scene(caster); });
  shadow.enabled = false;
  [h.draw setDirectionalShadow:shadow];
  for (int n = 0; n < 3; ++n)
  {
    auto disabled = h.Run(camera, [&] { scene(caster); });
    Check(disabled == noShadow, "disabling shadow did not restore original rendering");
    Check([h.draw shadowDrawCallCount] == 0, "disabled shadow still draws");
  }
  Check([h.draw memoryStats].shadowMapBytes == 4 && ![h.draw memoryStats].releasePending,
        "disabled shadow maps not released after safe reuse");
  // A coarse map must not stripe a grazing receiver with its own shadow.
  auto tilted = [&]
  {
    [h.draw drawTriangle:{-1, -1, -.6f} p1:{1, -1, .6f} p2:{1, 1, .6f} color:{1, 1, 1, 1}];
    [h.draw drawTriangle:{-1, -1, -.6f} p1:{1, 1, .6f} p2:{-1, 1, -.6f} color:{1, 1, 1, 1}];
  };
  auto withoutSelfShadow = h.Run(camera, tilted);
  shadow.enabled         = true;
  shadow.resolution      = 64;
  shadow.depthBias       = 0;
  shadow.bounds          = {{-2, -2, -1}, {2, 2, 2}};
  [h.draw setDirectionalShadow:shadow];
  auto slopeBiased = h.Run(camera, tilted);
  for (int y = 85; y < 170; ++y)
    for (int x = 85; x < 170; ++x)
      Check(std::abs(Red(slopeBiased[y * 256 + x]) - Red(withoutSelfShadow[y * 256 + x])) <= 3,
            "slope bias failed to suppress self-shadow stripes");
  for (auto model : {caster, mask, blend, unlit, mirrored, blendLit})
    [model release];
  std::puts("shadows: cast/receive, mask, fade, unlit, mirrored skin, instances, animated clone, "
            "RGB, validation, resize, in-flight pages and disable passed");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3 || (argc == 4 && std::string_view(argv[3]) == "--custom-surface"),
            "usage: shadow_regression shaders.metallib material-fixtures");
      alloy3d::DirectionalShadow3D stable;
      stable.resolution = 512;
      stable.stabilize  = true;
      auto original     = alloy3d::BuildDirectionalShadowCamera3D(stable, {0, 0, -1});
      stable.bounds.min.x += .0001f;
      stable.bounds.max.x += .0001f;
      auto shifted = alloy3d::BuildDirectionalShadowCamera3D(stable, {0, 0, -1});
      auto a       = simd_mul(original.getProjectionMatrix(), original.getModelViewMatrix());
      auto b       = simd_mul(shifted.getProjectionMatrix(), shifted.getModelViewMatrix());
      for (int col = 0; col < 4; ++col)
        Check(simd_all(simd_abs(a.columns[col] - b.columns[col]) < 1e-6f),
              "subtexel motion changed stabilized shadow");
      stable.filterRadius = NAN;
      bool rejected       = false;
      try
      {
        alloy3d::BuildDirectionalShadowCamera3D(stable, {0, 0, -1});
      }
      catch (const std::invalid_argument &)
      {
        rejected = true;
      }
      Check(rejected, "invalid PCF radius accepted");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness h(device, argv[1]);
        if (argc == 4)
        {
          std::string diagnostics;
          auto        shader = [h.draw
              createModelShader:
                  "float3 alloy3dShade(ModelSurface s, float4 p) { return s.unlit ? s.baseColor : "
                  "s.baseColor * (s.ambient + s.diffuse * s.shadow * s.lightColor); }"
                    diagnostics:diagnostics];
          if (!shader)
            throw std::runtime_error(diagnostics);
          Check([h.draw setModelShader:shader parameters:{0, 0, 0, 0}], "shader rejected");
        }
        Test(h, argv[2]);
      }
      [device release];
      return 0;
    }
    catch (const std::exception &e)
    {
      std::fprintf(stderr, "FAIL: %s\n", e.what());
      return 1;
    }
  }
}
