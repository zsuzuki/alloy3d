#include "render_harness.h"
#include <limits>

static alloy3d::ModelShaderPtr Compile(Harness &h, std::string_view source)
{
  std::string error;
  auto        shader = [h.draw createModelShader:source diagnostics:error];
  if (!shader)
    throw std::runtime_error(error);
  Check(error.empty(), "successful compile retained old diagnostics");
  return shader;
}
static void Submit(Harness &h, MetalModel *model, float x = 0, float z = .4f)
{
  [h.draw drawModel:model position:{x, 0, z} rotation:{0, 0, 0} scale:{1, 1, 1} color:{1, 1, 1, 1}];
}
static void Pixel(const Pixels &p, int x, uint32_t expected)
{
  auto actual = p[128 * 256 + x];
  for (int shift : {0, 8, 16, 24})
    Check(std::abs(int((actual >> shift) & 255) - int((expected >> shift) & 255)) <= 2,
          "unexpected custom shader pixel");
}
static void Test(Harness &h, const std::filesystem::path &root)
{
  alloy3d::CameraData camera;
  auto                opaque = h.Load(root / "opaque_alpha.glb");
  auto                blend  = h.Load(root / "blend_red.glb");
  auto                skin   = h.Load(root / "mirrored_skin.glb");
  [h.draw setLightDirection:{0, 0, -1} ambient:0 diffuse:1];
  auto constant = Compile(h, "float3 alloy3dShade(ModelSurface s, float4 p) { return p.rgb; }");
  auto identity =
      Compile(h, "float3 alloy3dShade(ModelSurface s, float4 p) { return s.litColor; }");
  auto uv =
      Compile(h, "float3 alloy3dShade(ModelSurface s, float4 p) { return float3(s.texcoord, 0); }");
  auto baseline = h.Run(camera, [&] { Submit(h, opaque); });
  Check([h.draw setModelShader:identity parameters:{0, 0, 0, 0}], "identity shader rejected");
  Check(baseline == h.Run(camera, [&] { Submit(h, opaque); }), "identity differs from built-in");
  Check([h.draw setModelShader:uv parameters:{0, 0, 0, 0}], "UV shader rejected");
  auto uvPixels = h.Run(camera, [&] { Submit(h, opaque); });
  Check(uvPixels[128 * 256 + 80] != uvPixels[128 * 256 + 170], "surface UV was not interpolated");

  // Switching state after submission must not retroactively recolor or restore queued draws.
  auto snapshot = h.Run(camera,
                        [&]
                        {
                          [h.draw setModelShader:constant parameters:{0, 1, 0, 0}];
                          Submit(h, opaque, -.5f);
                          [h.draw setModelShader:constant parameters:{0, 0, 1, 0}];
                          Submit(h, opaque, .5f);
                          [h.draw setModelShader:{} parameters:{0, 0, 0, 0}];
                        });
  Pixel(snapshot, 64, 0xff00ff00);
  Pixel(snapshot, 192, 0xff0000ff);
  Check(baseline == h.Run(camera, [&] { Submit(h, opaque); }), "null did not restore default");

  // Compile and state validation errors must leave the current shader and values untouched.
  [h.draw setModelShader:constant parameters:{0, 1, 0, 0}];
  for (auto source :
       {"", "float3 alloy3dShade( broken", "float3 wrongName() { return float3(0); }"})
  {
    std::string error = "stale";
    Check(![h.draw createModelShader:source diagnostics:error], "invalid shader compiled");
    Check(!error.empty() && error != "stale", "compile diagnostic missing");
    if (std::string_view(source).find("broken") != std::string_view::npos)
      Check(error.find("model_surface_user.metal") != std::string::npos,
            "user source not identified");
  }
  std::string error;
  Check(![h.draw createModelShader:std::string_view("\xff", 1) diagnostics:error],
        "invalid UTF8 accepted");
  Check(![h.draw createModelShader:std::string_view("a\0b", 3) diagnostics:error],
        "embedded null accepted");
  Check(![h.draw setModelShader:identity
                     parameters:{std::numeric_limits<float>::infinity(), 0, 0, 0}],
        "non-finite parameters accepted");
  auto foreign = [[Draw3D alloc] initWithMetalKitView:h.view shaderlib:h.library];
  Check(![foreign setModelShader:constant parameters:{0, 0, 0, 0}],
        "foreign context shader accepted");
  [foreign release];
  Pixel(h.Run(camera, [&] { Submit(h, opaque); }), 128, 0xff00ff00);

  // Mirrored skinning and instance paths use the same custom fragment; count stays one.
  std::array<Instance, 2> placements;
  placements[0].position = {-.5f, 0, .4f};
  placements[1].position = {.5f, 0, .4f};
  placements[1].scale    = {-1, 1, 1};
  auto individual        = h.Run(camera,
                                 [&]
                                 {
                            for (auto &i : placements)
                              [h.draw drawModel:skin
                                       position:i.position
                                       rotation:i.rotation
                                          scale:i.scale
                                          color:i.color];
                                 });
  auto batched = h.Run(camera, [&] { [h.draw drawModelInstances:skin instances:placements]; });
  Check(individual == batched && [h.draw modelDrawCallCount] == 1,
        "custom instancing changed pixels or lost batching");
  Pixel(batched, 64, 0xff00ff00);
  Pixel(batched, 192, 0xff00ff00);
  // BLEND falls back to sorted scalar draws, retaining shader and parameters.
  auto blended = h.Run(camera, [&] { [h.draw drawModelInstances:blend instances:placements]; });
  Check([h.draw modelDrawCallCount] == 2, "BLEND did not use individual draws");
  Pixel(blended, 64, 0x80008000);

  // Shader can be dropped by its caller and reset before encoding; queues retain it.
  std::weak_ptr<alloy3d::ModelShader> weak = constant;
  h.Begin(0);
  Submit(h, opaque);
  [h.draw setModelShader:{} parameters:{0, 0, 0, 0}];
  constant.reset();
  Check(!weak.expired(), "queued shader released prematurely");
  h.Encode(0, camera);
  Check(weak.expired(), "encoded queue retains unused shader handle");
  [h.commands[0] commit];
  Pixel(h.Read(0), 128, 0xff00ff00);

  // Multiple command buffers copy independent parameters and retain their pipelines.
  for (int slot = 0; slot < 3; ++slot)
  {
    auto shader = Compile(h, "float3 alloy3dShade(ModelSurface s, float4 p) { return p.rgb; }");
    simd_float4 p{};
    p[slot] = 1;
    h.Begin(slot);
    [h.draw setModelShader:shader parameters:p];
    Submit(h, opaque);
    [h.draw setModelShader:{} parameters:{0, 0, 0, 0}];
    h.Encode(slot, camera);
    [h.commands[slot] commit];
  }
  for (int slot = 0; slot < 3; ++slot)
    Pixel(h.Read(slot), 128, 0xff000000 | (0xff << ((2 - slot) * 8)));
  // Discarded submissions release handles without touching the next frame.
  auto discarded = Compile(h, "float3 alloy3dShade(ModelSurface s, float4 p) { return p.rgb; }");
  weak           = discarded;
  h.Begin(0);
  [h.draw setModelShader:discarded parameters:{0, 0, 0, 0}];
  Submit(h, opaque);
  [h.draw setModelShader:{} parameters:{0, 0, 0, 0}];
  discarded.reset();
  [h.draw discardFrame];
  Check(weak.expired(), "discarded shader retained");
  Check(baseline == h.Run(camera, [&] { Submit(h, opaque); }), "discard leaked state");
  for (auto model : {opaque, blend, skin})
    [model release];
  std::puts("shader: diagnostics, RGB, UV, snapshots, restore, context ownership, skin/instances, "
            "blend and GPU lifetime passed");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: shader_regression shaders.metallib material-fixtures");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness h(device, argv[1]);
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
