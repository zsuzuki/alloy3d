#include <alloy3d/camera.h>
#import <alloy3d/metal/draw2d.h>
#import <alloy3d/metal/draw3d.h>
#import <alloy3d/metal/memory_cache.h>
#include <array>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include <vector>

static int destroyedValues = 0;
@interface CacheTestValue : NSObject
@end
@implementation CacheTestValue
- (void)dealloc
{
  ++destroyedValues;
  [super dealloc];
}
@end

static void Check(bool value, const char *message)
{
  if (!value)
    throw std::runtime_error(message);
}

static void TestCache()
{
  auto cache = [[MemoryCache alloc] initWithLimit:12];
  [cache setObject:@"A" forKey:@"a" cost:6];
  [cache setObject:@"B" forKey:@"b" cost:6];
  Check([[cache objectForKey:@"a"] isEqual:@"A"], "cache lookup failed");
  [cache setObject:@"C" forKey:@"c" cost:6];
  Check([cache objectForKey:@"b"] == nil && [cache bytes] == 12, "LRU eviction failed");
  [cache setObject:@"new A" forKey:@"a" cost:2];
  Check([cache bytes] == 8 && [cache count] == 2, "replacement cost incorrect");
  [cache setLimit:2];
  Check([cache bytes] == 2 && [[cache objectForKey:@"a"] isEqual:@"new A"],
        "budget reduction failed");
  [cache setObject:@"huge" forKey:@"huge" cost:std::numeric_limits<NSUInteger>::max()];
  Check([cache bytes] == 2 && [cache objectForKey:@"huge"] == nil, "oversized entry retained");
  id retained = [[cache objectForKey:@"a"] retain];
  [cache setLimit:0];
  Check([cache bytes] == 0 && [cache count] == 0 && [retained isEqual:@"new A"],
        "eviction invalidated retained value");
  [retained release];
  [cache setObject:@"zero" forKey:@"zero" cost:0];
  Check([cache count] == 0, "zero budget did not disable cache");
  [cache setLimit:1024];
  for (int i = 0; i < 600; ++i)
    [cache setObject:@"small" forKey:[NSString stringWithFormat:@"%d", i] cost:0];
  Check([cache count] == 512, "entry-count backstop failed");
  [cache removeAllObjects];
  Check([cache bytes] == 0 && [cache count] == 0, "cache clear failed");
  auto value = [[CacheTestValue alloc] init];
  [cache setObject:value forKey:@"owned" cost:1];
  [value release];
  Check(destroyedValues == 0, "cache did not retain its value");
  [cache setObject:[cache objectForKey:@"owned"] forKey:@"owned" cost:2];
  Check(destroyedValues == 0 && [cache bytes] == 2, "self replacement released value");
  id queued = [[cache objectForKey:@"owned"] retain];
  [cache removeAllObjects];
  Check(destroyedValues == 0, "eviction released an externally owned value");
  [queued release];
  Check(destroyedValues == 1, "evicted value leaked");
  [cache release];
}

static void CheckVisibleText(const std::vector<uint32_t> &pixels)
{
  // The rectangle occupies y=0..10; these regions must contain actual glyphs.
  unsigned text2d = 0, text3d = 0;
  for (int y = 15; y < 128; ++y)
    for (int x = 0; x < 128; ++x)
      if ((pixels[y * 128 + x] & 0x00ffffff) != 0)
      {
        if (y < 60)
          ++text2d;
        else
          ++text3d;
      }
  Check(text2d > 20 && text3d > 20, "reference frame has missing text");
}

static NSUInteger VertexBytes(Draw2D *d2, Draw3D *d3)
{
  return [d2 memoryStats].vertexBufferBytes + [d3 memoryStats].vertexBufferBytes;
}

static void CacheBound(Draw2D *d2, Draw3D *d3, NSUInteger limit)
{
  for (const auto stats : {[d2 memoryStats], [d3 memoryStats]})
    Check(stats.textBitmapCacheBytes <= limit && stats.textTextureCacheBytes <= limit,
          "text cache exceeded byte budget");
}

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    if (argc != 2)
      return 2;
    try
    {
      TestCache();
      auto device = MTLCreateSystemDefaultDevice();
      if (device == nil)
        return 77;
      NSError *error = nil;
      auto     library =
          [device newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]]
                              error:&error];
      Check(library != nil, "shader library missing");
      auto view = [[MTKView alloc] initWithFrame:NSMakeRect(0, 0, 128, 128) device:device];
      view.colorPixelFormat        = MTLPixelFormatBGRA8Unorm;
      view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
      auto d2                      = [[Draw2D alloc] initWithMetalKitView:view shaderlib:library];
      auto d3                      = [[Draw3D alloc] initWithMetalKitView:view shaderlib:library];
      d2.screenSize                = CGSizeMake(128, 128);
      const NSUInteger budget      = 128 * 1024;
      [d2 setTextBitmapLimit:budget textureLimit:budget];
      [d3 setTextBitmapLimit:budget textureLimit:budget];
      auto queue = [device newCommandQueue];
      auto desc  = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:view.colorPixelFormat
                                                                      width:128
                                                                     height:128
                                                                  mipmapped:NO];
      desc.usage = MTLTextureUsageRenderTarget;
      desc.storageMode = MTLStorageModeShared;
      id<MTLTexture> colors[3];
      for (auto &color : colors)
        color = [device newTextureWithDescriptor:desc];
      desc.pixelFormat                                 = view.depthStencilPixelFormat;
      desc.storageMode                                 = MTLStorageModePrivate;
      auto                                 depth       = [device newTextureWithDescriptor:desc];
      id<MTLCommandBuffer>                 commands[3] = {nil, nil, nil};
      alloy3d::CameraData                  camera;
      std::array<std::vector<uint32_t>, 3> expected;
      NSUInteger                           peak = 0, reduced = 0;
      const auto                           white = simd_make_float4(1, 1, 1, 1);
      // Heavy -> release -> light -> regrow. At most three frames in flight.
      for (int phase = 0; phase < 3; ++phase)
      {
        for (int page = 0; page < 3; ++page)
        {
          @autoreleasepool
          {
            if (commands[page])
            {
              [commands[page] waitUntilCompleted];
              Check(commands[page].status == MTLCommandBufferStatusCompleted, "GPU command failed");
              std::vector<uint32_t> pixels(128 * 128);
              [colors[page] getBytes:pixels.data()
                         bytesPerRow:128 * 4
                          fromRegion:MTLRegionMake2D(0, 0, 128, 128)
                         mipmapLevel:0];
              if (phase == 1)
              {
                CheckVisibleText(pixels);
                expected[page] = pixels;
              }
              else
                Check(pixels == expected[page], "release changed rendered pixels");
              [commands[page] release];
            }
            [d2 beginFrame];
            [d3 beginFrame];
            if (phase != 1)
            {
              for (int i = 0; i < 24000; ++i)
              {
                [d2 fillRect:simd_make_float2(-100, -100)
                          to:simd_make_float2(-99, -99)
                       color:white];
                [d3 drawLine:simd_make_float3(5, 5, .5) to:simd_make_float3(6, 6, .5) color:white];
              }
              for (int i = 0; i < 180; ++i)
              {
                auto text = [NSString stringWithFormat:@"Cache entry %03d - a changing label", i];
                [d2 print:text x:-1000 y:-1000];
                [d3 drawText:text
                      position:simd_make_float3(5, 5, .5)
                    lineHeight:.1
                         align:DrawText3DAlignLeftBottom
                         color:white];
                CacheBound(d2, d3, phase == 0 ? budget : 0);
              }
            }
            [d2 fillRect:simd_make_float2(0, 0) to:simd_make_float2(10, 10) color:white];
            [d2 print:@"Memory" x:3 y:20];
            [d3 drawText:@"3D"
                  position:simd_make_float3(-.2, -.3, .5)
                lineHeight:.4
                     align:DrawText3DAlignLeftBottom
                     color:white];
            auto pass                            = [MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture     = colors[page];
            pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
            pass.colorAttachments[0].storeAction = MTLStoreActionStore;
            pass.depthAttachment.texture         = depth;
            pass.depthAttachment.loadAction      = MTLLoadActionClear;
            pass.stencilAttachment.texture       = depth;
            pass.stencilAttachment.loadAction    = MTLLoadActionClear;
            commands[page]                       = [[queue commandBuffer] retain];
            auto encoder = [commands[page] renderCommandEncoderWithDescriptor:pass];
            [d3 render:encoder camera:&camera];
            [d2 render:encoder];
            [encoder endEncoding];
          }
        }
        if (phase == 0)
        {
          peak = VertexBytes(d2, d3);
          Check(peak > 1024 * 1024, "heavy scene did not grow buffers");
          Check([d2 memoryStats].textBitmapCacheBytes > 0 &&
                    [d3 memoryStats].textTextureCacheBytes > 0,
                "warm cache usage not reported");
          // Evict while encoded commands still reference textures, before commit.
          [d2 setTextBitmapLimit:0 textureLimit:0];
          [d3 setTextBitmapLimit:0 textureLimit:0];
          [d2 releaseUnusedMemory];
          [d3 releaseUnusedMemory];
          CacheBound(d2, d3, 0);
          Check([d2 memoryStats].releasePending && [d3 memoryStats].releasePending,
                "release should be deferred");
          Check(VertexBytes(d2, d3) == peak, "in-flight pages were released early");
        }
        if (phase == 1)
        {
          reduced = VertexBytes(d2, d3);
          Check(reduced < peak / 10, "peak capacity did not shrink");
          Check(![d2 memoryStats].releasePending && ![d3 memoryStats].releasePending,
                "release never completed");
        }
        for (auto command : commands)
          [command commit];
      }
      for (int page = 0; page < 3; ++page)
      {
        [commands[page] waitUntilCompleted];
        Check(commands[page].status == MTLCommandBufferStatusCompleted, "regrown frame failed");
        std::vector<uint32_t> pixels(128 * 128);
        [colors[page] getBytes:pixels.data()
                   bytesPerRow:128 * 4
                    fromRegion:MTLRegionMake2D(0, 0, 128, 128)
                   mipmapLevel:0];
        Check(pixels == expected[page], "regrowth changed pixels");
        [commands[page] release];
      }
      Check(VertexBytes(d2, d3) >= peak, "buffers failed to regrow");
      // A Start callback may queue vertices before the first beginFrame.
      [d2 fillRect:simd_make_float2(0, 0) to:simd_make_float2(10, 10) color:white];
      [d2 releaseUnusedMemory];
      const auto queued = [d2 memoryStats].vertexBufferBytes;
      [d2 beginFrame];
      Check([d2 memoryStats].vertexBufferBytes == queued, "queued vertices were dropped");
      [d2 discardFrame];
      [d2 beginFrame];
      Check([d2 memoryStats].vertexBufferBytes < queued, "discarded page was not reclaimed");
      std::printf("PASS: LRU/budgets/eviction, 3 frame pages, queued draws, shrink/regrow, "
                  "identical pixels; vertex_bytes=%lu -> %lu\n",
                  (unsigned long)peak,
                  (unsigned long)reduced);
      [d2 release];
      [d3 release];
      [depth release];
      for (auto color : colors)
        [color release];
      [queue release];
      [view release];
      [library release];
      [device release];
    }
    catch (const std::exception &error)
    {
      std::fprintf(stderr, "FAIL: %s\n", error.what());
      return 1;
    }
  }
}
