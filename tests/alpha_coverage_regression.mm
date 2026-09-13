#include "render_harness.h"
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: alpha_coverage_regression shaders.metallib fixtures");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      for (NSUInteger samples : {1u, 4u})
      {
        Harness             h(device, argv[1], 256, samples);
        alloy3d::CameraData camera;
        auto                root = std::filesystem::path(argv[2]);
        auto model = h.Load(root / "mask_equal.glb"), opaque = h.Load(root / "opaque_alpha.glb"),
             blend = h.Load(root / "blend_red.glb");
        for (bool custom : {false, true})
        {
          std::string error;
          auto        shader =
              custom
                  ? [h.draw createModelShader:
                                "float3 alloy3dShade(ModelSurface s,float4 p){return s.litColor;}"
                                  diagnostics:error]
                  : nullptr;
          Check(!custom || bool(shader), error.c_str());
          [h.draw setModelShader:shader parameters:{}];
          auto draw = [&](MetalModel *m, float alpha = 1)
          {
            [h.draw drawModel:m
                     position:{0, 0, .5f}
                     rotation:{}
                        scale:{1, 1, 1}
                        color:{1, 1, 1, alpha}];
          };
          [h.draw setModelTextureSampling:{1, false}];
          auto reference = h.Run(camera, [&] { draw(model); });
          [h.draw setModelTextureSampling:{1, true}];
          auto smooth = h.Run(camera, [&] { draw(model); });
          if (samples == 1)
            Check(reference == smooth, "A2C changed single-sample fallback");
          else
          {
            int green = (smooth[128 * 256 + 128] >> 8) & 255;
            Check(green >= 120 && green <= 136,
                  "half-alpha MASK did not cover half of MSAA samples");
            Check(((smooth[128 * 256 + 128] >> 24) & 255) == green,
                  "covered sample alpha was not restored to one");
          }
          auto composite = h.Run(camera,
                                 [&]
                                 {
                                   draw(model);
                                   [h.draw drawModel:opaque
                                            position:{0, 0, .7f}
                                            rotation:{}
                                               scale:{1, 1, 1}
                                               color:{1, 1, 1, 1}];
                                 });
          if (samples > 1)
          {
            auto p = composite[128 * 256 + 128];
            Check(std::abs(int((p >> 16) & 255) - 128) <= 2 &&
                      std::abs(int((p >> 8) & 255) - 128) <= 2 && (p >> 24) == 255,
                  "uncovered MASK samples blocked opaque background depth");
          }
          Instance instance{{0, 0, .5f}, {}, {1, 1, 1}, {1, 1, 1, 1}};
          Check(smooth ==
                    h.Run(camera,
                          [&]
                          { [h.draw drawModelInstances:model instances:std::span(&instance, 1)]; }),
                "A2C instances differ from scalar");
          for (auto m : {opaque, blend})
          {
            [h.draw setModelTextureSampling:{1, false}];
            auto before = h.Run(camera, [&] { draw(m); });
            [h.draw setModelTextureSampling:{1, true}];
            Check(before == h.Run(camera, [&] { draw(m); }), "A2C changed OPAQUE or BLEND");
          }
          [h.draw setModelTextureSampling:{1, false}];
          auto faded = h.Run(camera, [&] { draw(model, .5f); });
          [h.draw setModelTextureSampling:{1, true}];
          Check(faded == h.Run(camera, [&] { draw(model, .5f); }),
                "A2C double-faded transparent placement");
        }
        [model release];
        [opaque release];
        [blend release];
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
