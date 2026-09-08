#include <algorithm>
#include <alloy3d/camera.h>
#import <alloy3d/metal/draw2d.h>
#import <alloy3d/metal/draw3d.h>
#import <alloy3d/metal/model.h>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <vector>

using Clock = std::chrono::steady_clock;
static double Milliseconds(Clock::time_point start)
{
  return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

// Offscreen benchmark: CPU submission and encoding are separate from GPU time.
// Each frame waits for completion; this is deliberately not an FPS benchmark.
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    if (argc < 3)
      return 2;
    const bool stress   = argc > 3 && std::strcmp(argv[3], "--stress") == 0;
    const bool snapshot = argc > 3 && std::strcmp(argv[3], "--snapshot") == 0;
    auto       device   = MTLCreateSystemDefaultDevice();
    if (device == nil)
    {
      std::fprintf(stderr, "Metal device unavailable\n");
      return 77;
    }
    NSError *error = nil;
    auto     library =
        [device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]
                            error:&error];
    if (library == nil)
    {
      NSLog(@"%@", error);
      return 1;
    }
    auto view = [[MTKView alloc] initWithFrame:NSMakeRect(0, 0, 256, 256) device:device];
    view.colorPixelFormat        = MTLPixelFormatBGRA8Unorm;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.sampleCount             = 1;
    auto draw2d                  = [[Draw2D alloc] initWithMetalKitView:view shaderlib:library];
    auto draw3d                  = [[Draw3D alloc] initWithMetalKitView:view shaderlib:library];
    draw2d.screenSize            = CGSizeMake(256, 256);
    auto model = [[MetalModel alloc] initWithFile:[NSString stringWithUTF8String:argv[2]]
                                           device:device];
    if (!model.loaded)
    {
      std::fprintf(stderr, "Model load failed\n");
      return 1;
    }
    auto textureDesc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:view.colorPixelFormat
                                                           width:256
                                                          height:256
                                                       mipmapped:NO];
    textureDesc.usage                    = MTLTextureUsageRenderTarget;
    textureDesc.storageMode              = snapshot ? MTLStorageModeShared : MTLStorageModePrivate;
    auto color                           = [device newTextureWithDescriptor:textureDesc];
    textureDesc.pixelFormat              = view.depthStencilPixelFormat;
    textureDesc.storageMode              = MTLStorageModePrivate;
    auto depth                           = [device newTextureWithDescriptor:textureDesc];
    auto pass                            = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture     = color;
    pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.depthAttachment.texture         = depth;
    pass.depthAttachment.loadAction      = MTLLoadActionClear;
    pass.depthAttachment.clearDepth      = 1.0;
    pass.stencilAttachment.texture       = depth;
    pass.stencilAttachment.loadAction    = MTLLoadActionClear;
    auto                queue            = [device newCommandQueue];
    alloy3d::CameraData camera;
    camera.buildPerspective(45, 1, 0.1, 1000);
    const simd_float4 white = {1, 1, 1, 1};
    std::printf("device=%s mode=%s\n",
                [device.name UTF8String],
                snapshot ? "snapshot" : (stress ? "stress" : "benchmark"));
    for (int scenario = snapshot ? 4 : 0; scenario < (snapshot ? 5 : 4); ++scenario)
    {
      std::vector<double> submit, encode, gpu;
      const int           frames = snapshot ? 1 : (stress ? 6 : 80);
      for (int frame = 0; frame < frames; ++frame)
      {
        @autoreleasepool
        {
          auto start = Clock::now();
          if (scenario == 0)
          {
            for (int i = 0; i < (stress ? 65000 : 10000); ++i)
            {
              [draw2d drawLine:simd_make_float2(0, 0) to:simd_make_float2(1, 1) color:white];
              [draw3d drawLine:simd_make_float3(0, 0, -5)
                            to:simd_make_float3(1, 1, -5)
                         color:white];
            }
            for (int i = 0; i < (stress ? 21000 : 1000); ++i)
              [draw2d fillRect:simd_make_float2(0, 0) to:simd_make_float2(1, 1) color:white];
          }
          else if (scenario == 1)
          {
            for (int i = 0; i < (stress ? 180 : 100); ++i)
              [draw3d drawSphere:simd_make_float3(0, 0, -5)
                          radius:0.01f
                           color:white
                          slices:24
                          stacks:12];
          }
          else if (scenario == 2)
          {
            [model setAnimationTime:frame / 60.0f];
            for (int i = 0; i < 1000; ++i)
              [draw3d drawModel:model
                       position:simd_make_float3(0, 0, -5)
                       rotation:simd_make_float3(0, 0, 0)
                          scale:simd_make_float3(0.01, 0.01, 0.01)
                          color:white];
          }
          else if (scenario == 3)
          {
            for (int i = 0; i < (stress ? 5100 : 100); ++i)
            {
              [draw2d print:@"Alloy3D" x:-200 y:-200];
              [draw3d drawText:@"Alloy3D"
                      position:simd_make_float3(0, 0, -5)
                    lineHeight:0.001
                         align:DrawText3DAlignLeftBottom
                         color:white];
            }
          }
          else
          {
            [draw3d drawSphere:simd_make_float3(-0.8, 0, -5)
                        radius:0.8
                         color:simd_make_float4(0.2, 0.8, 0.5, 1)
                        slices:24
                        stacks:12];
            [model setAnimationTime:0.5f];
            [draw3d drawModel:model
                     position:simd_make_float3(0.6, -0.8, -5)
                     rotation:simd_make_float3(0, 0.4, 0)
                        scale:simd_make_float3(1, 1, 1)
                        color:white];
            [draw2d fillRoundRect:simd_make_float2(10, 10)
                               to:simd_make_float2(90, 30)
                           radius:5
                            color:simd_make_float4(0.2, 0.3, 0.7, 1)];
            [draw2d print:@"Alloy3D" x:10 y:80];
            [draw3d drawText:@"3D"
                    position:simd_make_float3(-0.5, -1.1, -4)
                  lineHeight:0.3
                       align:DrawText3DAlignLeftBottom
                       color:white];
          }
          const auto submitMs = Milliseconds(start);
          start               = Clock::now();
          auto command        = [queue commandBuffer];
          auto encoder        = [command renderCommandEncoderWithDescriptor:pass];
          [draw3d render:encoder camera:&camera];
          [draw2d render:encoder];
          [encoder endEncoding];
          const auto encodeMs = Milliseconds(start);
          [command commit];
          [command waitUntilCompleted];
          if (command.status == MTLCommandBufferStatusError)
          {
            NSLog(@"%@", command.error);
            return 1;
          }
          if (snapshot)
          {
            std::vector<uint32_t> pixels(256 * 256);
            [color getBytes:pixels.data()
                bytesPerRow:256 * 4
                 fromRegion:MTLRegionMake2D(0, 0, 256, 256)
                mipmapLevel:0];
            uint64_t hash = 14695981039346656037ULL;
            size_t   lit  = 0;
            for (auto pixel : pixels)
            {
              if (pixel & 0xffffff)
                ++lit;
              hash = (hash ^ pixel) * 1099511628211ULL;
            }
            std::printf("snapshot_hash=%016llx lit_pixels=%zu\n", (unsigned long long)hash, lit);
            if (lit < 1000)
              return 1;
          }
          if (stress || snapshot || frame >= 10)
          {
            submit.push_back(submitMs);
            encode.push_back(encodeMs);
            gpu.push_back((command.GPUEndTime - command.GPUStartTime) * 1000.0);
          }
        }
      }
      auto median = [](std::vector<double> values)
      {
        std::sort(values.begin(), values.end());
        return values[values.size() / 2];
      };
      const char *names[] = {"lines+fill", "spheres", "1000-models", "text", "snapshot"};
      std::printf("%s submit_ms=%.4f encode_ms=%.4f gpu_ms=%.4f\n",
                  names[scenario],
                  median(submit),
                  median(encode),
                  median(gpu));
    }
    [model release];
    [draw2d release];
    [draw3d release];
    [view release];
    [color release];
    [depth release];
    [queue release];
    [library release];
    [device release];
  }
}
