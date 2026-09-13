// Bake the sample's own crown meshes into eight transparent azimuth views.
#include "../samples/forest/scene.h"
#include "../tests/render_harness.h"
#include <fstream>

static void SavePNG(const Pixels &pixels, NSUInteger size, const std::filesystem::path &path)
{
  auto bitmap =
      [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
                                              pixelsWide:size
                                              pixelsHigh:size
                                           bitsPerSample:8
                                         samplesPerPixel:4
                                                hasAlpha:YES
                                                isPlanar:NO
                                          colorSpaceName:NSDeviceRGBColorSpace
                                            bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                                             bytesPerRow:size * 4
                                            bitsPerPixel:32];
  auto   bytes   = bitmap.bitmapData;
  size_t covered = 0;
  for (size_t i = 0; i < pixels.size(); ++i)
  {
    for (int c = 0; c < 3; ++c)
    {
      float value = float((pixels[i] >> (16 - c * 8)) & 255) / 255;
      value = value <= .0031308f ? value * 12.92f : 1.055f * std::pow(value, 1 / 2.4f) - .055f;
      bytes[i * 4 + c] = std::clamp(int(std::round(value * 255)), 0, 255);
    }
    bytes[i * 4 + 3] = (pixels[i] >> 24) & 255;
    covered += bytes[i * 4 + 3] > 0;
  }
  Check(covered > pixels.size() / 100 && covered < pixels.size() * 3 / 4,
        "invalid billboard coverage");
  auto data = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
  Check([data writeToFile:[NSString stringWithUTF8String:path.c_str()] atomically:YES],
        "cannot write billboard PNG");
  [bitmap release];
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 4,
            "usage: bake_forest_billboards shaders.metallib forest-assets output-directory");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness       h(device, argv[1], 768);
        forest::Scene scene;
        [h.draw setDirectionalLight:scene.Light()];
        [h.draw setHemisphereLight:scene.Ambient()];
        // Keep baked lighting, but no fog or projected forest shadows in the texture.
        std::string error;
        auto        leaf = [h.draw createModelShader:forest::LeafShader diagnostics:error];
        Check(bool(leaf), error.c_str());
        auto root = std::filesystem::path(argv[2]), output = std::filesystem::path(argv[3]);
        std::filesystem::create_directories(output);
        std::ofstream metadata(output / "frames.json");
        metadata << "[\n";
        for (size_t variant = 0; variant < 3; ++variant)
        {
          auto wood =
              h.Load(root / (std::string(forest::Assets[forest::Crowns[variant]]) + ".glb"));
          auto foliage =
              h.Load(root / (std::string(forest::Assets[forest::Foliage[variant]]) + ".glb"));
          alloy3d::Bounds3D wb, fb;
          Check([wood getBounds:&wb] && [foliage getBounds:&fb], "missing crown bounds");
          auto  lo = simd_min(wb.min, fb.min), hi = simd_max(wb.max, fb.max);
          float radius = std::hypot(std::max(std::abs(lo.x), std::abs(hi.x)),
                                    std::max(std::abs(lo.z), std::abs(hi.z)));
          float size   = std::max(radius * 2, hi.y - lo.y) * 1.04f;
          float center = (lo.y + hi.y) * .5f;
          metadata << (variant ? ",\n" : "") << "{\"size\":" << size << ",\"center_y\":" << center
                   << "}";
          alloy3d::CameraData camera;
          camera.buildOrthographic(size, 1, .1f, 80);
          for (int view = 0; view < 8; ++view)
          {
            float angle = float(view) * 6.28318530718f / 8;
            camera.buildModelView(
                {std::sin(angle) * 30, center, std::cos(angle) * 30}, {0, center, 0}, {0, 1, 0});
            auto pixels = h.Run(
                camera,
                [&]
                {
                  alloy3d::ModelInstance instance;
                  [h.draw setModelShader:nullptr parameters:simd_float4{}];
                  [h.draw drawModelInstances:wood
                                   instances:std::span<const alloy3d::ModelInstance>(&instance, 1)];
                  [h.draw setModelShader:leaf parameters:simd_float4{}];
                  [h.draw drawModelInstances:foliage
                                   instances:std::span<const alloy3d::ModelInstance>(&instance, 1)];
                });
            SavePNG(pixels,
                    h.size,
                    output / ("crown_" + std::to_string(variant + 1) + "_" + std::to_string(view) +
                              ".png"));
          }
          [wood release];
          [foliage release];
        }
        metadata << "\n]\n";
        Check(bool(metadata), "cannot write billboard frames");
      }
      [device release];
      std::puts("PASS: 24 transparent crown views baked from original meshes");
      return 0;
    }
    catch (const std::exception &e)
    {
      std::fprintf(stderr, "FAIL: %s\n", e.what());
      return 1;
    }
  }
}
