#import "renderer.h"
#include <cstdio>
#include <cstdlib>
#include <array>
#include <stdexcept>
#include <thread>

// Exercise the actual host lifecycle, including the no-drawable submission path,
// without depending on a visible window or display refresh timing.
@interface NoDrawableView : MTKView
@end
@implementation NoDrawableView
- (MTLRenderPassDescriptor *)currentRenderPassDescriptor
{
  return nil;
}
- (id<CAMetalDrawable>)currentDrawable
{
  return nil;
}
@end

class LifecycleLoop final : public alloy3d::ApplicationLoop
{
public:
  alloy3d::ApplicationContext::ModelLoader loader;
  alloy3d::ApplicationContext::ModelPtr    loaded;
  void Start(alloy3d::ApplicationContext &ctx) override { loader = ctx.CreateModelLoader(); }
  void Update(alloy3d::ApplicationContext &ctx) override
  {
    if (loaded)
    {
      std::array single{loaded};
      std::array duplicate{loaded, loaded};
      const auto a = ctx.GetModelResourceStats(single), b = ctx.GetModelResourceStats(duplicate);
      if (!a.bufferBytes || !a.textureBytes || a.bufferBytes != b.bufferBytes ||
          a.textureBytes != b.textureBytes || a.resourceCount != b.resourceCount)
        throw std::runtime_error("model resource accounting failed to deduplicate");
      auto       clone = ctx.CreateModelInstance(loaded);
      std::array shared{loaded, clone};
      const auto c = ctx.GetModelResourceStats(shared);
      if (!clone || c.textureBytes != a.textureBytes || c.bufferBytes >= a.bufferBytes * 2)
        throw std::runtime_error("instance resources were counted twice");
    }
    ctx.DrawBox3D(
        simd_make_float3(0, 0, 0), simd_make_float3(1, 1, 1), simd_make_float4(1, 1, 1, 1));
  }
};

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    auto device = MTLCreateSystemDefaultDevice();
    if (!device)
      return 77;
    const int     frames = argc > 1 ? std::atoi(argv[1]) : 0;
    LifecycleLoop loop;
    for (int iteration = 0; iteration < 3; ++iteration)
    {
      auto view   = [[NoDrawableView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64) device:device];
      view.paused = YES;
      view.colorPixelFormat        = MTLPixelFormatBGRA8Unorm;
      view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
      view.sampleCount             = iteration == 1 ? 4 : 1;
      auto renderer                = [[Renderer alloc]
          initWithMetalKitView:view
                 renderOptions:(alloy3d::RenderOptions{
                                   uint32_t(view.sampleCount), iteration > 0, iteration > 0})];
      [renderer setApplicationLoop:&loop];
      [renderer startApplicationLoop];
      if (argc > 2)
      {
        // Start's stack-allocated context no longer exists here.
        std::thread load([&] { loop.loaded = loop.loader(argv[2]); });
        load.join();
        if (!loop.loaded || !loop.loaded->IsLoaded())
          return 1;
      }
      for (int frame = 0; frame < frames; ++frame)
        [renderer drawInMTKView:view];
      // Do not explicitly wait: destruction must drain submissions and balance
      // the semaphore before releasing it, even if no frames were submitted.
      [renderer release];
      if (argc > 2)
      {
        std::thread load([&] { loop.loaded = loop.loader(argv[2]); });
        load.join();
        if (!loop.loaded || !loop.loaded->IsLoaded())
          return 1;
        loop.loaded.reset();
      }
      [view release];
    }
    [device release];
    std::printf("renderer shutdown: %d frames, 3 create/destroy cycles passed\n", frames);
    return 0;
  }
}
