// Same scene can be compiled against the previous library with ALLOY3D_ENV_BASELINE.
#include "../tests/render_harness.h"
#include <fstream>

static void Save(const Pixels &pixels, NSUInteger size, const std::string &path)
{
  std::ofstream out(path, std::ios::binary);
  out << "P6\n" << size << ' ' << size << "\n255\n";
  for (auto pixel : pixels)
    for (int shift : {16, 8, 0})
    {
      // Harness stores linear RGB; encode for a normal image viewer.
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
      Check(argc == 4, "usage: environment_probe shaders.metallib model.glb output-prefix");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness             h(device, argv[1], 1536);
        auto                model = h.Load(argv[2]);
        alloy3d::CameraData camera;
        camera.buildModelView({9, 7, 15}, {0, 1, -5}, {0, 1, 0});
        camera.buildPerspective(.85, 1, .1, 100);
        [h.draw setLightDirection:{-.4f, -.8f, -.5f} ambient:.25 diffuse:.75];
        std::vector<Instance> placements;
        for (int row = 0; row < 12; ++row)
          for (int col = 0; col < 12; ++col)
          {
            Instance i;
            i.position = {float(col) * 2 - 11, .75f, -float(row) * 2};
            i.scale    = {.55f, .75f, .55f};
            i.color    = {.7f, .75f, .8f, 1};
            placements.push_back(i);
          }
        const auto submit = [&]
        {
          [h.draw drawPlane:{-20, -.1f, 8}
                         p1:{20, -.1f, 8}
                         p2:{20, -.1f, -40}
                         p3:{-20, -.1f, -40}
                      color:{.25, .28, .32, 1}];
          [h.draw drawModelInstances:model instances:placements];
          [h.draw drawSphere:{-2, 1.5f, 3} radius:1.5 color:{.75, .35, .15, 1} slices:48 stacks:24];
          [h.draw drawSphere:{2, 1.5f, 3} radius:1.5 color:{.2, .5, .8, 1} slices:48 stacks:24];
        };
        std::printf("device=%s resolution=1536x1536 instances=144 shadows=OFF\n",
                    device.name.UTF8String);
        for (int mode = 0; mode < 4; ++mode)
        {
#ifdef ALLOY3D_ENV_BASELINE
          if (mode != 0)
            break;
#else
          alloy3d::Fog3D fog;
          fog.enabled = (mode & 1) != 0;
          fog.color   = {0, 0, 0}; // Match the offscreen clear color.
          fog.start   = 14;
          fog.end     = 48;
          [h.draw setFog:fog];
          alloy3d::HemisphereLight3D light;
          light.enabled = (mode & 2) != 0;
          [h.draw setHemisphereLight:light];
#endif
          std::vector<double> gpu, cpu;
          Pixels              last;
          for (int frame = 0; frame < 100; ++frame)
          {
            @autoreleasepool
            {
              last = h.Run(camera, submit);
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
                      gpu[gpu.size() / 2],
                      gpu[gpu.size() * 95 / 100],
                      cpu[cpu.size() / 2],
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
