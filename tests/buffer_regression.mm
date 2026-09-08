#import <alloy3d/metal/draw2d.h>
#import <alloy3d/metal/font_render.h>
#import <alloy3d/metal/model.h>
#include <alloy3d/metal/vertex_buffer.h>
#include <array>
#include <cmath>
#include <cstdio>
#include <limits>
#include <stdexcept>

// Exercise allocation failure without asking the system for an enormous buffer.
@interface FailingBufferDevice : NSObject
- (NSUInteger)maxBufferLength;
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
@end
@implementation FailingBufferDevice
- (NSUInteger)maxBufferLength
{
  return 1024 * 1024 * 1024;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options
{
  return nil;
}
@end

static void Check(bool condition, const char *message)
{
  if (!condition)
    throw std::runtime_error(message);
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    if (argc != 3)
      return 2;
    auto device = MTLCreateSystemDefaultDevice();
    if (device == nil)
      return 77;
    try
    {
      alloy3d::metal::VertexBuffer<uint32_t> buffer;
      Check(buffer.buffer() == nil, "unused buffer must not allocate");
      for (NSUInteger i = 0; i < 350000; ++i)
        *buffer.append(device, i, 1) = uint32_t(i ^ 0xabc123);
      auto data = static_cast<uint32_t *>(buffer.buffer().contents);
      for (NSUInteger i = 0; i < 350000; ++i)
        Check(data[i] == (i ^ 0xabc123), "growth lost vertices");
      auto previous = buffer.buffer();
      buffer.append(device, 0, 20);
      Check(buffer.buffer() == previous, "warm buffer must be reused");
      bool rejected = false;
      try
      {
        buffer.append(device, 1, std::numeric_limits<NSUInteger>::max());
      }
      catch (const std::length_error &)
      {
        rejected = true;
      }
      Check(rejected && buffer.buffer() == previous, "overflow must preserve the old buffer");
      Check(data[349999] == (349999 ^ 0xabc123), "overflow modified data");
      auto failingDevice = [[FailingBufferDevice alloc] init];
      rejected           = false;
      try
      {
        buffer.append((id<MTLDevice>)failingDevice, 350000, buffer.capacity());
      }
      catch (const std::bad_alloc &)
      {
        rejected = true;
      }
      [failingDevice release];
      Check(rejected && buffer.buffer() == previous && data[349999] == (349999 ^ 0xabc123),
            "allocation failure must preserve vertices");

      auto      font = [[FontRender alloc] init];
      NSString *key  = [[font CacheKey:@"label"] copy];
      Check([key isEqualToString:[font CacheKey:@"label"]], "font key unstable");
      [font SetSize:36];
      Check(![key isEqualToString:[font CacheKey:@"label"]], "font size did not invalidate key");
      [key release];
      key = [[font CacheKey:@"label"] copy];
      [font SetColor:0 green:1 blue:0 alpha:1];
      Check(![key isEqualToString:[font CacheKey:@"label"]], "font color did not invalidate key");
      [key release];
      [font release];

      auto model = [[MetalModel alloc] initWithFile:[NSString stringWithUTF8String:argv[2]]
                                             device:device];
      Check(model.loaded && model.parts.count == 1, "bouncer fixture missing");
      for (const float time : {0.0f, 0.5f, 0.25f, 0.0f})
      {
        [model setAnimationTime:time];
        for (NSUInteger page = 0; page < 3; ++page)
        {
          const auto joints = [model.parts[0] jointMatrixBufferForPage:page];
          Check(joints != nil, "joint buffer missing");
          const auto matrix = static_cast<const simd_float4x4 *>(joints.contents)[0];
          Check(std::fabs(matrix.columns[3].y - time * 1.1f) < 0.00001f,
                "animation did not refresh every GPU page");
        }
      }
      [model release];

      NSError *error = nil;
      auto     library =
          [device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]
                              error:&error];
      Check(library != nil, "shader library missing");
      auto view = [[MTKView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64) device:device];
      view.colorPixelFormat        = MTLPixelFormatBGRA8Unorm;
      view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
      auto draw                    = [[Draw2D alloc] initWithMetalKitView:view shaderlib:library];
      auto queue                   = [device newCommandQueue];
      auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:view.colorPixelFormat
                                                                     width:64
                                                                    height:64
                                                                 mipmapped:NO];
      desc.storageMode = MTLStorageModeShared;
      desc.usage       = MTLTextureUsageRenderTarget;
      id<MTLTexture>       colors[3];
      id<MTLCommandBuffer> commands[3];
      auto                 depthDesc =
          [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:view.depthStencilPixelFormat
                                                             width:64
                                                            height:64
                                                         mipmapped:NO];
      depthDesc.storageMode = MTLStorageModePrivate;
      depthDesc.usage       = MTLTextureUsageRenderTarget;
      auto          depth   = [device newTextureWithDescriptor:depthDesc];
      const CGFloat scale   = [[NSScreen mainScreen] backingScaleFactor];
      for (int cycle = 0; cycle < 2; ++cycle)
      {
        // Encode all three frames before submitting any. A shared uniform buffer
        // would make all three images use the last frame's screen size.
        for (int frame = 0; frame < 3; ++frame)
        {
          colors[frame]                        = [device newTextureWithDescriptor:desc];
          auto pass                            = [MTLRenderPassDescriptor renderPassDescriptor];
          pass.colorAttachments[0].texture     = colors[frame];
          pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
          pass.colorAttachments[0].storeAction = MTLStoreActionStore;
          pass.depthAttachment.texture         = depth;
          pass.stencilAttachment.texture       = depth;
          draw.screenSize                      = CGSizeMake(64 << frame, 64);
          // Discard must neither retain the red rectangle nor advance a page.
          [draw fillRect:simd_make_float2(0, 0)
                      to:simd_make_float2(64 / scale, 64 / scale)
                   color:simd_make_float4(1, 0, 0, 1)];
          [draw discardFrame];
          [draw fillRect:simd_make_float2(0, 0)
                      to:simd_make_float2(16 / scale, 64 / scale)
                   color:simd_make_float4(1, 1, 1, 1)];
          commands[frame] = [[queue commandBuffer] retain];
          auto encoder    = [commands[frame] renderCommandEncoderWithDescriptor:pass];
          [draw render:encoder];
          [encoder endEncoding];
        }
        for (auto command : commands)
          [command commit];
        for (int frame = 0; frame < 3; ++frame)
        {
          [commands[frame] waitUntilCompleted];
          Check(commands[frame].status == MTLCommandBufferStatusCompleted, "GPU command failed");
          std::array<uint32_t, 64 * 64> pixels{};
          [colors[frame] getBytes:pixels.data()
                      bytesPerRow:64 * 4
                       fromRegion:MTLRegionMake2D(0, 0, 64, 64)
                      mipmapLevel:0];
          for (int x = 0; x < 64; ++x)
          {
            const auto rgb = pixels[32 * 64 + x] & 0xffffff;
            Check(rgb == (x < (16 >> frame) ? 0xffffff : 0),
                  "frame data overwritten or discard failed");
          }
          [commands[frame] release];
          [colors[frame] release];
        }
      }
      [depth release];
      [queue release];
      [draw release];
      [view release];
      [library release];
      std::puts("PASS: growth, reuse, overflow, font invalidation, animation pages, 3 GPU pages, "
                "discard, page wrap");
    }
    catch (const std::exception &error)
    {
      std::fprintf(stderr, "FAIL: %s\n", error.what());
      return 1;
    }
    [device release];
  }
}
