#include "render_harness.h"

static void Individual(Draw3D *draw, MetalModel *model, std::span<const Instance> instances)
{
  for (const auto &i : instances)
    [draw drawModel:model position:i.position rotation:i.rotation scale:i.scale color:i.color];
}
static void Visible(const Pixels &pixels)
{
  Check(std::count_if(pixels.begin(), pixels.end(), [](auto p) { return (p & 0xffffff) != 0; }) >
            20,
        "reference has no visible geometry");
}

static void TestNormals(Harness &h, const std::filesystem::path &root)
{
  // Analytic normal from transformed surface tangents, independent of inverse transpose code.
  auto matrix         = matrix_identity_float4x4;
  matrix.columns[0].x = 2;
  matrix.columns[1].y = .5;
  matrix.columns[2].z = -1.5;
  auto u = simd_make_float3(1, -1, 0), v = simd_make_float3(1, 1, -2);
  auto normal      = simd_normalize(simd_cross(u, v));
  auto transformed = simd_normalize(simd_mul(alloy3d::metal::NormalMatrix(matrix), normal));
  auto tu          = simd_mul(matrix, simd_make_float4(u, 0)).xyz;
  auto tv          = simd_mul(matrix, simd_make_float4(v, 0)).xyz;
  Check(std::fabs(simd_dot(transformed, tu)) < 1e-5 && std::fabs(simd_dot(transformed, tv)) < 1e-5,
        "normal not perpendicular after nonuniform scale");
  matrix.columns[2].z = 0;
  auto degenerate     = simd_mul(alloy3d::metal::NormalMatrix(matrix), normal);
  Check(simd_length_squared(degenerate) == 0, "singular transform must have finite zero normal");

  const auto light = simd_normalize(simd_make_float3(1, .3, .1));
  [h.draw setLightDirection:-light ambient:.15 diffuse:.7];
  for (const char *name : {"normals.glb", "skinned_normals.glb"})
  {
    auto model = h.Load(root / name);
    for (float sign : {1.f, -1.f})
    {
      Instance i;
      i.scale             = {sign * .8f, .6f, .5f};
      i.position.z        = .3;
      auto expectedNormal = simd_normalize(
          simd_make_float3(1 / (sign * .8f * .8f), 1 / (.6f * 1.2f), 1 / (.5f * .6f)));
      int expected =
          std::lround(255 * (.15f + .7f * std::max(0.f, simd_dot(expectedNormal, light))));
      for (int view = 0; view < 2; ++view)
      {
        alloy3d::CameraData camera;
        if (view)
          camera.buildModelView({.6f, .2f, 2.f}, {0, 0, .4f}, {0, 1, 0});
        if (view)
          camera.buildPerspective(.9f, 1, .1f, 10);
        auto pixels = h.Run(camera, [&] { Individual(h.draw, model, {&i, 1}); });
        Visible(pixels);
        for (auto pixel : pixels)
          if (pixel & 0xffffff)
            for (int channel = 0; channel < 3; ++channel)
              Check(std::abs(int((pixel >> (8 * channel)) & 255) - expected) <= 2,
                    "GPU normal/light-space result differs from analytic intensity");
        auto batch = h.Run(camera, [&] { [h.draw drawModelInstances:model instances:{&i, 1}]; });
        Check(pixels == batch, "single-instance normal path differs");
      }
    }
    [model release];
  }
}

static std::vector<Instance> Placements(int count)
{
  std::vector<Instance> result(count);
  int                   columns = static_cast<int>(std::ceil(std::sqrt(count)));
  for (int n = 0; n < count; ++n)
  {
    auto &i      = result[n];
    float step   = 1.8f / columns;
    i.position   = {-.9f + (n % columns + .5f) * step, -.9f + (n / columns + .5f) * step, .25f};
    i.scale      = {step, step * .8f, step};
    i.rotation.z = (n % 3) * .15f;
    i.color      = {.4f + .1f * (n % 5), .6f, .9f, 1};
  }
  return result;
}

static void TestInstances(Harness &h, const std::filesystem::path &root)
{
  alloy3d::CameraData camera;
  [h.draw setLightDirection:{0, 0, -1} ambient:1 diffuse:0];
  for (const char *name :
       {"normals.glb", "opaque_parts.glb", "transparent_parts.glb", "textured_parts.glb"})
  {
    auto model     = h.Load(root / name);
    auto list      = Placements(9);
    auto reference = h.Run(camera, [&] { Individual(h.draw, model, list); });
    Visible(reference);
    const auto calls = [h.draw modelDrawCallCount];
    auto       batch = h.Run(camera, [&] { [h.draw drawModelInstances:model instances:list]; });
    Check(reference == batch, "instanced pixels differ from individual draws");
    bool transparent = std::strcmp(name, "transparent_parts.glb") == 0 ||
                       std::strcmp(name, "textured_parts.glb") == 0;
    Check([h.draw modelDrawCallCount] == (transparent ? calls : model.parts.count),
          "draw calls were not batched/fallback correctly");
    // Overlap placements, use alpha, mix scalar and two batch requests, then mutate input.
    list.resize(3);
    for (int n = 0; n < 3; ++n)
    {
      list[n].position = {n * .08f, 0, .3f - n * .03f};
      list[n].scale    = {1, 1, 1};
      list[n].color.w  = .5;
    }
    reference = h.Run(camera, [&] { Individual(h.draw, model, list); });
    batch     = h.Run(camera,
                      [&]
                      {
                    [h.draw drawModelInstances:model instances:std::span(list).first(1)];
                    Individual(h.draw, model, std::span(list).subspan(1, 1));
                    [h.draw drawModelInstances:model instances:std::span(list).last(1)];
                    for (auto &i : list)
                      i.position.x = 50;
                      });
    Check(reference == batch, "mixed submissions/input lifetime changed draw order");
    [model release];
  }
  auto textured     = h.Load(root / "textured_parts.glb");
  auto texturedCopy = [textured newInstance];
  Check(textured.parts[0].texture != nil &&
            textured.parts[0].texture == texturedCopy.parts[0].texture,
        "textured clone did not share a real texture");
  [textured release];
  auto texturedPixels = h.Run(camera, [&] { Individual(h.draw, texturedCopy, Placements(4)); });
  Visible(texturedPixels);
  auto retainedPixels = h.Run(camera,
                              [&]
                              {
                                auto pending = [texturedCopy newInstance];
                                [h.draw drawModelInstances:pending instances:Placements(4)];
                                [pending release]; // Only the queued request owns this model now.
                              });
  Check(texturedPixels == retainedPixels, "queued request did not retain its model");
  [texturedCopy release];
  auto model = h.Load(root / "normals.glb");
  auto empty = h.Run(camera, [&] { [h.draw drawModelInstances:model instances:{}]; });
  Check([h.draw modelDrawCallCount] == 0 &&
            std::all_of(empty.begin(), empty.end(), [](auto p) { return (p & 0xffffff) == 0; }),
        "empty batch drew geometry");
  [h.draw drawModelInstances:model instances:Placements(10)];
  [h.draw discardFrame];
  h.Run(camera, [] {});
  Check([h.draw modelDrawCallCount] == 0, "discarded instances remained queued");

  // Three distinct pages in flight, growth, release, and regrowth. Encode all before commit.
  std::array<Pixels, 3> expected;
  for (int phase = 0; phase < 3; ++phase)
  {
    for (int slot = 0; slot < 3; ++slot)
    {
      h.Begin(slot);
      auto list = Placements(phase == 1 ? 9 : 10000);
      for (auto &i : list)
        i.color = {.3f + .2f * slot, .7f, .9f, 1};
      [h.draw drawModelInstances:model instances:list];
      if (slot == 0 && phase == 0)
        [h.draw releaseUnusedMemory]; // queued CPU data stays valid
      h.Encode(slot, camera);
      Check([h.draw modelDrawCallCount] == 1, "large batch did not use one draw call");
    }
    for (auto command : h.commands)
      [command commit];
    for (int slot = 0; slot < 3; ++slot)
    {
      auto pixels = h.Read(slot);
      Visible(pixels);
      if (phase == 0)
        expected[slot] = pixels;
      if (phase == 2)
        Check(expected[slot] == pixels, "regrown instance page changed pixels");
    }
    auto bytes = [h.draw memoryStats].instanceBufferBytes;
    if (phase == 0)
    {
      Check(bytes > 1000000, "instance buffers did not grow");
      [h.draw releaseUnusedMemory];
    }
    if (phase == 1)
      Check(bytes < 200000 && ![h.draw memoryStats].releasePending,
            "instance pages did not shrink");
  }
  Check(expected[0] != expected[1] && expected[1] != expected[2], "frame data was overwritten");
  [model release];
}

static std::vector<simd_float4x4> Pose(MetalModel *model)
{
  std::vector<simd_float4x4> result([model rigCount]);
  for (NSUInteger i = 0; i < result.size(); ++i)
    Check([model rigTransformAtIndex:i transform:&result[i]], "rig missing");
  return result;
}
static bool SamePose(const std::vector<simd_float4x4> &a, const std::vector<simd_float4x4> &b)
{
  return a.size() == b.size() &&
         std::memcmp(a.data(), b.data(), a.size() * sizeof(simd_float4x4)) == 0;
}
static void TestSharing(Harness &h, const std::filesystem::path &rig)
{
  auto source = h.Load(rig);
  [source setAnimationBlendFrom:0 timeA:.7 to:1 timeB:1.3 weight:.4];
  auto saved = Pose(source);
  auto a     = [source newInstance];
  auto b     = [a newInstance];
  Check([a sharesAssetWith:source] && [b sharesAssetWith:source], "asset metadata was copied");
  Check(SamePose(Pose(a), saved) && SamePose(Pose(b), saved),
        "clone did not preserve blended pose");
  for (NSUInteger part = 0; part < source.parts.count; ++part)
  {
    auto p = source.parts[part], q = a.parts[part];
    Check(p != q && p.vertexBuffer == q.vertexBuffer && p.indexBuffer == q.indexBuffer &&
              p.texture == q.texture,
          "geometry/texture resources were not shared");
    for (int page = 0; page < 3; ++page)
    {
      auto x = [p jointMatrixBufferForPage:page], y = [q jointMatrixBufferForPage:page];
      Check(x != y && x.length == y.length && std::memcmp(x.contents, y.contents, x.length) == 0,
            "clone joint pages were shared or initial pose changed");
    }
  }
  [a setAnimationIndex:0];
  [a setAnimationTime:1];
  Check(!SamePose(Pose(a), saved) && SamePose(Pose(source), saved) && SamePose(Pose(b), saved),
        "independent animation changed another instance");
  [source release];
  [a release];
  Check(SamePose(Pose(b), saved), "source destruction invalidated clone");
  alloy3d::CameraData camera;
  Instance            i;
  i.scale       = {.8, .8, .8};
  i.position.z  = .5;
  auto original = h.Run(camera, [&] { Individual(h.draw, b, {&i, 1}); });
  Visible(original);
  [b setAnimationIndex:1];
  [b setAnimationTime:2];
  auto updated = h.Run(camera, [&] { [h.draw drawModelInstances:b instances:{&i, 1}]; });
  Check(original != updated, "surviving clone cannot animate/render");
  [b release];
}

static void Benchmark(Harness &h, const std::filesystem::path &root)
{
  auto                model = h.Load(root / "normals.glb");
  alloy3d::CameraData camera;
  for (int count : {1000, 10000})
  {
    auto list = Placements(count);
    for (bool batch : {false, true})
    {
      std::vector<double> submit, encode, gpu;
      for (int run = 0; run < 60; ++run)
      {
        @autoreleasepool
        {
          h.Run(camera,
                [&]
                {
                  if (batch)
                    [h.draw drawModelInstances:model instances:list];
                  else
                    Individual(h.draw, model, list);
                });
          if (run >= 10)
          {
            submit.push_back(h.submitMs);
            encode.push_back(h.encodeMs);
            gpu.push_back(h.gpuMs);
          }
        }
      }
      auto median = [](auto v)
      {
        std::sort(v.begin(), v.end());
        return v[v.size() / 2];
      };
      std::printf("%s count=%d calls=%lu submit_ms=%.4f encode_ms=%.4f gpu_ms=%.4f\n",
                  batch ? "instanced" : "individual",
                  count,
                  (unsigned long)[h.draw modelDrawCallCount],
                  median(submit),
                  median(encode),
                  median(gpu));
    }
  }
  [model release];
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    if (argc < 4)
      return 2;
    try
    {
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness h(device, argv[1]);
        TestNormals(h, argv[2]);
        TestInstances(h, argv[2]);
        TestSharing(h, argv[3]);
        if (argc > 4 && std::strcmp(argv[4], "--benchmark") == 0)
          Benchmark(h, argv[2]);
        std::puts("PASS: analytic normals, camera-independent lighting, instancing/order, 3 "
                  "pages/shrink/regrow, shared resources and independent animation");
      }
      [device release];
    }
    catch (const std::exception &e)
    {
      std::fprintf(stderr, "FAIL: %s\n", e.what());
      return 1;
    }
  }
}
