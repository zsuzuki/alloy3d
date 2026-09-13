#include "../application/src/render_options.h"
#include "render_harness.h"

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: msaa_regression shaders.metallib material-directory");
      using alloy3d::internal::SelectSampleCount;
      Check(SelectSampleCount(8, [](auto n) { return n == 4; }) == 4, "MSAA fallback failed");
      Check(SelectSampleCount(4, [](auto) { return false; }) == 1, "MSAA fallback to 1 failed");
      for (auto n : {0u, 3u, 16u})
      {
        bool rejected = false;
        try
        {
          SelectSampleCount(n, [](auto) { return true; });
        }
        catch (const std::invalid_argument &)
        {
          rejected = true;
        }
        Check(rejected, "invalid MSAA setting accepted");
      }
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      for (NSUInteger samples : {1u, 2u, 4u, 8u})
      {
        if (![device supportsTextureSampleCount:samples])
          continue;
        Harness             h(device, argv[1], 256, samples);
        alloy3d::CameraData camera;
        [h.draw setLightDirection:{0, 0, -1} ambient:1 diffuse:0];
        auto   triangle = h.Run(camera,
                                [&]
                                {
                                [h.draw drawTriangle:{-.8f, -.7f, .5f}
                                                  p1:{.7f, -.6f, .5f}
                                                  p2:{-.3f, .8f, .5f}
                                               color:{1, 1, 1, 1}];
                                });
        size_t partial  = 0;
        for (auto pixel : triangle)
          if ((pixel & 255) > 0 && (pixel & 255) < 255)
            ++partial;
        Check(samples == 1 ? partial == 0 : partial > 100, "MSAA did not resolve edge coverage");
        auto        root   = std::filesystem::path(argv[2]);
        auto        opaque = h.Load(root / "opaque_alpha.glb");
        auto        mask   = h.Load(root / "mask_checker.glb");
        auto        blend  = h.Load(root / "blend_red.glb");
        std::string error;
        auto        shader = [h.draw
            createModelShader:"float3 alloy3dShade(ModelSurface s, float4 p) { return s.litColor; }"
                  diagnostics:error];
        Check(bool(shader), error.c_str());
        alloy3d::DirectionalShadow3D shadow;
        shadow.enabled = true;
        [h.draw setDirectionalShadow:shadow];
        std::array<Instance, 2> instances;
        instances[0].position = {-.45f, .1f, .5f};
        instances[1].position = {.4f, -.1f, .5f};
        instances[0].scale = instances[1].scale = {.55f, .55f, .55f};
        instances[0].rotation.z = instances[1].rotation.z = .31f;
        for (auto model : {opaque, mask, blend})
        {
          [h.draw setModelShader:{} parameters:{}];
          auto reference =
              h.Run(camera, [&] { [h.draw drawModelInstances:model instances:instances]; });
          [h.draw setModelShader:shader parameters:{}];
          auto custom =
              h.Run(camera, [&] { [h.draw drawModelInstances:model instances:instances]; });
          Check(reference == custom, "MSAA custom material/shadow output differs");
          Check(reference == h.Run(camera,
                                   [&]
                                   {
                                     for (const auto &i : instances)
                                       [h.draw drawModel:model
                                                position:i.position
                                                rotation:i.rotation
                                                   scale:i.scale
                                                   color:i.color];
                                   }),
                "MSAA instance output differs");
          [model release];
        }
        std::printf("MSAA %lu: %zu partial edge pixels; material/custom/instances/shadows passed\n",
                    (unsigned long)samples,
                    partial);
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
