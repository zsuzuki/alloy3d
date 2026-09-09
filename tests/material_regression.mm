#include "render_harness.h"
#include <numbers>

static uint32_t Center(const Pixels &pixels) { return pixels[128 * 256 + 128]; }
static void     Color(uint32_t pixel, int r, int g, int b, int a = 255)
{
  for (auto [shift, expected] : {std::pair{0, b}, {8, g}, {16, r}, {24, a}})
    if (std::abs(int((pixel >> shift) & 255) - expected) > 2)
    {
      std::fprintf(stderr, "pixel=%08x expected RGBA=(%d,%d,%d,%d)\n", pixel, r, g, b, a);
      Check(false, "material pixel differs from analytic color");
    }
}
static size_t VisibleCount(const Pixels &pixels)
{
  return std::count_if(pixels.begin(), pixels.end(), [](auto p) { return (p & 0xffffff) != 0; });
}
static void Submit(Harness &h, MetalModel *model, float depth, simd_float4 tint = {1, 1, 1, 1},
                   simd_float3 rotation = {0, 0, 0}, simd_float3 scale = {1, 1, 1})
{
  [h.draw drawModel:model position:{0, 0, depth} rotation:rotation scale:scale color:tint];
}
static void Test(Harness &h, const std::filesystem::path &root)
{
  alloy3d::CameraData camera;
  auto opaque = h.Load(root / "opaque_alpha.glb"), mask = h.Load(root / "mask_checker.glb");
  auto equal = h.Load(root / "mask_equal.glb"), cutoff = h.Load(root / "mask_cutoff.glb");
  auto red = h.Load(root / "blend_red.glb"), blue = h.Load(root / "blend_blue.glb");
  auto parts = h.Load(root / "blend_parts.glb"), lit = h.Load(root / "single_sided.glb");
  auto unlit = h.Load(root / "unlit.glb"), both = h.Load(root / "double_sided.glb");
  Check(opaque.parts[0].alphaMode == 0 && mask.parts[0].alphaMode == 1 &&
            red.parts[0].alphaMode == 2 && both.parts[0].doubleSided && unlit.parts[0].unlit,
        "glTF material metadata lost");
  [h.draw setLightDirection:{0, 0, -1} ambient:0 diffuse:1];
  auto full = h.Run(camera, [&] { Submit(h, opaque, .2); });
  Color(Center(full), 255, 0, 0);
  Check(VisibleCount(full) == 128 * 128, "OPAQUE alpha affected coverage");
  auto holes = h.Run(camera, [&] { Submit(h, mask, .2); });
  Check(VisibleCount(holes) > 3000 && VisibleCount(holes) < 10000, "MASK checker not cut out");
  for (auto p : holes)
    if (p & 0xffffff)
      Color(p, 0, 255, 0);
  Check(VisibleCount(h.Run(camera, [&] { Submit(h, cutoff, .2); })) == 0, "custom cutoff ignored");
  Color(Center(h.Run(camera, [&] { Submit(h, equal, .2); })), 0, 255, 0);
  auto background = h.Run(camera, [&] { Submit(h, unlit, .7); });
  auto covered    = h.Run(camera,
                          [&]
                          {
                         Submit(h, mask, .2);
                         Submit(h, unlit, .7);
                          });
  for (size_t i = 0; i < holes.size(); ++i)
    Check(covered[i] == ((holes[i] & 0xffffff) ? holes[i] : background[i]),
          "MASK discarded pixels wrote depth or accepted pixels lost depth");
  Color(Center(h.Run(camera,
                     [&]
                     {
                       Submit(h, opaque, .2);
                       Submit(h, unlit, .7);
                     })),
        255,
        0,
        0);
  // Explicit placement alpha remains usable as a fade even for OPAQUE materials.
  Color(Center(h.Run(camera, [&] { Submit(h, opaque, .2, simd_make_float4(1, 1, 1, .5)); })),
        128,
        0,
        0,
        128);
  auto reference = h.Run(camera,
                         [&]
                         {
                           Submit(h, red, .2);
                           Submit(h, blue, .7);
                         });
  Color(Center(reference), 128, 0, 64, 191);
  Check(reference == h.Run(camera,
                           [&]
                           {
                             Submit(h, blue, .7);
                             Submit(h, red, .2);
                           }),
        "blend sorting depends on model submission order");
  Color(Center(h.Run(camera, [&] { Submit(h, parts, 0); })), 128, 0, 64, 191);
  Color(Center(h.Run(camera,
                     [&]
                     {
                       Submit(h, red, .2);
                       Submit(h, blue, .7);
                       Submit(h, unlit, .5);
                     })),
        153,
        51,
        77);

  // Probe the depth buffer with an opaque pass after BLEND in the same encoder.
  auto probe = [[Draw3D alloc] initWithMetalKitView:h.view shaderlib:h.library];
  [probe beginFrame];
  [probe drawModel:unlit position:{0, 0, .7} rotation:{0, 0, 0} scale:{1, 1, 1} color:{1, 1, 1, 1}];
  h.Begin(0);
  Submit(h, red, .2);
  h.Encode(0,
           camera,
           [&](id<MTLRenderCommandEncoder> encoder) { [probe render:encoder camera:&camera]; });
  [h.commands[0] commit];
  Color(Center(h.Read(0)), 51, 102, 153);
  [probe release];

  // The back of a one-sided plane disappears; a double-sided plane reverses its normal.
  const auto back = simd_make_float3(0, std::numbers::pi_v<float>, 0);
  Check(VisibleCount(
            h.Run(camera, [&] { Submit(h, lit, .4, simd_make_float4(1, 1, 1, 1), back); })) == 0,
        "single-sided back face visible");
  auto frontLit = h.Run(camera, [&] { Submit(h, both, .4); });
  auto backLit  = h.Run(camera, [&] { Submit(h, both, .4, simd_make_float4(1, 1, 1, 1), back); });
  Color(Center(frontLit), 51, 102, 153);
  Color(Center(backLit), 51, 102, 153);
  for (const char *name : {"single_sided.glb", "mirrored_node.glb", "mirrored_skin.glb"})
  {
    auto model = h.Load(root / name);
    for (float sign : {1.f, -1.f})
      Color(Center(h.Run(camera,
                         [&]
                         {
                           Submit(h,
                                  model,
                                  .4,
                                  simd_make_float4(1, 1, 1, 1),
                                  simd_make_float3(0, 0, 0),
                                  simd_make_float3(sign, 1, 1));
                         })),
            51,
            102,
            153);
    [model release];
  }
  [h.draw setLightDirection:{0, 0, 1} ambient:0 diffuse:0];
  Color(Center(h.Run(camera, [&] { Submit(h, lit, .4); })), 0, 0, 0);
  Color(Center(h.Run(camera, [&] { Submit(h, unlit, .4); })), 51, 102, 153);
  [h.draw setLightDirection:{0, 0, -1} ambient:0 diffuse:1];

  // Mixed parity batches, mask texture, and faded/BLEND fallback match scalar draws.
  for (auto model : {opaque, mask, both, unlit, red, parts})
  {
    std::array<Instance, 3> placements;
    for (int i = 0; i < 3; ++i)
    {
      placements[i].position = {(i - 1) * .15f, 0, .1f + i * .06f};
      placements[i].scale    = {i == 1 ? -.7f : .7f, .7f, .7f};
    }
    for (float alpha : {1.f, .5f})
    {
      for (auto &i : placements)
        i.color.w = alpha;
      auto individual = h.Run(camera,
                              [&]
                              {
                                for (const auto &i : placements)
                                  [h.draw drawModel:model
                                           position:i.position
                                           rotation:i.rotation
                                              scale:i.scale
                                              color:i.color];
                              });
      auto batch = h.Run(camera, [&] { [h.draw drawModelInstances:model instances:placements]; });
      Check(individual == batch, "material instance output differs from scalar output");
      bool blend = alpha < 1 || model.parts[0].alphaMode == 2;
      Check(h.draw.modelDrawCallCount == model.parts.count * (blend ? 3 : 1),
            "material batching classification wrong");
    }
  }
  auto animated = h.Load(root / "animated_blend.glb");
  [animated setAnimationIndex:0];
  [animated setAnimationTime:0];
  auto clone = [animated newInstance];
  Color(Center(h.Run(camera,
                     [&]
                     {
                       Submit(h, animated, 0);
                       Submit(h, blue, .5);
                     })),
        128,
        0,
        64,
        191);
  [animated setAnimationTime:1];
  Color(Center(h.Run(camera,
                     [&]
                     {
                       Submit(h, animated, 0);
                       Submit(h, blue, .5);
                     })),
        64,
        0,
        128,
        191);
  Color(Center(h.Run(camera,
                     [&]
                     {
                       Submit(h, clone, 0);
                       Submit(h, blue, .5);
                     })),
        128,
        0,
        64,
        191);
  [animated release];
  Check(clone.parts[0].alphaMode == 2 && clone.parts[0].unlit, "clone material settings lost");
  Color(Center(h.Run(camera,
                     [&]
                     {
                       Submit(h, clone, 0);
                       Submit(h, blue, .5);
                     })),
        128,
        0,
        64,
        191);
  [clone release];
  for (auto model : {opaque, mask, equal, cutoff, red, blue, parts, lit, unlit, both})
    [model release];
  std::puts("materials: alpha coverage, cutoff, depth, blend sorting, sidedness, mirrored "
            "skin/instances, unlit and clone pose passed");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3 || (argc == 4 && std::string_view(argv[3]) == "--custom-surface"),
            "usage: material_regression shaders.metallib material-fixtures");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness h(device, argv[1]);
        if (argc == 4)
        {
          std::string diagnostics;
          auto        shader =
              [h.draw createModelShader:
                          "float3 alloy3dShade(ModelSurface s, float4 p) { return s.litColor; }"
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
