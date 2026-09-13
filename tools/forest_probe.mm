#include "../samples/forest/scene.h"
#include "../tests/render_harness.h"
#include <cstdlib>
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
      Check(argc == 4, "usage: forest_probe shaders.metallib forest-asset-directory output-prefix");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        const char *samplesEnv = std::getenv("ALLOY3D_FOREST_SAMPLES");
        NSUInteger samples = samplesEnv ? std::strtoul(samplesEnv, nullptr, 10) : 1;
        Check(samples == 1 || samples == 2 || samples == 4 || samples == 8, "invalid forest samples");
        Harness h(device, argv[1], 1000, samples);
        [h.draw setTransparentBatching:true];
        const char *anisotropyEnv = std::getenv("ALLOY3D_FOREST_ANISOTROPY");
        uint32_t anisotropy = anisotropyEnv ? std::strtoul(anisotropyEnv, nullptr, 10) : 8;
        [h.draw setModelTextureSampling:(alloy3d::ModelTextureSampling3D{anisotropy})];
        h.clearColor =
            MTLClearColorMake(forest::SkyColor.x, forest::SkyColor.y, forest::SkyColor.z, 1);
        forest::Scene       scene;
        alloy3d::CameraData camera;
        scene.Camera(camera, 1);
        std::array<MetalModel *, forest::Assets.size()> models{};
        for (size_t i = 0; i < models.size(); ++i)
          models[i] =
              h.Load(std::filesystem::path(argv[2]) / (std::string(forest::Assets[i]) + ".glb"));
        for (auto asset : {forest::Ground,
                           forest::Tree,
                           forest::Tree2,
                           forest::Tree3,
                           forest::Crown,
                           forest::Crown2,
                           forest::Crown3,
                           forest::CrownLod,
                           forest::CrownLod2,
                           forest::CrownLod3,
                           forest::Rock})
        {
          auto texture = models[asset].parts[0].texture;
          Check(texture && texture.width > 1 && texture.height > 1,
                "forest surface albedo missing");
          auto levels =
              NSUInteger(std::floor(std::log2(std::max(texture.width, texture.height)))) + 1;
          Check(texture.mipmapLevelCount == levels, "forest albedo mip chain missing");
          Check(texture.pixelFormat == MTLPixelFormatRGBA8Unorm_sRGB ||
                    texture.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB,
                "forest albedo lost sRGB decoding");
        }
        for (size_t asset = forest::BillboardBegin; asset < forest::Droplet; ++asset)
        {
          auto part = models[asset].parts[0];
          Check(part.alphaMode == 1 && part.unlit && part.texture.mipmapLevelCount > 1,
                "billboard lost cutout material or mipmaps");
        }
        std::string error;
        auto        ground = [h.draw createModelShader:forest::GroundShader diagnostics:error];
        Check(bool(ground), error.c_str());
        auto leaf = [h.draw createModelShader:forest::LeafShader diagnostics:error];
        Check(bool(leaf), error.c_str());
        auto water = [h.draw createModelShader:forest::WaterShader diagnostics:error];
        Check(bool(water), error.c_str());
        [h.draw setDirectionalLight:scene.Light()];
        [h.draw setHemisphereLight:scene.Ambient()];
        [h.draw setFog:scene.Fog()];
        [h.draw setDirectionalShadow:scene.Shadow()];
        Check(models[forest::Droplet].parts[0].alphaMode == 2 &&
                  models[forest::Droplet].parts[0].unlit,
              "droplet lost translucent glint material");
        bool waterOnly = false, dropsOnly = false;
        auto render = [&](float time)
        {
          [h.draw setHeightFog:scene.HeightFog()];
          [h.draw setModelNormalMapping:(alloy3d::ModelNormalMapping3D{scene.settings.normalMaps ? 1.f : 0.f})];
          scene.Animate(time, camera.getEyePosition());
          std::array<std::span<const alloy3d::ModelInstance>, forest::Assets.size()> placements;
          scene.Draw([&](size_t asset, auto instances) { placements[asset] = instances; });
          for (size_t variant = 0; variant < forest::Crowns.size() * 2; ++variant)
          {
            auto wood    = placements[variant < 3 ? forest::Crowns[variant]
                                                  : forest::DistantCrowns[variant - 3]];
            auto foliage = placements[variant < 3 ? forest::Foliage[variant]
                                                  : forest::DistantFoliage[variant - 3]];
            Check(wood.size() == foliage.size(), "unpaired forest crown");
            for (size_t i = 0; i < wood.size(); ++i)
              Check(simd_all(wood[i].position == foliage[i].position) &&
                        simd_all(wood[i].rotation == foliage[i].rotation) &&
                        simd_all(wood[i].scale == foliage[i].scale),
                    "wind detached leaves from branches");
          }
          return h.Run(
              camera,
              [&]
              {
                scene.Draw(
                    [&](size_t asset, std::span<const alloy3d::ModelInstance> instances)
                    {
                      if (waterOnly && asset != forest::Water)
                        return;
                      if (dropsOnly && asset != forest::Droplet)
                        return;
                      [h.draw setModelTextureTransform:scene.TextureTransform(asset)];
                      [h.draw setModelTransmission:(alloy3d::ModelTransmission3D{scene.settings.transmission && forest::IsFoliage(asset) ? .45f : 0.f,
                                                                                {.75f, 1.f, .4f}})];
                      [h.draw setModelMaterialDetail:(alloy3d::ModelMaterialDetail3D{scene.settings.materialDetail && (asset == forest::Ground || asset == forest::Rock)})];
                      [h.draw setModelShader:asset == forest::Water     ? water
                                             : asset == forest::Ground  ? ground
                                             : forest::IsFoliage(asset) ? leaf
                                                                        : nullptr
                                  parameters:(simd_float4{asset == forest::Water ? scene.waterTime
                                                                                 : scene.time,
                                                          scene.settings.shafts ? 1.f : 0.f,
                                                          0,
                                                          0})];
                      [h.draw setModelHighlight:(alloy3d::ModelHighlight3D{
                                                    asset == forest::Rock     ? .20f
                                                    : asset == forest::Ground ? .10f
                                                                              : .035f,
                                                    48})];
                      [h.draw drawModelInstances:models[asset] instances:instances];
                    });
              });
        };
        auto first = render(0);
        auto batchedDraws = [h.draw modelDrawCallCount];
        [h.draw setTransparentBatching:false];
        Check(first == render(0), "transparent batching changed forest pixels");
        auto scalarDraws = [h.draw modelDrawCallCount];
        Check(batchedDraws < scalarDraws, "transparent batching did not reduce forest draws");
        std::printf("transparent batching: %lu -> %lu model draws\n", (unsigned long)scalarDraws, (unsigned long)batchedDraws);
        [h.draw setTransparentBatching:true];
        scene.settings.normalMaps = false;
        auto noNormals = render(0);
        Check(first != noNormals, "forest normal maps did not affect lighting");
        Save(noNormals, h.size, std::string(argv[3]) + "-no-normals.ppm");
        scene.settings.normalMaps = true;
        Check(first == render(0), "normal toggle did not restore forest");
        scene.settings.materialDetail = false;
        auto noDetail = render(0);
        Check(first != noDetail, "forest material detail did not affect lighting");
        Save(noDetail, h.size, std::string(argv[3]) + "-no-detail.ppm");
        scene.settings.materialDetail = true;
        Check(first == render(0), "material detail toggle did not restore forest");
        scene.settings.transmission = false;
        auto noTransmission = render(0);
        Check(first != noTransmission, "forest backlighting did not affect leaves");
        Save(noTransmission, h.size, std::string(argv[3]) + "-no-transmission.ppm");
        scene.settings.transmission = true;
        Check(first == render(0), "transmission toggle did not restore forest");
        scene.settings.heightFog = false;
        auto noHeightFog = render(0);
        Check(first != noHeightFog, "height fog did not affect forest");
        Save(noHeightFog, h.size, std::string(argv[3]) + "-no-height-fog.ppm");
        scene.settings.heightFog = true;
        Check(first == render(0), "height fog toggle did not restore forest");
        // Check placed root tips against the terrain, including uneven river banks.
        scene.Draw(
            [&](size_t asset, auto instances)
            {
              if (std::find(forest::Trunks.begin(), forest::Trunks.end(), asset) ==
                  forest::Trunks.end())
                return;
              for (const auto &tree : instances)
                for (float radius : {1.3f, 1.7f, 2.1f})
                  for (int i = 0; i < 48; ++i)
                  {
                    float angle = i * 6.28318530718f / 48;
                    float ground =
                        forest::Height(tree.position.x + std::cos(angle) * radius * tree.scale.x,
                                       tree.position.z + std::sin(angle) * radius * tree.scale.z);
                    Check(tree.position.y + .04f * tree.scale.y <= ground,
                          "root tips are suspended above terrain");
                  }
            });
        auto checkForestHorizon = [&](const Pixels &pixels)
        {
          size_t sky = 0, total = 0;
          for (NSUInteger y = h.size * 54 / 100; y < h.size * 70 / 100; ++y)
            for (NSUInteger x = h.size * 12 / 100; x < h.size * 88 / 100; ++x)
            {
              auto pixel = pixels[y * h.size + x];
              bool clear = true;
              for (int c = 0; c < 3; ++c)
                clear &= std::abs(int((pixel >> (16 - c * 8)) & 255) -
                                  int(std::round(forest::SkyColor[c] * 255))) <= 1;
              sky += clear;
              ++total;
            }
          Check(sky * 500 < total, "open sky visible between distant trunk bases");
        };
        checkForestHorizon(first);
        Save(first, h.size, std::string(argv[3]) + "-0.ppm");
        auto later = render(2);
        Save(later, h.size, std::string(argv[3]) + "-2.ppm");
        Check(first != later, "forest animation did not change the image");
        Check(render(2) == later, "same forest time is not deterministic");
        auto detailCounts = [&]
        {
          std::array<size_t, 4> counts{};
          scene.Draw(
              [&](size_t asset, auto instances)
              {
                for (size_t variant = 0; variant < forest::Trunks.size(); ++variant)
                {
                  if (forest::IsBillboard(asset) && variant == 0)
                    counts[3] += instances.size();
                  if (asset == forest::Trunks[variant])
                    counts[0] += instances.size();
                  if (asset == forest::Crowns[variant])
                    counts[1] += instances.size();
                  if (asset == forest::DistantCrowns[variant])
                    counts[2] += instances.size();
                }
              });
          Check(counts[0] == counts[1] + counts[2] + counts[3],
                "tree disappeared during detail selection");
          return counts;
        };
        auto initialDetail = detailCounts();
        Check(initialDetail[1] > 0 && initialDetail[2] > 0 && initialDetail[3] > 0,
              "missing forest detail levels");
        scene.travel = 8;
        scene.Camera(camera, 1);
        Check(render(2) != later, "forest camera did not advance");
        Check(detailCounts() != initialDetail, "tree detail did not follow camera");
        scene.travel = 0;
        scene.Camera(camera, 1);
        Check(render(2) == later, "returning camera changed forest layout or wind");
        std::printf("trees=%zu near=%zu middle=%zu billboards=%zu\n",
                    initialDetail[0],
                    initialDetail[1],
                    initialDetail[2],
                    initialDetail[3]);
        scene.settings.billboards = false;
        Check(render(2) != later, "billboard toggle has no visible effect");
        Check(detailCounts()[3] == 0, "billboard toggle left sprites active");
        scene.settings.billboards = true;
        Check(render(2) == later, "billboard toggle changed layout or animation");
        scene.yaw = .6f;
        scene.Camera(camera, 1);
        auto turned = render(2);
        checkForestHorizon(turned);
        Save(turned, h.size, std::string(argv[3]) + "-turned.ppm");
        detailCounts();
        Check(turned != later, "billboard camera turn has no visible effect");
        scene.yaw = 0;
        scene.Camera(camera, 1);
        Check(render(2) == later, "camera turn changed billboard view selection");
        scene.settings.wind = false;
        auto noWind         = render(2);
        Check(noWind != later, "wind toggle has no visible effect");
        scene.settings.wind   = true;
        scene.settings.shafts = false;
        auto noShafts         = render(2);
        Save(noShafts, h.size, std::string(argv[3]) + "-no-shafts.ppm");
        Check(noShafts != later, "sunlight toggle has no visible effect");
        scene.settings.shafts = true;
        scene.settings.fog    = false;
        [h.draw setFog:scene.Fog()];
        Check(render(2) != later, "fog toggle has no visible effect");
        scene.settings.fog = true;
        [h.draw setFog:scene.Fog()];
        scene.settings.shadows = false;
        [h.draw setDirectionalShadow:scene.Shadow()];
        Check(render(2) != later, "shadow toggle has no visible effect");
        scene.settings.shadows = true;
        [h.draw setDirectionalShadow:scene.Shadow()];
        waterOnly = true;
        camera.buildModelView({forest::StreamCenter(8) + 1.5f, 1.5f, 14},
                              {forest::StreamCenter(8), forest::WaterLevel(8), 8},
                              {0, 1, 0});
        auto waterStart = render(2);
        auto waterLater = render(3);
        Check(waterStart != waterLater, "water flow has no visible effect");
        scene.settings.flow = false;
        Check(render(4) == waterLater, "stopped water keeps moving");
        scene.settings.flow = true;
        Check(render(5) != waterLater, "water flow did not resume");
        waterOnly = false;
        Save(render(2), h.size, std::string(argv[3]) + "-water-detail.ppm");
        dropsOnly      = true;
        auto dropStart = render(2);
        auto dropLater = render(2.15f);
        Check(dropStart != dropLater, "droplets do not hop");
        Check(render(2.15f) == dropLater, "paused droplets are not deterministic");
        scene.settings.flow = false;
        Check(render(2.3f) == dropLater, "droplets keep moving with stopped stream");
        scene.settings.flow = true;
        Check(render(2.45f) != dropLater, "droplets did not resume");
        auto dropsOn          = render(2.45f);
        scene.settings.shafts = false;
        Check(render(2.45f) == dropsOn, "sunlight toggle hides stream droplets");
        scene.settings.shafts   = true;
        scene.settings.droplets = false;
        Check(render(2.45f) != dropsOn, "droplet toggle has no visible effect");
        scene.settings.droplets = true;
        Check(render(2.45f) == dropsOn, "droplet toggle changes particle timing");
        dropsOnly              = false;
        size_t maxDrops        = 0;
        size_t highDropSamples = 0, dropSamples = 0;
        float  maxDropHeight = 0;
        for (int frame = 0; frame < 600; ++frame)
        {
          scene.Animate(3.f + frame / 60.f, camera.getEyePosition());
          scene.Draw(
              [&](size_t asset, auto instances)
              {
                if (asset != forest::Droplet)
                  return;
                maxDrops = std::max(maxDrops, instances.size());
                Check(instances.size() <= forest::DropletCapacity,
                      "particle pool grew beyond its limit");
                for (const auto &drop : instances)
                {
                  auto  p      = drop.position;
                  float height = p.y - forest::WaterLevel(p.z);
                  Check(std::isfinite(height) && height >= 0 && height < .165f,
                        "droplet escaped gentle water-surface hop");
                  ++dropSamples;
                  highDropSamples += height > .08f;
                  maxDropHeight = std::max(maxDropHeight, height);
                  Check(std::abs(p.x - forest::StreamCenter(p.z)) < forest::StreamWidth(p.z),
                        "droplet landed on dry bank");
                }
              });
        }
        Check(maxDropHeight > .14f && highDropSamples > 0, "higher splash patterns are missing");
        Check(highDropSamples * 5 < dropSamples, "higher splashes overwhelm the low droplets");
        std::printf("droplet hops: maximum %.1fcm, %.1f%% of samples above 8cm\n",
                    maxDropHeight * 100.f,
                    100.0 * highDropSamples / dropSamples);
        std::printf("droplets: %zu bounded slots, maximum %zu active over 10 seconds\n",
                    forest::DropletCapacity,
                    maxDrops);
        // Check concentration at separated viewpoints, plus world anchoring across
        // a camera move while time is frozen (a moving particle cloud must not slide).
        forest::Scene concentration;
        auto          collectDrops = [&](float seconds, simd_float3 eye)
        {
          concentration.Animate(seconds, eye);
          std::vector<alloy3d::ModelInstance> drops;
          concentration.Draw(
              [&](size_t asset, auto instances)
              {
                if (asset == forest::Droplet)
                  drops.assign(instances.begin(), instances.end());
              });
          return drops;
        };
        for (float z : {14.f, 6.f, -12.f})
        {
          simd_float3 eye  = {forest::StreamCenter(z) + 2.f, 2.25f, z};
          size_t      near = 0, middle = 0, far = 0;
          for (int frame = 0; frame < 600; ++frame)
            for (const auto &drop : collectDrops(frame / 60.f, eye))
            {
              simd_float2 delta = {drop.position.x - eye.x, drop.position.z - eye.z};
              if (simd_length(delta) < 10.f)
                ++near;
              else if (simd_length(delta) < 20.f)
                ++middle;
              else
                ++far;
            }
          Check(middle > near / 3, "droplets do not reach the middle distance");
          Check(near > middle / 2 && near + middle > far * 3,
                "droplet density does not follow the camera");
          std::printf("droplet concentration: camera z=%.1f, near=%.1f%% middle=%.1f%%\n",
                      z,
                      100.0 * near / (near + middle + far),
                      100.0 * middle / (near + middle + far));
          auto before = collectDrops(3.f, eye);
          eye.z -= .1f;
          auto after = collectDrops(3.f, eye);
          for (const auto &drop : before)
          {
            simd_float2 delta = {drop.position.x - eye.x, drop.position.z - eye.z};
            if (simd_length(delta) >= 6.f)
              continue;
            Check(std::any_of(after.begin(),
                              after.end(),
                              [&](const auto &other)
                              { return simd_length(other.position - drop.position) < .0001f; }),
                  "camera motion dragged a visible droplet");
          }
        }
        for (int frame = 0; frame < 3; ++frame)
          Save(render(3.f + frame * .12f),
               h.size,
               std::string(argv[3]) + "-drops-" + std::to_string(frame) + ".ppm");
        scene.settings.droplets = false;
        Save(render(3.f), h.size, std::string(argv[3]) + "-no-drops.ppm");
        scene.settings.droplets = true;
        if (std::getenv("ALLOY3D_FOREST_CAPTURE_DROPLETS"))
          for (int frame = 0; frame < 48; ++frame)
            Save(render(3.f + frame / 12.f),
                 h.size,
                 std::string(argv[3]) + "-drop-motion-" + std::to_string(frame) + ".ppm");
        camera.buildModelView({-3.3f, 1.7f, 8}, {-5.3f, 1.2f, 5}, {0, 1, 0});
        Save(render(2), h.size, std::string(argv[3]) + "-bark.ppm");
        camera.buildModelView({2, 1.5f, 12}, {2.5f, .5f, 9}, {0, 1, 0});
        Save(render(2), h.size, std::string(argv[3]) + "-ground-rock.ppm");
        scene.Camera(camera, 1);
        std::vector<double> gpu, cpu;
        for (int i = 0; i < 36; ++i)
        {
          render(2 + i / 60.f);
          if (i >= 6)
          {
            gpu.push_back(h.gpuMs);
            cpu.push_back(h.submitMs + h.encodeMs);
          }
        }
        std::sort(gpu.begin(), gpu.end());
        std::sort(cpu.begin(), cpu.end());
        std::printf(
            "forest device=%s size=%lux%lu gpu_median_ms=%.3f cpu_median_ms=%.3f draws=%lu\n",
            device.name.UTF8String,
            (unsigned long)h.size,
            (unsigned long)h.size,
            gpu[gpu.size() / 2],
            cpu[cpu.size() / 2],
            (unsigned long)[h.draw modelDrawCallCount]);
        std::printf("PASS: assets, sRGB albedo/mipmaps, shaders, deterministic time, animation, "
                    "wind, sunlight, fog, "
                    "shadows, grounded roots, forest horizon, water flow/pause/resume, attached "
                    "crown motion, camera detail selection, droplet hops/toggle/pause/resume\n");
        scene.settings.droplets = false;
        gpu.clear();
        for (int i = 0; i < 36; ++i)
        {
          render(2 + i / 60.f);
          if (i >= 6)
            gpu.push_back(h.gpuMs);
        }
        std::sort(gpu.begin(), gpu.end());
        std::printf("same forest, droplets OFF gpu_median_ms=%.3f\n", gpu[gpu.size() / 2]);
        scene.settings.droplets   = true;
        scene.settings.billboards = false;
        Save(render(2), h.size, std::string(argv[3]) + "-no-billboards.ppm");
        gpu.clear();
        for (int i = 0; i < 24; ++i)
        {
          render(2 + i / 60.f);
          if (i >= 6)
            gpu.push_back(h.gpuMs);
        }
        std::sort(gpu.begin(), gpu.end());
        std::printf("same canopy, billboards OFF gpu_median_ms=%.3f\n", gpu[gpu.size() / 2]);
        scene.settings.billboards = true;
        // Inspect each complete tree separately from forest composition and fog.
        [h.draw setFog:alloy3d::Fog3D{}];
        camera.buildModelView({11, 7, 15}, {0, 6, 0}, {0, 1, 0});
        for (size_t variant = 0; variant < forest::Trunks.size(); ++variant)
        {
          auto specimen = h.Run(
              camera,
              [&]
              {
                [h.draw setModelTextureTransform:alloy3d::ModelTextureTransform3D{}];
                for (auto asset :
                     {forest::Trunks[variant], forest::Crowns[variant], forest::Foliage[variant]})
                {
                  [h.draw setModelShader:forest::IsFoliage(asset) ? leaf : nullptr
                              parameters:simd_float4{}];
                  [h.draw setModelHighlight:(alloy3d::ModelHighlight3D{.035f, 48})];
                  alloy3d::ModelInstance instance;
                  instance.position.y = asset == forest::Trunks[variant] ? 0 : 4;
                  [h.draw drawModelInstances:models[asset]
                                   instances:std::span<const alloy3d::ModelInstance>(&instance, 1)];
                }
              });
          Save(specimen,
               h.size,
               std::string(argv[3]) + "-tree-" + std::to_string(variant + 1) + ".ppm");
        }
        for (auto model : models)
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
