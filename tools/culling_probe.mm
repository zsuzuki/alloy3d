#include "../tests/render_harness.h"

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: culling_probe shaders model");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      Harness             h(device, argv[1]);
      auto                model = h.Load(argv[2]);
      alloy3d::CameraData camera;
      camera.buildPerspective(.9f, 1, .1f, 200);
      camera.buildModelView({0, 10, 30}, {0, 0, 0}, {0, 1, 0});
      std::vector<Instance> instances;
      for (int i = 0; i < 20000; ++i)
        instances.push_back({{float(i % 200 - 100) * 8, 0, float(i / 200 - 50) * 8},
                             {0, i * .013f, 0},
                             {1, 1, 1},
                             {1, 1, 1, 1}});
      [h.draw setFrustumCulling:true];
      std::vector<double> encode, gpu;
      uint64_t            hash = 0;
      for (int frame = 0; frame < 80; ++frame)
      {
        auto pixels = h.Run(camera, [&] { [h.draw drawModelInstances:model instances:instances]; });
        if (frame >= 10)
        {
          encode.push_back(h.encodeMs);
          gpu.push_back(h.gpuMs);
        }
        hash = 1469598103934665603ull;
        for (auto pixel : pixels)
        {
          hash ^= pixel;
          hash *= 1099511628211ull;
        }
      }
      std::sort(encode.begin(), encode.end());
      std::sort(gpu.begin(), gpu.end());
      std::printf("encode_median_ms=%.4f gpu_median_ms=%.4f hash=%016llx\n",
                  encode[encode.size() / 2],
                  gpu[gpu.size() / 2],
                  (unsigned long long)hash);
      [model release];
      [device release];
      return 0;
    }
    catch (const std::exception &e)
    {
      std::fprintf(stderr, "%s\n", e.what());
      return 1;
    }
  }
}
