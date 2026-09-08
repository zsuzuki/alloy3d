#include <algorithm>
#include <alloy3d/camera.h>
#import <alloy3d/metal/draw3d.h>
#import <alloy3d/metal/model.h>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <new>
#include <stdexcept>
#include <vector>

// Count C++ allocations on this thread only, inside warmed-up animation calls.
// This does not claim to count Objective-C / Metal allocations or process RSS.
static thread_local bool   countAllocations = false;
static thread_local size_t allocations      = 0;
void                      *operator new(size_t size)
{
  if (countAllocations)
    ++allocations;
  if (void *p = std::malloc(size ? size : 1))
    return p;
  throw std::bad_alloc();
}
void *operator new[](size_t size) { return ::operator new(size); }
void  operator delete(void *p) noexcept { std::free(p); }
void  operator delete[](void *p) noexcept { std::free(p); }
void  operator delete(void *p, size_t) noexcept { std::free(p); }
void  operator delete[](void *p, size_t) noexcept { std::free(p); }
void *operator new(size_t size, std::align_val_t alignment)
{
  if (countAllocations)
    ++allocations;
  void *p = nullptr;
  if (posix_memalign(&p, static_cast<size_t>(alignment), size ? size : 1) == 0)
    return p;
  throw std::bad_alloc();
}
void *operator new[](size_t size, std::align_val_t a) { return ::operator new(size, a); }
void  operator delete(void *p, std::align_val_t) noexcept { std::free(p); }
void  operator delete[](void *p, std::align_val_t) noexcept { std::free(p); }
void  operator delete(void *p, size_t, std::align_val_t) noexcept { std::free(p); }
void  operator delete[](void *p, size_t, std::align_val_t) noexcept { std::free(p); }

static void Check(bool condition, const char *message)
{
  if (!condition)
    throw std::runtime_error(message);
}

struct Request
{
  NSUInteger a, b;
  float      ta, tb, weight;
  bool       blend;
};

static void Apply(MetalModel *model, const Request &r)
{
  if (r.blend)
    [model setAnimationBlendFrom:r.a timeA:r.ta to:r.b timeB:r.tb weight:r.weight];
  else
  {
    [model setAnimationIndex:r.a];
    [model setAnimationTime:r.ta];
  }
}

struct Transform
{
  simd_float3 translation, scale;
  float       angle;
};

// Independent analytic oracle for the generated planar strands, including the
// library's existing normalized quaternion interpolation (not a new interpolator).
static Transform Pose(int joint, int count, NSUInteger clip, float seconds)
{
  int       strand = joint / 5, segment = joint % 5;
  int       columns = std::min(8, count / 5);
  Transform result{{0, .15f, 0}, {1, 1, 1}, 0};
  if (segment == 0)
    result.translation =
        simd_make_float3((strand % columns - (columns - 1) / 2.0f) * .4f,
                         (strand / columns - ((count / 5 - 1) / columns) / 2.0f) * .85f,
                         0);
  float t = std::fmod(std::max(0.0f, seconds), clip == 0 ? 2.0f : 3.0f);
  if (clip == 0)
  {
    float f      = t < 1 ? t : 2 - t;
    float angle  = joint % 2 == 0 ? .18f : -.18f;
    result.angle = 2 * std::atan2(f * std::sin(angle / 2), 1 + f * (std::cos(angle / 2) - 1));
  }
  else
  {
    if (t >= 1.5f)
      result.translation += simd_make_float3(.02, .03, 0);
    float f      = t < 1.5f ? t / 1.5f : (3 - t) / 1.5f;
    result.scale = simd_make_float3(1 + .02f * f, 1 - .02f * f, 1);
  }
  return result;
}

static simd_float4x4 Translation(simd_float3 t)
{
  auto m       = matrix_identity_float4x4;
  m.columns[3] = simd_make_float4(t, 1);
  return m;
}

static simd_float4x4 Local(Transform t)
{
  const float c = std::cos(t.angle), s = std::sin(t.angle);
  return simd_matrix(simd_make_float4(c * t.scale.x, s * t.scale.x, 0, 0),
                     simd_make_float4(-s * t.scale.y, c * t.scale.y, 0, 0),
                     simd_make_float4(0, 0, t.scale.z, 0),
                     simd_make_float4(t.translation, 1));
}

static void MatrixEqual(simd_float4x4 actual, simd_float4x4 expected)
{
  for (int col = 0; col < 4; ++col)
    for (int row = 0; row < 4; ++row)
      Check(std::isfinite(actual.columns[col][row]) &&
                std::fabs(actual.columns[col][row] - expected.columns[col][row]) < .00002f,
            "matrix differs from analytic fixture pose");
}

static void Append(std::vector<char> &output, const void *data, size_t size)
{
  const char *p = static_cast<const char *>(data);
  output.insert(output.end(), p, p + size);
}

static void VerifyPose(MetalModel *model, int count, const Request &r, std::vector<char> &capture)
{
  Apply(model, r);
  const auto                 root = Translation(simd_make_float3(.1, -.1, 0));
  std::vector<simd_float4x4> world(count);
  for (int i = 0; i < count; ++i)
  {
    auto a = Pose(i, count, r.a, r.ta);
    if (r.blend)
    {
      auto  b = Pose(i, count, r.b, r.tb);
      float w = std::clamp(r.weight, 0.0f, 1.0f);
      a.translation += (b.translation - a.translation) * w;
      a.scale += (b.scale - a.scale) * w;
      a.angle = 2 * std::atan2((1 - w) * std::sin(a.angle / 2) + w * std::sin(b.angle / 2),
                               (1 - w) * std::cos(a.angle / 2) + w * std::cos(b.angle / 2));
    }
    world[i] = simd_mul(i % 5 ? world[i - 1] : root, Local(a));
    simd_float4x4 actual;
    Check([model rigTransformAtIndex:2 + count - 1 - i transform:&actual], "joint node missing");
    MatrixEqual(actual, world[i]);
  }
  for (NSUInteger i = 0; i < [model rigCount]; ++i)
  {
    simd_float4x4 actual;
    Check([model rigTransformAtIndex:i transform:&actual], "rig node missing");
    if (i < 2)
      MatrixEqual(actual, root);
    if (i == count + 2)
      MatrixEqual(actual, Translation(simd_make_float3(.4, .1, .1)));
    if (i == count + 3)
    {
      auto expected         = Translation(simd_make_float3(-.1, .2, .1));
      expected.columns[1].y = 2;
      MatrixEqual(actual, expected);
    }
    Append(capture, &actual, sizeof(actual));
  }
  for (NSUInteger page = 0; page < 3; ++page)
  {
    auto buffer = [model.parts[0] jointMatrixBufferForPage:page];
    Check(buffer.length >= count * sizeof(simd_float4x4), "joint buffer too small");
    const auto *matrices = static_cast<const simd_float4x4 *>(buffer.contents);
    for (int i = 0; i < count; ++i)
    {
      // Bind world transform is translation only; accumulate along the strand.
      auto bind = simd_make_float3(.1, -.1, 0);
      for (int j = i - i % 5; j <= i; ++j)
        bind += Pose(j, count, 0, 0).translation;
      MatrixEqual(matrices[i], simd_mul(world[i], Translation(-bind)));
    }
    Append(capture, buffer.contents, count * sizeof(simd_float4x4));
  }
}

static void RenderPoses(MetalModel *model, id<MTLDevice> device, id<MTLLibrary> library,
                        std::vector<char> &capture, const std::filesystem::path &previewDirectory,
                        int jointCount)
{
  auto view             = [[MTKView alloc] initWithFrame:NSMakeRect(0, 0, 256, 256) device:device];
  view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
  auto draw                    = [[Draw3D alloc] initWithMetalKitView:view shaderlib:library];
  auto desc        = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:view.colorPixelFormat
                                                                        width:256
                                                                       height:256
                                                                    mipmapped:NO];
  desc.usage       = MTLTextureUsageRenderTarget;
  desc.storageMode = MTLStorageModeShared;
  auto color       = [device newTextureWithDescriptor:desc];
  desc.pixelFormat = view.depthStencilPixelFormat;
  desc.storageMode = MTLStorageModePrivate;
  auto depth       = [device newTextureWithDescriptor:desc];
  auto pass        = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.colorAttachments[0].texture     = color;
  pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
  pass.colorAttachments[0].storeAction = MTLStoreActionStore;
  pass.depthAttachment.texture         = depth;
  pass.depthAttachment.loadAction      = MTLLoadActionClear;
  pass.stencilAttachment.texture       = depth;
  pass.stencilAttachment.loadAction    = MTLLoadActionClear;
  auto                queue            = [device newCommandQueue];
  alloy3d::CameraData camera;
  camera.buildPerspective(.785398163f, 1, .1, 100);
  std::vector<uint32_t> previous;
  int                   poseIndex = 0;
  for (const auto &request : {Request{0, 0, .75, 0, 0, false},
                              Request{1, 1, 1.7, 0, 0, false},
                              Request{0, 1, .3, 1.9, .4, true}})
  {
    Apply(model, request);
    [draw drawModel:model
           position:simd_make_float3(0, -.25, -6)
           rotation:simd_make_float3(0, 0, 0)
              scale:simd_make_float3(1, 1, 1)
              color:simd_make_float4(1, 1, 1, 1)];
    auto command = [queue commandBuffer];
    auto encoder = [command renderCommandEncoderWithDescriptor:pass];
    [draw render:encoder camera:&camera];
    [encoder endEncoding];
    [command commit];
    [command waitUntilCompleted];
    Check(command.status == MTLCommandBufferStatusCompleted, "GPU rendering failed");
    std::vector<uint32_t> pixels(256 * 256);
    [color getBytes:pixels.data()
        bytesPerRow:256 * 4
         fromRegion:MTLRegionMake2D(0, 0, 256, 256)
        mipmapLevel:0];
    Check(std::count_if(pixels.begin(), pixels.end(), [](uint32_t p) { return p & 0xffffff; }) >
              100,
          "skinned mesh not visible");
    Check(previous.empty() || pixels != previous, "animation did not change rendered pixels");
    Append(capture, pixels.data(), pixels.size() * sizeof(uint32_t));
    if (!previewDirectory.empty())
    {
      std::filesystem::create_directories(previewDirectory);
      auto bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
                                                            pixelsWide:256
                                                            pixelsHigh:256
                                                         bitsPerSample:8
                                                       samplesPerPixel:4
                                                              hasAlpha:YES
                                                              isPlanar:NO
                                                        colorSpaceName:NSDeviceRGBColorSpace
                                                           bytesPerRow:256 * 4
                                                          bitsPerPixel:32];
      for (size_t i = 0; i < pixels.size(); ++i)
      {
        bitmap.bitmapData[i * 4]     = (pixels[i] >> 16) & 255;
        bitmap.bitmapData[i * 4 + 1] = (pixels[i] >> 8) & 255;
        bitmap.bitmapData[i * 4 + 2] = pixels[i] & 255;
        bitmap.bitmapData[i * 4 + 3] = 255;
      }
      auto file = previewDirectory / ("rig_" + std::to_string(jointCount) + "_pose_" +
                                      std::to_string(poseIndex) + ".png");
      auto png  = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
      Check([png writeToFile:[NSString stringWithUTF8String:file.c_str()] atomically:YES],
            "cannot write preview");
      [bitmap release];
    }
    ++poseIndex;
    previous = std::move(pixels);
  }
  [queue release];
  [color release];
  [depth release];
  [draw release];
  [view release];
}

static void Benchmark(MetalModel *model, int count, bool blend, bool requireNoAlloc)
{
  [model setAnimationIndex:0];
  auto update = [&](int frame)
  {
    if (blend)
      [model setAnimationBlendFrom:0 timeA:frame * .013f to:1 timeB:frame * .017f weight:.4f];
    else
      [model setAnimationTime:frame * .013f];
  };
  for (int i = 0; i < 20; ++i)
    update(i);
  std::vector<double> times;
  size_t              counted = 0;
  constexpr int       samples = 15, iterations = 200;
  for (int sample = 0; sample < samples; ++sample)
  {
    auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < iterations; ++i)
      update(sample * iterations + i);
    times.push_back(
        std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - start)
            .count() /
        iterations);
  }
  allocations      = 0;
  countAllocations = true;
  for (int i = 0; i < iterations; ++i)
    update(i);
  countAllocations = false;
  counted          = allocations;
  std::sort(times.begin(), times.end());
  std::printf("joints=%d mode=%s median_us=%.3f cpp_allocations_per_update=%.1f\n",
              count,
              blend ? "blend" : "single",
              times[samples / 2],
              double(counted) / iterations);
  Check(!requireNoAlloc || counted == 0, "warmed animation still allocates C++ memory");
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    if (argc < 3)
      return 2;
    const bool requireNoAlloc = argc > 3 && std::strcmp(argv[3], "--require-no-alloc") == 0;
    const bool record         = argc == 5 && std::strcmp(argv[3], "--record") == 0;
    const bool compare        = argc == 5 && std::strcmp(argv[3], "--compare") == 0;
    auto       device         = MTLCreateSystemDefaultDevice();
    if (device == nil)
      return 77;
    try
    {
      NSError *error = nil;
      auto     library =
          [device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]
                              error:&error];
      Check(library != nil, "shader library missing");
      for (int count : {25, 100, 200})
      {
        auto path  = std::filesystem::path(argv[1]) / ("rig_" + std::to_string(count) + ".glb");
        auto model = [[MetalModel alloc] initWithFile:[NSString stringWithUTF8String:path.c_str()]
                                               device:device];
        Check(model.loaded && model.parts.count == 1 && [model rigCount] == count + 4 &&
                  [model animationCount] == 2,
              "fixture structure is incorrect");
        Check([[model animationNameAtIndex:0] isEqualToString:@"Wave"] &&
                  [model animationDurationAtIndex:1] == 3,
              "animation metadata changed");
        std::vector<char> capture;
        for (int clip : {0, 1, 0})
          for (float time : {-.25f, 0.f, .25f, 1.f, 1.5f, 1.99f, 2.f, 3.f, 4.25f, .1f})
            VerifyPose(model, count, {NSUInteger(clip), 0, time, 0, 0, false}, capture);
        for (float weight : {-1.f, 0.f, .25f, .5f, 1.f, 2.f})
        {
          VerifyPose(model, count, {0, 1, .6f, 1.8f, weight, true}, capture);
          VerifyPose(model, count, {1, 0, 2.2f, 1.3f, weight, true}, capture);
        }
        VerifyPose(model, count, {0, 0, .3f, 1.5f, .4f, true}, capture);
        VerifyPose(model, count, {0, 1, .6f, 1.8f, .5f, true}, capture);
        VerifyPose(model, count, {0, 0, 0, 0, 0, false}, capture);
        simd_float4x4 before, after;
        [model rigTransformAtIndex:2 transform:&before];
        [model setAnimationBlendFrom:99 timeA:1 to:0 timeB:1 weight:.5];
        [model setAnimationIndex:99];
        [model rigTransformAtIndex:2 transform:&after];
        MatrixEqual(before, after);
        Check(![model rigTransformAtIndex:count + 4 transform:&after], "invalid rig accepted");
        RenderPoses(model,
                    device,
                    library,
                    capture,
                    record ? std::filesystem::path(argv[4]) : std::filesystem::path{},
                    count);
        if (record || compare)
        {
          auto file = std::filesystem::path(argv[4]) / ("rig_" + std::to_string(count) + ".bin");
          if (record)
          {
            std::filesystem::create_directories(file.parent_path());
            std::ofstream stream(file, std::ios::binary);
            stream.write(capture.data(), capture.size());
            Check(bool(stream), "cannot write baseline capture");
          }
          else
          {
            std::ifstream stream(file, std::ios::binary);
            Check(bool(stream), "baseline capture missing");
            std::vector<char> expected((std::istreambuf_iterator<char>(stream)), {});
            Check(capture == expected, "CPU/joint matrices or GPU pixels differ from baseline");
          }
        }
        Benchmark(model, count, false, requireNoAlloc);
        Benchmark(model, count, true, requireNoAlloc);
        [model release];
      }
      [library release];
      [device release];
      std::puts("PASS: analytic poses, clip changes, blend/loop/seek, static nodes, skin matrices "
                "and animated GPU pixels");
    }
    catch (const std::exception &error)
    {
      countAllocations = false;
      std::fprintf(stderr, "FAIL: %s\n", error.what());
      return 1;
    }
  }
}
