#include "render_harness.h"
#include <limits>

using Transform = alloy3d::ModelTextureTransform3D;
static alloy3d::ModelShaderPtr Compile(Harness &h, const char *source)
{
  std::string error;
  auto        shader = [h.draw createModelShader:source diagnostics:error];
  Check(bool(shader), error.c_str());
  return shader;
}
static void Submit(Harness &h, MetalModel *model, float x = 0, float z = .4f)
{
  [h.draw drawModel:model position:{x, 0, z} rotation:{0, 0, 0} scale:{1, 1, 1} color:{1, 1, 1, 1}];
}
static void Near(uint32_t pixel, std::array<float, 3> expected)
{
  for (int c = 0; c < 3; ++c)
    Check(std::abs(int((pixel >> (16 - c * 8)) & 255) - int(std::round(expected[c] * 255))) <= 2,
          "surface coordinate/direction differs from expected value");
}
static void Test(Harness &h, const std::filesystem::path &root)
{
  auto                opaque  = h.Load(root / "opaque_alpha.glb");
  auto                mask    = h.Load(root / "mask_checker.glb");
  auto                blend   = h.Load(root / "blend_red.glb");
  auto                skin    = h.Load(root / "mirrored_skin.glb");
  auto                checker = h.Load(root.parent_path() / "mipmaps/checker.glb");
  alloy3d::CameraData camera;
  auto                baseline = h.Run(camera, [&] { Submit(h, mask); });
  [h.draw setModelTextureTransform:Transform{}];
  Check(baseline == h.Run(camera, [&] { Submit(h, mask); }),
        "default UV transform was not identity");
  Transform shift{{1, 1}, {.125f, 0}};
  [h.draw setModelTextureTransform:shift];
  auto shifted = h.Run(camera,
                       [&]
                       {
                         Submit(h, mask);
                         [h.draw setModelTextureTransform:Transform{}];
                       });
  Check(shifted != baseline, "base texture/MASK did not move or snapshot was lost");
  Check(h.Run(camera, [&] { Submit(h, mask); }) == baseline, "identity reset failed");

  [h.draw setModelTextureTransform:(Transform{{1.f / 128, 1.f / 128}, {0, 0}})];
  auto textured = h.Run(camera, [&] { Submit(h, checker); });
  [h.draw setModelTextureTransform:(Transform{{1.f / 128, 1.f / 128}, {1.f / 1024, 0}})];
  Check(textured != h.Run(camera, [&] { Submit(h, checker); }),
        "opaque RGB texture did not scroll");

  auto uv =
      Compile(h, "float3 alloy3dShade(ModelSurface s,float4 p){return float3(s.texcoord,0);}");
  [h.draw setModelShader:uv parameters:{0, 0, 0, 0}];
  Transform transform{{.5f, .6f}, {.1f, .2f}};
  [h.draw setModelTextureTransform:transform];
  auto custom = h.Run(camera, [&] { Submit(h, opaque); });
  Near(custom[128 * 256 + 128], {.351953f, .497656f, 0});
  for (int component = 0; component < 4; ++component)
    for (float bad :
         {std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()})
    {
      auto invalid = transform;
      if (component < 2)
        invalid.scale[component] = bad;
      else
        invalid.offset[component - 2] = bad;
      bool rejected = false;
      try
      {
        [h.draw setModelTextureTransform:invalid];
      }
      catch (const std::invalid_argument &)
      {
        rejected = true;
      }
      Check(rejected, "non-finite UV transform accepted");
      Check(custom == h.Run(camera, [&] { Submit(h, opaque); }),
            "invalid UV transform changed saved state");
    }
  [h.draw setModelTextureTransform:(Transform{{0, 0}, {.2f, .7f}})];
  Near(h.Run(camera, [&] { Submit(h, opaque); })[128 * 256 + 128], {.2f, .7f, 0});
  [h.draw setModelTextureTransform:(Transform{{-.5f, .5f}, {.75f, .1f}})];
  auto negative = h.Run(camera, [&] { Submit(h, opaque); });
  Check(((negative[128 * 256 + 100] >> 16) & 255) > ((negative[128 * 256 + 155] >> 16) & 255),
        "negative UV scale not mirrored");

  std::array<Instance, 2> instances;
  instances[0].position = {-.5f, 0, .4f};
  instances[1].position = {.5f, 0, .4f};
  instances[1].scale    = {-1, 1, 1};
  for (auto model : {skin, blend})
  {
    [h.draw setModelTextureTransform:transform];
    auto individual = h.Run(camera,
                            [&]
                            {
                              for (auto &i : instances)
                                [h.draw drawModel:model
                                         position:i.position
                                         rotation:i.rotation
                                            scale:i.scale
                                            color:i.color];
                            });
    auto batched    = h.Run(camera,
                            [&]
                            {
                           [h.draw drawModelInstances:model instances:instances];
                           [h.draw setModelTextureTransform:Transform{}];
                            });
    Check(individual == batched,
          "UV transform differs for skin, mirrored instances or BLEND fallback");
    Check([h.draw modelDrawCallCount] == (model == skin ? 1 : 2),
          "UV state split instance batching");
  }
  for (int slot = 0; slot < 3; ++slot)
  {
    h.Begin(slot);
    [h.draw setModelTextureTransform:(Transform{{0, 0}, {.2f * slot, .4f}})];
    Submit(h, opaque);
    [h.draw setModelTextureTransform:Transform{}];
    h.Encode(slot, camera);
    [h.commands[slot] commit];
  }
  for (int slot = 0; slot < 3; ++slot)
    Near(h.Read(slot)[128 * 256 + 128], {.2f * slot, .4f, 0});

  // View-space inputs remain valid with highlights OFF and unlit materials.
  auto position =
      Compile(h, "float3 alloy3dShade(ModelSurface s,float4 p){return s.viewPosition*.1+.5;}");
  auto direction =
      Compile(h, "float3 alloy3dShade(ModelSurface s,float4 p){return s.viewDirection*.5+.5;}");
  auto light = Compile(h,
                       "float3 alloy3dShade(ModelSurface s,float4 p){return "
                       "s.lightDirection*s.lightIntensity*.5+.5;}");
  camera.buildModelView({0, 0, 3}, {0, 0, 0}, {0, 1, 0});
  for (bool perspective : {false, true})
  {
    if (perspective)
      camera.buildPerspective(.8f, 1, .1f, 10);
    else
      camera.buildOrthographic(2, 1, .1f, 10);
    [h.draw setModelShader:position parameters:{0, 0, 0, 0}];
    Near(h.Run(camera, [&] { Submit(h, opaque, 0, 0); })[128 * 256 + 128], {.5f, .5f, .2f});
    [h.draw setModelShader:direction parameters:{0, 0, 0, 0}];
    auto p = h.Run(camera, [&] { Submit(h, opaque, 0, 0); });
    Near(p[128 * 256 + 128], {.5f, .5f, 1});
    if (perspective)
      Check(((p[128 * 256 + 100] >> 16) & 255) > ((p[128 * 256 + 155] >> 16) & 255),
            "perspective eye rays are constant");
    else
      Near(p[128 * 256 + 100], {.5f, .5f, 1});
    [h.draw setLightDirection:{-1, 0, 0} ambient:0 diffuse:.8f];
    [h.draw setModelShader:light parameters:{0, 0, 0, 0}];
    Near(h.Run(camera, [&] { Submit(h, opaque, 0, 0); })[128 * 256 + 128], {.9f, .5f, .5f});
  }
  camera.buildModelView({2, 1, 4}, {0, 0, 0}, {0, 1, 0});
  [h.draw setModelShader:position parameters:{0, 0, 0, 0}];
  auto individualPosition = h.Run(camera,
                                  [&]
                                  {
                                    for (auto &i : instances)
                                      [h.draw drawModel:skin
                                               position:i.position
                                               rotation:i.rotation
                                                  scale:i.scale
                                                  color:i.color];
                                  });
  auto instancePosition =
      h.Run(camera, [&] { [h.draw drawModelInstances:skin instances:instances]; });
  Check(individualPosition == instancePosition,
        "view position differs after skinning/instancing and camera rotation");
  [h.draw setModelShader:light parameters:{0, 0, 0, 0}];
  [h.draw setLightDirection:{-1, 0, 0} ambient:0 diffuse:.8f];
  auto rotatedLight = h.Run(camera, [&] { Submit(h, opaque, 0, 0); });
  auto expected     = simd_mul(camera.getModelViewMatrix(), simd_make_float4(1, 0, 0, 0));
  Near(rotatedLight[128 * 256 + 128],
       {expected.x * .4f + .5f, expected.y * .4f + .5f, expected.z * .4f + .5f});
  [h.draw setModelShader:{} parameters:{0, 0, 0, 0}];

  // Scrolled alpha cutouts must move their SHADOW on the receiver as well.
  camera.buildModelView({0, 0, 3}, {0, 0, 0}, {0, 1, 0});
  camera.buildOrthographic(4, 1, .1f, 10);
  [h.draw setLightDirection:{.8f, 0, -1} ambient:.2f diffuse:.8f];
  alloy3d::DirectionalShadow3D shadow;
  shadow.enabled    = true;
  shadow.resolution = 512;
  shadow.bounds     = {{-2, -2, -.2f}, {2, 2, 2}};
  [h.draw setDirectionalShadow:shadow];
  auto shadowScene = [&](Transform t, bool instanced)
  {
    return h.Run(camera,
                 [&]
                 {
                   [h.draw drawTriangle:{-2, -2, 0} p1:{2, -2, 0} p2:{2, 2, 0} color:{1, 1, 1, 1}];
                   [h.draw drawTriangle:{-2, -2, 0} p1:{2, 2, 0} p2:{-2, 2, 0} color:{1, 1, 1, 1}];
                   [h.draw setModelTextureTransform:t];
                   if (instanced)
                   {
                     Instance i;
                     i.position = {-.4f, 0, 1};
                     [h.draw drawModelInstances:mask instances:std::span(&i, 1)];
                   }
                   else
                     Submit(h, mask, -.4f, 1);
                   [h.draw setModelTextureTransform:Transform{}];
                 });
  };
  auto original = shadowScene({}, false), moved = shadowScene(shift, false);
  int  changed = 0;
  for (int y = 105; y < 150; ++y)
    for (int x = 141; x < 181; ++x)
      changed += std::abs(int((original[y * 256 + x] >> 16) & 255) -
                          int((moved[y * 256 + x] >> 16) & 255)) > 40;
  Check(changed > 30, "MASK shadow did not follow the UV transform");
  Check(moved == shadowScene(shift, true), "instanced MASK shadow UV differs");
  for (auto model : {opaque, mask, blend, skin, checker})
    [model release];
  std::puts("PASS: UV identity, scale/scroll, snapshot, invalid values, skin/instances, BLEND, "
            "frame pages, view/light inputs, MASK shadows");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: texture_transform_regression shaders.metallib material-directory");
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
