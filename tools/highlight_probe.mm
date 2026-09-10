#include "../tests/render_harness.h"
#include <fstream>

static void Save(const Pixels &pixels, NSUInteger size, const std::string &path)
{
  std::ofstream out(path, std::ios::binary);
  out << "P6\n" << size << ' ' << size << "\n255\n";
  for (auto pixel : pixels)
    for (int shift : {16, 8, 0})
    {
      float c = float((pixel >> shift) & 255) / 255;
      c       = c <= .0031308f ? c * 12.92f : 1.055f * std::pow(c, 1 / 2.4f) - .055f;
      out.put(char(std::clamp(int(std::round(c * 255)), 0, 255)));
    }
  Check(bool(out), "cannot write preview");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 4, "usage: highlight_probe shaders.metallib sphere.glb output-prefix");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness             h(device, argv[1], 1536);
        auto                model = h.Load(argv[2]);
        alloy3d::CameraData camera;
        camera.buildModelView({0, 0, 4}, {0, 0, 0}, {0, 1, 0});
        camera.buildPerspective(.65, 1, .1, 20);
        [h.draw setLightDirection:{-.5f, -.6f, -1} ambient:.2f diffuse:.7f];
        std::printf("device=%s resolution=1536x1536 sphere=3968 triangles shadows=OFF\n",
                    device.name.UTF8String);
        for (int mode = 0; mode < 3; ++mode)
        {
#ifdef ALLOY3D_HIGHLIGHT_BASELINE
          if (mode != 0)
            break;
#else
          [h.draw setModelHighlight:(alloy3d::ModelHighlight3D{mode == 0   ? 0.f
                                                               : mode == 1 ? .3f
                                                                           : .8f,
                                                               mode == 2 ? 96.f : 32.f})];
#endif
          std::vector<double> gpu, cpu;
          Pixels              last;
          for (int frame = 0; frame < 100; ++frame)
          {
            @autoreleasepool
            {
              last = h.Run(camera,
                           [&]
                           {
                             [h.draw drawModel:model
                                      position:{0, 0, 0}
                                      rotation:{0, 0, 0}
                                         scale:{1, 1, 1}
                                         color:{1, 1, 1, 1}];
                           });
              if (frame >= 20)
              {
                gpu.push_back(h.gpuMs);
                cpu.push_back(h.submitMs + h.encodeMs);
              }
            }
          }
          std::sort(gpu.begin(), gpu.end());
          std::sort(cpu.begin(), cpu.end());
          uint64_t hash = 1469598103934665603ull;
          for (auto p : last)
          {
            hash ^= p;
            hash *= 1099511628211ull;
          }
          std::printf("mode=%d gpu_median_ms=%.4f gpu_p95_ms=%.4f cpu_median_ms=%.4f draws=%lu "
                      "hash=%016llx\n",
                      mode,
                      gpu[40],
                      gpu[76],
                      cpu[40],
                      (unsigned long)[h.draw modelDrawCallCount],
                      (unsigned long long)hash);
          Save(last, h.size, std::string(argv[3]) + "-" + std::to_string(mode) + ".ppm");
        }
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
