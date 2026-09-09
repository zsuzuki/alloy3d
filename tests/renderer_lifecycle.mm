#import "renderer.h"
#include <cstdio>
#include <cstdlib>

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
  void Update(alloy3d::ApplicationContext &ctx) override
  {
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
      auto renderer                = [[Renderer alloc] initWithMetalKitView:view];
      [renderer setApplicationLoop:&loop];
      [renderer startApplicationLoop];
      for (int frame = 0; frame < frames; ++frame)
        [renderer drawInMTKView:view];
      // Do not explicitly wait: destruction must drain submissions and balance
      // the semaphore before releasing it, even if no frames were submitted.
      [renderer release];
      [view release];
    }
    [device release];
    std::printf("renderer shutdown: %d frames, 3 create/destroy cycles passed\n", frames);
    return 0;
  }
}
