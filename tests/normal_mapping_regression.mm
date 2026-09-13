#include "render_harness.h"
#include <limits>

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: normal_mapping_regression shaders.metallib fixtures");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness             h(device, argv[1]);
        alloy3d::CameraData camera;
        auto                root   = std::filesystem::path(argv[2]);
        auto                flat   = h.Load(root / "flat.glb");
        auto                tilted = h.Load(root / "tilted.glb");
        Check(tilted.parts[0].normalTexture.pixelFormat == MTLPixelFormatRGBA8Unorm ||
                  tilted.parts[0].normalTexture.pixelFormat == MTLPixelFormatBGRA8Unorm,
              "normal texture incorrectly decoded as sRGB");
        Check(tilted.parts[0].normalTexture.mipmapLevelCount == 2, "normal mipmaps missing");
        [h.draw setLightDirection:{-.6f, 0, -.8f} ambient:0 diffuse:1];
        auto submit = [&](MetalModel *model, simd_float3 scale = {1, 1, 1})
        {
          [h.draw drawModel:model position:{0, 0, .5f} rotation:{} scale:scale color:{1, 1, 1, 1}];
        };
        auto         reference = h.Run(camera, [&] { submit(flat); });
        auto         mapped    = h.Run(camera, [&] { submit(tilted); });
        const size_t center    = 128 * 256 + 128;
        Check((mapped[center] & 255) > (reference[center] & 255) + 35,
              "normal map did not change lighting correctly");
        [h.draw setModelNormalMapping:{0}];
        Check(h.Run(camera, [&] { submit(tilted); }) == reference,
              "disabled mapping changed flat rendering");
        [h.draw setModelNormalMapping:{1}];
        for (float value : {-1.f, 9.f, std::numeric_limits<float>::quiet_NaN()})
        {
          bool rejected = false;
          try
          {
            [h.draw setModelNormalMapping:(alloy3d::ModelNormalMapping3D{value})];
          }
          catch (const std::invalid_argument &)
          {
            rejected = true;
          }
          Check(rejected && mapped == h.Run(camera, [&] { submit(tilted); }),
                "invalid strength changed state");
        }
        for (const char *kind : {"zero_scale", "degenerate_uv"})
        {
          auto model = h.Load(root / (std::string(kind) + ".glb"));
          Check(h.Run(camera, [&] { submit(model); }) == reference,
                "zero/degenerate normal mapping changed base normal");
          [model release];
        }
        std::string error;
        auto        shader = [h.draw
            createModelShader:
                "float3 alloy3dShade(ModelSurface s, float4 p) { return s.normal * .5 + .5; }"
                  diagnostics:error];
        Check(bool(shader), error.c_str());
        [h.draw setModelShader:shader parameters:{}];
        auto normal = h.Run(camera, [&] { submit(tilted); });
        Check(std::abs(int((normal[center] >> 16) & 255) - 204) < 3 &&
                  std::abs(int(normal[center] & 255) - 230) < 3,
              "custom shader did not receive mapped view-space normal");
        auto mirrored       = h.Load(root / "mirrored_uv.glb");
        auto mirroredNormal = h.Run(camera, [&] { submit(mirrored); });
        Check(std::abs(int((mirroredNormal[center] >> 16) & 255) - 51) < 3,
              "mirrored UV handedness is wrong");
        [mirrored release];
        for (const char *kind : {"tilted", "tangent", "skin", "blend", "mask", "unlit"})
        {
          auto model  = h.Load(root / (std::string(kind) + ".glb"));
          auto shared = [model newInstance];
          Check(shared.parts[0].normalTexture == model.parts[0].normalTexture,
                "instance duplicated normal texture");
          [model setAnimationTime:.3f];
          for (float mirror : {-1.f, 1.f})
          {
            std::array<Instance, 2> placements;
            placements[0]   = {{-.5f, 0, .5f}, {0, 0, .2f}, {mirror * .6f, .4f, 1}, {1, 1, 1, 1}};
            placements[1]   = {{.5f, 0, .5f}, {0, 0, -.2f}, {-mirror * .6f, .4f, 1}, {1, 1, 1, 1}};
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
            Check(
                individual ==
                    h.Run(camera, [&] { [h.draw drawModelInstances:model instances:placements]; }),
                "mapped mirrored/scaled/skinned instancing differs");
          }
          [shared release];
          [model release];
        }
        [flat release];
        [tilted release];
      }
      [device release];
      std::puts("normal mapping: linear texture, lighting, disable, UV/tangent, degenerate, "
                "custom, shared, mirrored/skinned instances passed");
      return 0;
    }
    catch (const std::exception &e)
    {
      std::fprintf(stderr, "FAIL: %s\n", e.what());
      return 1;
    }
  }
}
