#include "render_harness.h"
#include <limits>

static void Pixel(const Pixels &p, std::array<float, 4> expected, int x = 128)
{
  int shifts[] = {16, 8, 0, 24};
  for (int i = 0; i < 4; ++i)
  {
    int actual = (p[128 * 256 + x] >> shifts[i]) & 255;
    if (std::abs(actual - int(std::round(expected[i] * 255))) > 3)
    {
      std::fprintf(
          stderr, "x=%d channel=%d actual=%d expected=%.2f\n", x, i, actual, expected[i] * 255);
      Check(false, "highlight pixel mismatch");
    }
  }
}
static void Model(Harness &h, MetalModel *model, float x = 0, float z = 0, float scale = 3)
{
  [h.draw drawModel:model
           position:{x, 0, z}
           rotation:{0, 0, 0}
              scale:{scale, scale, scale}
              color:{1, 1, 1, 1}];
}
static alloy3d::ModelShaderPtr Compile(Harness &h, const char *source)
{
  std::string error;
  auto        shader = [h.draw createModelShader:source diagnostics:error];
  if (!shader)
    throw std::runtime_error(error);
  return shader;
}
static void Test(Harness &h, const std::filesystem::path &root)
{
  auto                lit   = h.Load(root / "double_sided.glb");
  auto                unlit = h.Load(root / "opaque_alpha.glb");
  auto                blend = h.Load(root / "blend_lit.glb");
  auto                skin  = h.Load(root / "mirrored_skin.glb");
  alloy3d::CameraData camera;
  camera.buildModelView({0, 0, 5}, {0, 0, 0}, {0, 1, 0});
  camera.buildOrthographic(4, 1, .1, 20);
  alloy3d::DirectionalLight3D light;
  light.direction = {0, 0, -1};
  light.ambient   = .2;
  light.diffuse   = .5;
  [h.draw setDirectionalLight:light];
  auto baseline = h.Run(camera, [&] { Model(h, lit); });
  Pixel(baseline, {.14, .28, .42, 1});
  alloy3d::ModelHighlight3D highlight{.4, 32};
  [h.draw setModelHighlight:highlight];
  auto shiny = h.Run(camera, [&] { Model(h, lit); });
  Pixel(shiny, {.34, .48, .62, 1});
  Pixel(shiny, {.34, .48, .62, 1}, 96); // Orthographic rays are parallel.
  Pixel(h.Run(camera, [&] { Model(h, unlit); }), {1, 0, 0, 1});
  Pixel(h.Run(camera, [&] { Model(h, blend); }), {.45, .1, .1, .5});

  auto saved = h.Run(camera,
                     [&]
                     {
                       Model(h, lit, -.8, 0, 1);
                       [h.draw setModelHighlight:(alloy3d::ModelHighlight3D{.8, 32})];
                       Model(h, lit, .8, 0, 1);
                       [h.draw setModelHighlight:alloy3d::ModelHighlight3D{}];
                     });
  Pixel(saved, {.34, .48, .62, 1}, 77);
  Pixel(saved, {.54, .68, .82, 1}, 179);
  Check(baseline == h.Run(camera, [&] { Model(h, lit); }), "reset did not restore old shading");
  [h.draw setModelHighlight:highlight];
  for (auto bad : {alloy3d::ModelHighlight3D{-1, 32},
                   alloy3d::ModelHighlight3D{2, 32},
                   alloy3d::ModelHighlight3D{.4, 0},
                   alloy3d::ModelHighlight3D{.4, 129},
                   alloy3d::ModelHighlight3D{std::numeric_limits<float>::quiet_NaN(), 32},
                   alloy3d::ModelHighlight3D{.4, std::numeric_limits<float>::infinity()}})
  {
    bool rejected = false;
    try
    {
      [h.draw setModelHighlight:bad];
    }
    catch (const std::invalid_argument &)
    {
      rejected = true;
    }
    Check(rejected, "invalid highlight accepted");
  }
  Check(shiny == h.Run(camera, [&] { Model(h, lit); }), "invalid highlight mutated live state");
  light.diffuse = 0;
  [h.draw setDirectionalLight:light];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {.04, .08, .12, 1});
  light.diffuse = .5;
  light.color   = {1, 0, 0};
  [h.draw setDirectionalLight:light];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {.34, .08, .12, 1});
  light.color     = {1, 1, 1};
  light.direction = {0, 0, 1};
  [h.draw setDirectionalLight:light];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {.04, .08, .12, 1});
  light.direction = {0, 0, -1};
  [h.draw setDirectionalLight:light];

  // Perspective view direction varies across the surface; higher exponents narrow the lobe.
  camera.buildModelView({3, 0, 5}, {0, 0, 0}, {0, 1, 0});
  camera.buildPerspective(.8, 1, .1, 20);
  for (float exponent : {8.f, 128.f})
  {
    [h.draw setModelHighlight:(alloy3d::ModelHighlight3D{.4, exponent})];
    auto  v          = simd_normalize(simd_make_float3(3, 0, 5));
    auto  halfVector = simd_normalize(v + simd_make_float3(0, 0, 1));
    float spec       = .2f * std::pow(halfVector.z, exponent);
    Pixel(h.Run(camera, [&] { Model(h, lit); }), {.14f + spec, .28f + spec, .42f + spec, 1});
  }
  camera.buildModelView({0, 0, 5}, {0, 0, 0}, {0, 1, 0});
  camera.buildOrthographic(4, 1, .1, 20);
  [h.draw setModelHighlight:highlight];
  auto identity = Compile(h, "float3 alloy3dShade(ModelSurface s,float4 p){return s.litColor;}");
  auto recomposed =
      Compile(h,
              "float3 alloy3dShade(ModelSurface s,float4 p){return "
              "s.baseColor*(s.ambientColor+s.diffuse*s.shadow*s.lightColor)+s.specularColor;}");
  for (auto shader : {identity, recomposed})
  {
    [h.draw setModelShader:shader parameters:{}];
    Check(shiny == h.Run(camera, [&] { Model(h, lit); }),
          "custom highlight disagrees with standard");
  }
  auto constant =
      Compile(h, "float3 alloy3dShade(ModelSurface s,float4 p){return float3(.1,0,0);}");
  [h.draw setModelShader:constant parameters:{}];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {.1, 0, 0, 1});
  [h.draw setModelShader:{} parameters:{}];
  alloy3d::Fog3D fog;
  fog.enabled = true;
  fog.color   = {0, 0, 1};
  fog.start   = 3;
  fog.end     = 7;
  [h.draw setFog:fog];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {.17, .24, .81, 1});
  [h.draw setFog:alloy3d::Fog3D{}];

  std::array<Instance, 2> placements;
  placements[0].position = {-.7, 0, 0};
  placements[1].position = {.7, 0, 0};
  placements[0].scale    = {.8, 1.2, .6};
  placements[1].scale    = {-.8, 1.2, .6};
  camera.buildPerspective(.8, 1, .1, 20);
  for (auto model : {lit, skin, blend})
  {
    auto scalar = h.Run(camera,
                        [&]
                        {
                          for (auto &i : placements)
                            [h.draw drawModel:model
                                     position:i.position
                                     rotation:i.rotation
                                        scale:i.scale
                                        color:i.color];
                        });
    auto batch  = h.Run(camera, [&] { [h.draw drawModelInstances:model instances:placements]; });
    Check(scalar == batch, "highlight changes mirrored/skin/BLEND batch output");
    Check([h.draw modelDrawCallCount] == (model == blend ? 2 : 1),
          "highlight split an instance batch");
  }
  camera.buildOrthographic(4, 1, .1, 20);
  light.direction = {.8, 0, -1};
  [h.draw setDirectionalLight:light];
  alloy3d::DirectionalShadow3D shadow;
  shadow.enabled    = true;
  shadow.resolution = 512;
  shadow.bounds     = {{-2, -2, -.2}, {2, 2, 2}};
  shadow.depthBias  = .002;
  [h.draw setDirectionalShadow:shadow];
  auto scene = [&]
  {
    Model(h, lit, 0, 0, 4);
    Model(h, lit, -.3, 1, .6);
  };
  Pixel(h.Run(camera, scene), {.04, .08, .12, 1}, 160);
  Check([h.draw shadowDrawCallCount] == 2, "highlight changed shadow pass");
  [h.draw setDirectionalShadow:alloy3d::DirectionalShadow3D{}];
  light.direction = {0, 0, -1};
  [h.draw setDirectionalLight:light];
  // Three in-flight pages and later settings must not overwrite saved per-draw data.
  for (int i = 0; i < 3; ++i)
  {
    h.Begin(i);
    [h.draw setModelHighlight:(alloy3d::ModelHighlight3D{float(i) * .2f, 32})];
    Model(h, lit);
    [h.draw setModelHighlight:alloy3d::ModelHighlight3D{}];
    h.Encode(i, camera);
    [h.commands[i] commit];
  }
  for (int i = 0; i < 3; ++i)
    Pixel(h.Read(i), {.14f + .1f * i, .28f + .1f * i, .42f + .1f * i, 1});
  Check(baseline == h.Run(camera, [&] { Model(h, lit); }), "highlight leaked after reset");
  for (auto model : {lit, unlit, blend, skin})
    [model release];
  std::puts("highlight: strength, exponent, view, light, shadow, fog, alpha, custom, snapshots, "
            "skin/instances and pages passed");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: highlight_regression shaders.metallib material-fixtures");
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
