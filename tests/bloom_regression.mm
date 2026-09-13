#include "render_harness.h"
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: bloom_regression shaders.metallib fixtures");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      for (NSUInteger samples : {1u, 4u})
      {
        Harness             h(device, argv[1], 129, samples, true);
        alloy3d::CameraData camera;
        auto                model = h.Load(std::filesystem::path(argv[2]) / "unlit.glb");
        std::string         error;
        auto                shader = [h.draw
            createModelShader:"float3 alloy3dShade(ModelSurface s,float4 p){return float3(4);}"
                  diagnostics:error];
        Check(bool(shader), error.c_str());
        [h.draw setModelShader:shader parameters:{}];
        auto submit = [&]
        {
          [h.draw drawModel:model
                   position:{0, 0, .3f}
                   rotation:{}
                      scale:{.6f, .6f, 1}
                      color:{1, 1, 1, 1}];
        };
        alloy3d::PostProcessing3D settings{.1f, alloy3d::ToneMapping3D::None};
        h.post->set(settings);
        auto reference = h.Run(camera, submit);
        auto baseBytes = h.post->bytes();
        settings.bloom = {.5f, 1, 4};
        h.post->set(settings);
        auto glow = h.Run(camera, submit);
        Check(h.post->bytes() > baseBytes, "bloom buffers missing from memory accounting");
        size_t glowPixels = 0;
        for (size_t i = 0; i < glow.size(); ++i)
        {
          glowPixels += (reference[i] & 0xffffff) == 0 && (glow[i] & 0xffffff) > 0;
          Check((reference[i] >> 24) == (glow[i] >> 24), "bloom changed alpha coverage");
        }
        Check(glowPixels > 50, "bloom did not spread outside bright geometry");
        settings.bloom.threshold = 64;
        h.post->set(settings);
        Check(reference == h.Run(camera, submit), "below-threshold content bloomed");
        settings.bloom.strength = 0;
        h.post->set(settings);
        Check(reference == h.Run(camera, submit), "bloom off changed pixels");
        h.post->releaseUnusedMemory();
        h.Run(camera, submit);
        Check(h.post->bytes() == baseBytes, "bloom targets were retained after release/reuse");
        bool rejected         = false;
        settings.bloom.radius = 0;
        try
        {
          h.post->set(settings);
        }
        catch (const std::invalid_argument &)
        {
          rejected = true;
        }
        Check(rejected, "zero bloom radius was accepted");
        [model release];
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
