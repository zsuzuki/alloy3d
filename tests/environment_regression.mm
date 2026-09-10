#include "render_harness.h"
#include <limits>

static void Pixel(const Pixels &pixels, std::array<float, 4> expected, int x = 128, int y = 128)
{
  uint32_t  p        = pixels[y * 256 + x];
  const int shifts[] = {16, 8, 0, 24};
  for (int i = 0; i < 4; ++i)
  {
    int value = (p >> shifts[i]) & 255;
    if (std::abs(value - int(std::round(expected[i] * 255))) > 3)
    {
      std::fprintf(stderr,
                   "pixel %d,%d channel %d: actual %d expected %.2f\n",
                   x,
                   y,
                   i,
                   value,
                   expected[i] * 255);
      Check(false, "environment pixel mismatch");
    }
  }
}
static void Model(Harness &h, MetalModel *model, float z = 0, simd_float3 rotation = {0, 0, 0})
{
  [h.draw drawModel:model position:{0, 0, z} rotation:rotation scale:{3, 3, 3} color:{1, 1, 1, 1}];
}
static alloy3d::ModelShaderPtr Compile(Harness &h, const char *source)
{
  std::string error;
  auto        shader = [h.draw createModelShader:source diagnostics:error];
  if (!shader)
    throw std::runtime_error(error);
  return shader;
}
static void Invalid(const std::function<void()> &change)
{
  bool rejected = false;
  try
  {
    change();
  }
  catch (const std::invalid_argument &)
  {
    rejected = true;
  }
  Check(rejected, "invalid environment settings accepted");
}
static void Test(Harness &h, const std::filesystem::path &root)
{
  auto                red   = h.Load(root / "opaque_alpha.glb");
  auto                lit   = h.Load(root / "double_sided.glb");
  auto                blend = h.Load(root / "blend_red.glb");
  auto                mask  = h.Load(root / "mask_checker.glb");
  auto                skin  = h.Load(root / "mirrored_skin.glb");
  alloy3d::CameraData camera;
  camera.buildModelView({0, 0, 5}, {0, 0, 0}, {0, 1, 0});
  camera.buildOrthographic(4, 1, .1, 30);
  [h.draw setLightDirection:{0, 0, -1} ambient:1 diffuse:0];
  auto baseline = h.Run(camera, [&] { Model(h, lit); });
  [h.draw setFog:alloy3d::Fog3D{}];
  [h.draw setHemisphereLight:alloy3d::HemisphereLight3D{}];
  Check(baseline == h.Run(camera, [&] { Model(h, lit); }), "defaults changed rendering");

  alloy3d::Fog3D fog;
  fog.enabled = true;
  fog.color   = {0, 0, 1};
  fog.start   = 3;
  fog.end     = 7;
  [h.draw setFog:fog];
  for (bool perspective : {false, true})
  {
    if (perspective)
      camera.buildPerspective(.8, 1, .1, 30);
    for (float z : {3.f, 2.f, 0.f, -2.f, -3.f})
    {
      float t = std::clamp((5 - z - 3) / 4, 0.f, 1.f);
      Pixel(h.Run(camera, [&] { Model(h, red, z); }), {1 - t, 0, t, 1});
    }
  }
  camera.buildOrthographic(4, 1, .1, 30);
  Pixel(h.Run(camera, [&] { Model(h, blend); }), {.25, 0, .25, .5});
  // Interpolate depth, then clamp fog per pixel; clamping at vertices is incorrect.
  auto sloped = h.Run(camera,
                      [&]
                      {
                        [h.draw drawPlane:{-2, -2, 4}
                                       p1:{2, -2, -4}
                                       p2:{2, 2, -4}
                                       p3:{-2, 2, 4}
                                    color:{1, 0, 0, 1}];
                      });
  Pixel(sloped, {.7461f, 0, .2539f, 1}, 96);
  // Fog modifies RGB only: MASK coverage must match even at full fog.
  auto fogMask = h.Run(camera, [&] { Model(h, mask, -2); });
  [h.draw setFog:alloy3d::Fog3D{}];
  auto plainMask = h.Run(camera, [&] { Model(h, mask, -2); });
  int  visible = 0, holes = 0;
  for (size_t i = 0; i < fogMask.size(); ++i)
  {
    Check((fogMask[i] >> 24) == (plainMask[i] >> 24), "fog changed MASK coverage");
    visible += (fogMask[i] >> 24) != 0;
    holes += (fogMask[i] >> 24) == 0;
  }
  Check(visible > 1000 && holes > 1000, "MASK fixture did not exercise coverage");

  // Apply fog after custom shading, exactly once, including custom unlit output.
  auto green =
      Compile(h, "float3 alloy3dShade(ModelSurface s, float4 p) { return float3(0,1,0); }");
  [h.draw setFog:fog];
  [h.draw setModelShader:green parameters:{}];
  Pixel(h.Run(camera, [&] { Model(h, red); }), {0, .5, .5, 1});
  [h.draw setModelShader:{} parameters:{}];
  auto fogged = h.Run(camera, [&] { Model(h, red); });
  for (float value :
       {-1.f, 7.f, std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
  {
    auto bad  = fog;
    bad.start = value;
    Invalid([&] { [h.draw setFog:bad]; });
  }
  auto badFog    = fog;
  badFog.color.y = 2;
  Invalid([&] { [h.draw setFog:badFog]; });
  Check(fogged == h.Run(camera, [&] { Model(h, red); }), "invalid fog mutated live state");

  // Normal-free lines and 3D text still receive distance fog.
  auto line =
      h.Run(camera, [&] { [h.draw drawLine:{-1, 0, -2} to:{1, 0, -2} color:{1, 0, 0, 1}]; });
  bool blueLine = false;
  for (auto p : line)
    blueLine |= (p & 0xffffff) == 255;
  Check(blueLine, "unlit line missed fog");
  auto text     = h.Run(camera,
                        [&]
                        {
                      [h.draw drawText:@"Fog"
                              position:{-.8f, -.3f, -2}
                            lineHeight:1
                                 align:DrawText3DAlignLeftBottom
                                 color:{1, 0, 0, 1}];
                        });
  bool blueText = false;
  for (auto p : text)
    blueText |= (p & 255) > 200 && ((p >> 16) & 255) < 3;
  Check(blueText, "3D text missed fog or retained stale model uniforms");

  [h.draw setFog:alloy3d::Fog3D{}];
  alloy3d::HemisphereLight3D hemi;
  hemi.enabled     = true;
  hemi.up          = {0, 0, 2};
  hemi.skyColor    = {1, 0, 0};
  hemi.groundColor = {0, 0, 1};
  hemi.intensity   = 1;
  [h.draw setHemisphereLight:hemi];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {.2, 0, 0, 1});
  hemi.up = {0, 0, -1};
  [h.draw setHemisphereLight:hemi];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {0, 0, .6, 1});
  hemi.up = {0, 1, 0};
  [h.draw setHemisphereLight:hemi];
  auto hemisphere = h.Run(camera, [&] { Model(h, lit); });
  Pixel(hemisphere, {.1, 0, .3, 1});
  Pixel(h.Run(camera,
              [&]
              {
                [h.draw drawPlane:{-2, -2, 0}
                               p1:{2, -2, 0}
                               p2:{2, 2, 0}
                               p3:{-2, 2, 0}
                            color:{1, 1, 1, 1}];
              }),
        {.5, 0, .5, 1});
  Pixel(h.Run(camera, [&] { Model(h, red); }), {1, 0, 0, 1});
  // World-space environment must not rotate with the camera.
  camera.buildModelView({3, 1, 5}, {0, 0, 0}, {0, 1, 0});
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {.1, 0, .3, 1});
  camera.buildModelView({0, 0, -5}, {0, 0, 0}, {0, 1, 0});
  hemi.up = {0, 0, 1};
  [h.draw setHemisphereLight:hemi];
  Pixel(h.Run(camera, [&] { Model(h, lit); }), {0, 0, .6, 1});
  camera.buildModelView({0, 0, 5}, {0, 0, 0}, {0, 1, 0});
  hemi.up = {0, 1, 0};
  [h.draw setHemisphereLight:hemi];
  auto identity =
      Compile(h, "float3 alloy3dShade(ModelSurface s, float4 p) { return s.litColor; }");
  auto ambient = Compile(
      h, "float3 alloy3dShade(ModelSurface s, float4 p) { return s.baseColor * s.ambientColor; }");
  for (auto shader : {identity, ambient})
  {
    [h.draw setModelShader:shader parameters:{}];
    Check(hemisphere == h.Run(camera, [&] { Model(h, lit); }), "custom ambient disagrees");
  }
  [h.draw setModelShader:{} parameters:{}];
  auto badHemi = hemi;
  badHemi.up   = {};
  Invalid([&] { [h.draw setHemisphereLight:badHemi]; });
  badHemi           = hemi;
  badHemi.intensity = -1;
  Invalid([&] { [h.draw setHemisphereLight:badHemi]; });
  badHemi            = hemi;
  badHemi.skyColor.x = std::numeric_limits<float>::quiet_NaN();
  Invalid([&] { [h.draw setHemisphereLight:badHemi]; });
  Check(hemisphere == h.Run(camera, [&] { Model(h, lit); }), "invalid hemisphere mutated state");

  [h.draw setFog:fog];
  std::array<Instance, 2> placements;
  placements[0].position = {-.7f, 0, 1};
  placements[1].position = {.7f, 0, -1};
  placements[0].scale    = {.8, 1.5, .7};
  placements[1].scale    = {-.8, 1.5, .7};
  for (auto model : {lit, skin})
  {
    auto individual = h.Run(camera,
                            [&]
                            {
                              for (auto &i : placements)
                                [h.draw drawModel:model
                                         position:i.position
                                         rotation:i.rotation
                                            scale:i.scale
                                            color:i.color];
                            });
    auto batched = h.Run(camera, [&] { [h.draw drawModelInstances:model instances:placements]; });
    Check(individual == batched && [h.draw modelDrawCallCount] == 1,
          "environment changed skin/instance output or batching");
  }
  Check([h.draw shadowDrawCallCount] == 0 && [h.draw memoryStats].shadowMapBytes == 4,
        "environment allocated a shadow map or pass");
  // Shadow visibility affects direct light, leaving hemisphere ambient intact.
  [h.draw setFog:alloy3d::Fog3D{}];
  [h.draw setLightDirection:{.8f, 0, -1} ambient:0 diffuse:.8f];
  alloy3d::DirectionalShadow3D shadow;
  shadow.enabled    = true;
  shadow.resolution = 512;
  shadow.bounds     = {{-2, -2, -.2f}, {2, 2, 2}};
  shadow.depthBias  = .002f;
  [h.draw setDirectionalShadow:shadow];
  auto scene = [&]
  {
    [h.draw drawPlane:{-2, -2, 0} p1:{2, -2, 0} p2:{2, 2, 0} p3:{-2, 2, 0} color:{1, 1, 1, 1}];
    [h.draw drawModel:lit
             position:{-.3f, 0, 1}
             rotation:{0, 0, 0}
                scale:{.6f, .6f, .6f}
                color:{1, 1, 1, 1}];
  };
  auto shaded = h.Run(camera, scene);
  Pixel(shaded, {.5, 0, .5, 1}, 160);
  [h.draw setFog:fog];
  Pixel(h.Run(camera, scene), {.25, 0, .75, 1}, 160);
  Check([h.draw shadowDrawCallCount] == 2, "environment changed shadow draw count");
  [h.draw setDirectionalShadow:alloy3d::DirectionalShadow3D{}];
  [h.draw setLightDirection:{0, 0, -1} ambient:1 diffuse:0];
  // Each in-flight page retains its own settings after encoding.
  for (int i = 0; i < 3; ++i)
  {
    fog.color = i == 0   ? simd_float3{1, 0, 0}
                : i == 1 ? simd_float3{0, 1, 0}
                         : simd_float3{0, 0, 1};
    [h.draw setFog:fog];
    h.Begin(i);
    Model(h, red, -2);
    h.Encode(i, camera);
    [h.commands[i] commit];
  }
  Pixel(h.Read(0), {1, 0, 0, 1});
  Pixel(h.Read(1), {0, 1, 0, 1});
  Pixel(h.Read(2), {0, 0, 1, 1});
  [h.draw setFog:alloy3d::Fog3D{}];
  [h.draw setHemisphereLight:alloy3d::HemisphereLight3D{}];
  Check(baseline == h.Run(camera, [&] { Model(h, lit); }), "disable did not restore baseline");
  for (auto model : {red, lit, blend, mask, skin})
    [model release];
  std::puts("environment: fog depth, projection, alpha, MASK, custom, text, hemisphere, camera, "
            "instances and pages passed");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: environment_regression shaders.metallib material-fixtures");
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
