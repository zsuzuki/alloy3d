#include "../tests/render_harness.h"
#include "../samples/open_world/world.h"
#include "../samples/open_world/materials.h"
#include <fstream>
#include <unordered_set>
#include <mach/mach.h>

static void Save(const Pixels &pixels, NSUInteger size, const std::string &path)
{
  std::ofstream out(path, std::ios::binary);
  out << "P6\n" << size << ' ' << size << "\n255\n";
  for (auto pixel : pixels)
    for (int channel : {16, 8, 0})
    {
      float c = float((pixel >> channel) & 255) / 255;
      c       = c <= .0031308f ? c * 12.92f : 1.055f * std::pow(c, 1 / 2.4f) - .055f;
      out.put(char(std::clamp(int(std::round(c * 255)), 0, 255)));
    }
  Check(bool(out), "cannot save snapshot");
}
using World = open_world::World<MetalModel>;
static size_t Resources(const World &world)
{
  std::unordered_set<void *> seen;
  size_t                     bytes = 0;
  @autoreleasepool
  {
    for (auto model : world.Models())
      for (ModelPart *part in model.get().parts)
        for (id<MTLResource> resource in [part resources])
          if (seen.insert((void *)resource).second)
            bytes += resource.allocatedSize;
  }
  return bytes;
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 4, "usage: open_world_probe shaders assets output-prefix");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness     h(device, argv[1], 1000, 2);
        std::string shaderError;
        auto        waterShader = [h.draw createModelMaterialShader:open_world::RiverMaterial
                                                        diagnostics:shaderError];
        Check(bool(waterShader), "river shader failed");
        auto grassShader = [h.draw createModelShader:open_world::GrassSurface
                                         diagnostics:shaderError];
        Check(bool(grassShader), "grass shader failed");
        [h.draw setModelTextureSampling:(alloy3d::ModelTextureSampling3D{4, true})];
        h.clearColor = MTLClearColorMake(.48, .66, .79, 1);
        [h.draw setFrustumCulling:true];
        [h.draw setShadowCulling:true];
        [h.draw setDirectionalLight:(alloy3d::DirectionalLight3D{
                                        {-.5f, -1, .3f}, {1, .96f, .86f}, .3f, .8f})];
        [h.draw setHemisphereLight:(alloy3d::HemisphereLight3D{
                                       true, {.7f, .82f, 1}, {.25f, .3f, .15f}, {0, 1, 0}, .3f})];
        [h.draw setFog:(alloy3d::Fog3D{true, {.48f, .66f, .79f}, 2000, 6000})];
        World world(argv[2],
                    [&](const auto &path)
                    {
                      @autoreleasepool
                      {
                        auto model = h.Load(path);
                        return World::Ptr(model, [](MetalModel *p) { [p release]; });
                      }
                    });
        // Two identical circuits: validate bounded residency and stable resource
        // memory after the hysteresis ring has settled, including all four edges.
        const auto                       bridge     = world.landscape.bridges.front();
        const std::array<simd_float3, 9> route      = {world.landscape.Spawn(),
                                                       {bridge.x - 38, 0, bridge.z - 35},
                                                       {bridge.x - 235, 0, bridge.z + 8},
                                                       {bridge.x + 140, 0, bridge.z + 75},
                                                       {4050, 0, 2420},
                                                       {4990, 0, 4990},
                                                       {10, 0, 4990},
                                                       {10, 0, 10},
                                                       world.landscape.Spawn()};
        const std::array<simd_float3, 9> directions = {simd_float3{1, -.04f, 0},
                                                       {1, -.06f, .4f},
                                                       {0, -.04f, 1},
                                                       {1, -.03f, 0},
                                                       {-1, -.35f, -.5f},
                                                       {-1, -.08f, -1},
                                                       {1, -.08f, -1},
                                                       {1, -.08f, 1},
                                                       {1, -.04f, 0}};
        std::ofstream                    csv(std::string(argv[3]) + ".csv");
        csv << "round,stop,resident,loaded,evicted,resource_bytes,placement_bytes,footprint_bytes,"
               "encode_ms,gpu_ms\n";
        size_t   previousEnd   = 0;
        uint64_t peakFootprint = 0;
        for (int round = 0; round < 2; ++round)
          for (unsigned stop = 0; stop < route.size(); ++stop)
          {
            @autoreleasepool
            {
              auto eye = route[stop];
              eye.y    = world.landscape.WalkHeight(eye.x, eye.z) + 1.8f;
              alloy3d::CameraData camera;
              camera.buildPerspective(.95f, 1, .5f, 7500);
              camera.buildModelView(eye, eye + directions[stop], {0, 1, 0});
              alloy3d::DirectionalShadow3D shadow;
              shadow.enabled    = true;
              shadow.resolution = 1024;
              shadow.bounds    = {eye - simd_float3{180, 45, 180}, eye + simd_float3{180, 65, 180}};
              shadow.stabilize = true;
              [h.draw setDirectionalShadow:shadow];
              Pixels     pixels;
              const auto timeout = std::chrono::steady_clock::now() + std::chrono::seconds(15);
              unsigned   frames  = 0;
              do
              {
                @autoreleasepool
                {
                  world.Update(eye, .1f);
                  pixels = h.Run(
                      camera,
                      [&]
                      {
                        world.Draw(
                            camera,
                            [&](auto model, auto instances, auto visibility, auto style)
                            {
                              [h.draw setModelShader:style == World::Water   ? waterShader
                                                     : style == World::Grass ? grassShader
                                                                             : nullptr
                                          parameters:(simd_float4{0, 0, 0, 0})];
                              [h.draw
                                  setModelHighlight:(alloy3d::ModelHighlight3D{
                                                        style == World::Water ? .55f : 0.f, 80})];
                              [h.draw setModelVisibility:visibility];
                              [h.draw drawModelInstances:model.get() instances:instances];
                            });
                      });
                }
                Check(world.Stats().failed == 0, "world asset loading failed");
                Check(world.Stats().resident < 80 && world.Stats().pending <= 4,
                      "world residency exceeded bounds");
                Check(std::chrono::steady_clock::now() < timeout, "streaming did not settle");
                ++frames;
              } while (frames < 12 || world.Stats().pending);
              auto                   s     = world.Stats();
              const size_t           bytes = Resources(world);
              task_vm_info_data_t    info{};
              mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
              task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count);
              peakFootprint = std::max(peakFootprint, info.phys_footprint);
              csv << round << ',' << stop << ',' << s.resident << ',' << s.loaded << ','
                  << s.evicted << ',' << bytes << ',' << world.PlacementBytes() << ','
                  << info.phys_footprint << ',' << h.encodeMs << ',' << h.gpuMs << '\n';
              if (round == 0 && stop < 5)
                Save(pixels, h.size, std::string(argv[3]) + "-" + std::to_string(stop) + ".ppm");
              if (stop == route.size() - 1)
              {
                if (round == 0)
                  previousEnd = bytes;
                else
                  Check(bytes == previousEnd, "resource bytes grew after identical world circuit");
              }
              Check(s.resident > 0, "detailed cells never became resident");
              Check(world.frame.detailCells + world.frame.farCells > 0, "nothing rendered");
            }
          }
        Check(world.Stats().evicted > 0, "route never unloaded a cell");
        std::printf("world: two circuits passed; resident=%zu loaded=%llu evicted=%llu "
                    "resource_MiB=%.2f peak_footprint_MiB=%.2f\n",
                    world.Stats().resident,
                    (unsigned long long)world.Stats().loaded,
                    (unsigned long long)world.Stats().evicted,
                    Resources(world) / 1048576.,
                    peakFootprint / 1048576.);
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
