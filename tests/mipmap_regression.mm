#include "render_harness.h"
#include <fstream>

static void Submit(Harness &h, MetalModel *model, float scale = 1.31f, float x = 0)
{
  [h.draw drawModel:model
           position:{x, 0, .4f}
           rotation:{0, 0, 0}
              scale:{scale, scale, scale}
              color:{1, 1, 1, 1}];
}
static uint64_t Hash(const Pixels &pixels)
{
  uint64_t hash = 1469598103934665603ull;
  for (auto p : pixels)
  {
    hash ^= p;
    hash *= 1099511628211ull;
  }
  return hash;
}
static double Variation(const Pixels &pixels)
{
  double sum = 0;
  for (int y = 80; y < 176; ++y)
    for (int x = 80; x < 176; ++x)
      sum += std::pow(double(pixels[y * 256 + x] & 255) - 127.5, 2);
  return std::sqrt(sum / (96 * 96));
}
static void Probe(Harness &h, MetalModel *checker, const std::string &prefix)
{
  alloy3d::CameraData camera;
  auto                near  = h.Run(camera, [&] { Submit(h, checker, 12); });
  double              error = 0, motion = 0;
  Pixels              previous;
  for (int i = 0; i < 12; ++i)
  {
    auto pixels = h.Run(camera, [&] { Submit(h, checker, 1.31f, float(i) * .0021f); });
    error += Variation(pixels);
    if (!previous.empty())
      for (int y = 80; y < 176; ++y)
        for (int x = 80; x < 176; ++x)
          motion += std::abs(int(pixels[y * 256 + x] & 255) - int(previous[y * 256 + x] & 255));
    if (i == 0)
    {
      std::ofstream out(prefix + ".ppm", std::ios::binary);
      out << "P6\n256 256\n255\n";
      for (auto p : pixels)
        for (int shift : {16, 8, 0})
          out.put(char((p >> shift) & 255));
      Check(bool(out), "cannot write probe image");
    }
    previous = std::move(pixels);
  }
  std::printf("mips=%lu near_hash=%016llx minification_RMS=%.3f motion_mean_delta=%.3f\n",
              (unsigned long)checker.parts[0].texture.mipmapLevelCount,
              (unsigned long long)Hash(near),
              error / 12,
              motion / (11 * 96 * 96));
}
static void Test(Harness &h, const std::filesystem::path &root)
{
  auto checker = h.Load(root / "checker.glb");
  auto npot    = h.Load(root / "npot.glb");
  auto single  = h.Load(root / "single.glb");
  auto dense   = h.Load(root / "mask_dense.glb");
  auto sparse  = h.Load(root / "mask_sparse.glb");
  Check(checker.parts[0].texture.mipmapLevelCount == 11, "1024 texture mip chain missing");
  Check(npot.parts[0].texture.mipmapLevelCount == 5, "non-power-of-two mip chain missing");
  Check(single.parts[0].texture.mipmapLevelCount == 1, "1x1 texture acquired extra levels");
  auto texture = checker.parts[0].texture;
  Check(texture.pixelFormat == MTLPixelFormatRGBA8Unorm_sRGB ||
            texture.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB,
        "base color lost sRGB decoding");
  // Verify every level was initialized before the loader returned, on a separate queue.
  auto bytes    = [h.device newBufferWithLength:11 * 256 options:MTLResourceStorageModeShared];
  auto commands = [h.queue commandBuffer];
  auto blit     = [commands blitCommandEncoder];
  for (NSUInteger level = 0; level < 11; ++level)
    [blit copyFromTexture:texture
                     sourceSlice:0
                     sourceLevel:level
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(1, 1, 1)
                        toBuffer:bytes
               destinationOffset:level * 256
          destinationBytesPerRow:256
        destinationBytesPerImage:256];
  [blit endEncoding];
  [commands commit];
  [commands waitUntilCompleted];
  Check(commands.status == MTLCommandBufferStatusCompleted, "mip readback failed");
  auto data = static_cast<const uint8_t *>(bytes.contents);
  for (NSUInteger level = 1; level < 11; ++level)
    Check(std::abs(int(data[level * 256]) - 188) <= 3 && data[level * 256 + 3] == 255,
          "mip generation was incomplete or averaged sRGB instead of linear color");
  [bytes release];

  alloy3d::CameraData camera;
  auto                far = h.Run(camera, [&] { Submit(h, checker); });
  Check(Variation(far) < 3, "minified checker still aliases");
  auto near = h.Run(camera, [&] { Submit(h, checker, 12); });
  Check(Variation(near) > 20, "magnification lost original texture detail");
  auto flat     = h.Run(camera, [&] { Submit(h, npot); });
  auto onePixel = h.Run(camera, [&] { Submit(h, single); });
  Check(flat == onePixel, "NPOT mipmapped solid color differs from 1x1 texture");
  auto shared = [checker newInstance];
  Check(shared.parts[0].texture == texture, "shared model duplicated mipmaps");
  Check(far == h.Run(camera, [&] { Submit(h, shared); }), "shared mipmapped model differs");

  std::string error;
  auto        identity = [h.draw
      createModelShader:"float3 alloy3dShade(ModelSurface s, float4 p) { return s.litColor; }"
            diagnostics:error];
  Check(bool(identity), "mipmap custom shader failed to compile");
  [h.draw setModelShader:identity parameters:{}];
  Check(far == h.Run(camera, [&] { Submit(h, checker); }), "custom mipmap sampling differs");
  [h.draw setModelShader:{} parameters:{}];
  std::array<Instance, 2> placements;
  placements[0].position = {-.4f, 0, .4f};
  placements[1].position = {.4f, 0, .4f};
  placements[0].scale = placements[1].scale = {.7, .7, .7};
  auto individual                           = h.Run(camera,
                                                    [&]
                                                    {
                            for (auto &i : placements)
                              [h.draw drawModel:checker
                                       position:i.position
                                       rotation:i.rotation
                                          scale:i.scale
                                          color:i.color];
                                                    });
  Check(individual ==
                h.Run(camera, [&] { [h.draw drawModelInstances:checker instances:placements]; }) &&
            [h.draw modelDrawCallCount] == 1,
        "mipmaps changed instancing output/batching");

  // Document the ordinary alpha-average policy: 75% stays, 25% falls below cutoff.
  auto densePixels  = h.Run(camera, [&] { Submit(h, dense, .04); });
  auto sparsePixels = h.Run(camera, [&] { Submit(h, sparse, .04); });
  Check((densePixels[128 * 256 + 128] >> 24) == 255, "dense MASK vanished in mipmaps");
  Check(sparsePixels[128 * 256 + 128] == 0, "sparse MASK no longer follows averaged alpha cutoff");
  // The shadow pass also minifies MASK alpha rather than sampling only level 0.
  camera.buildModelView({0, 0, 5}, {0, 0, 0}, {0, 1, 0});
  camera.buildOrthographic(4, 1, .1, 20);
  [h.draw setLightDirection:{.8f, 0, -1} ambient:.2f diffuse:.8f];
  alloy3d::DirectionalShadow3D shadow;
  shadow.enabled    = true;
  shadow.resolution = 128;
  shadow.bounds     = {{-2, -2, -.2f}, {2, 2, 2}};
  shadow.depthBias  = .002f;
  [h.draw setDirectionalShadow:shadow];
  auto scene = [&](MetalModel *caster)
  {
    [h.draw drawPlane:{-2, -2, 0} p1:{2, -2, 0} p2:{2, 2, 0} p3:{-2, 2, 0} color:{1, 1, 1, 1}];
    if (caster)
      [h.draw drawModel:caster
               position:{-.3f, 0, 1}
               rotation:{0, 0, 0}
                  scale:{.4, .4, .4}
                  color:{1, 1, 1, 1}];
  };
  auto noCaster     = h.Run(camera, [&] { scene(nil); });
  auto denseShadow  = h.Run(camera, [&] { scene(dense); });
  auto sparseShadow = h.Run(camera, [&] { scene(sparse); });
  Check((denseShadow[128 * 256 + 160] & 255) < 80, "minified dense MASK did not cast shadow");
  Check(noCaster == sparseShadow, "sparse MASK leaves a shadow after vanishing in color pass");
  for (auto model : {checker, npot, single, dense, sparse, shared})
    [model release];
  std::puts("mipmap: complete levels, linear RGB, minification, magnification, NPOT, 1x1, "
            "shared/custom/instances, MASK passed");
}
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3 || (argc == 5 && std::string_view(argv[3]) == "--probe"),
            "usage: mipmap_regression shaders.metallib fixtures [--probe output-prefix]");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness h(device, argv[1]);
        if (argc == 5)
        {
          auto checker = h.Load(std::filesystem::path(argv[2]) / "checker.glb");
          Probe(h, checker, argv[4]);
          [checker release];
        }
        else
          Test(h, argv[2]);
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
