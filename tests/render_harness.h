#pragma once
#include <algorithm>
#include <alloy3d/camera.h>
#import <alloy3d/metal/draw3d.h>
#include <alloy3d/metal/normal_matrix.h>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <functional>
#include <stdexcept>
#include <vector>

using Instance = alloy3d::ModelInstance;
using Pixels   = std::vector<uint32_t>;
static void Check(bool condition, const char *message)
{
  if (!condition)
    throw std::runtime_error(message);
}

struct Harness
{
  id<MTLDevice>            device;
  id<MTLLibrary>           library;
  MTKView                 *view;
  Draw3D                  *draw;
  id<MTLCommandQueue>      queue;
  id<MTLTexture>           colors[3];
  id<MTLTexture>           depth;
  id<MTLDepthStencilState> depthState;
  id<MTLCommandBuffer>     commands[3] = {nil, nil, nil};
  double                   submitMs = 0, encodeMs = 0, gpuMs = 0;
  NSUInteger               size;

  Harness(id<MTLDevice> d, const char *shader, NSUInteger dimension = 256) : device(d), size(dimension)
  {
    NSError *error = nil;
    library = [d newLibraryWithURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:shader]]
                             error:&error];
    Check(library != nil, "shader library missing");
    view                  = [[MTKView alloc] initWithFrame:NSMakeRect(0, 0, 256, 256) device:d];
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    draw                         = [[Draw3D alloc] initWithMetalKitView:view shaderlib:library];
    queue                        = [d newCommandQueue];
    auto desc  = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:view.colorPixelFormat
                                                                    width:size
                                                                   height:size
                                                                mipmapped:NO];
    desc.usage = MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModeShared;
    for (auto &color : colors)
      color = [d newTextureWithDescriptor:desc];
    desc.pixelFormat        = view.depthStencilPixelFormat;
    desc.storageMode        = MTLStorageModePrivate;
    depth                   = [d newTextureWithDescriptor:desc];
    auto ds                 = [[MTLDepthStencilDescriptor alloc] init];
    ds.depthCompareFunction = MTLCompareFunctionLess;
    ds.depthWriteEnabled    = YES;
    depthState              = [d newDepthStencilStateWithDescriptor:ds];
    [ds release];
  }
  ~Harness()
  {
    for (auto command : commands)
    {
      if (command && command.status < MTLCommandBufferStatusCommitted)
        [command commit];
      [command waitUntilCompleted];
      [command release];
    }
    [draw release];
    [view release];
    [library release];
    [queue release];
    [depth release];
    [depthState release];
    for (auto color : colors)
      [color release];
  }
  MetalModel *Load(const std::filesystem::path &path)
  {
    auto model = [[MetalModel alloc] initWithFile:[NSString stringWithUTF8String:path.c_str()]
                                           device:device];
    Check(model.loaded, "fixture failed to load");
    return model;
  }
  void Begin(int slot)
  {
    if (commands[slot])
    {
      [commands[slot] waitUntilCompleted];
      Check(commands[slot].status == MTLCommandBufferStatusCompleted, "GPU command failed");
      [commands[slot] release];
      commands[slot] = nil;
    }
    [draw beginFrame];
  }
  void Encode(int slot, alloy3d::CameraData &camera,
              const std::function<void(id<MTLRenderCommandEncoder>)> &after = {})
  {
    auto pass                            = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture     = colors[slot];
    pass.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 0);
    pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.depthAttachment.texture         = depth;
    pass.depthAttachment.loadAction      = MTLLoadActionClear;
    pass.depthAttachment.clearDepth      = 1;
    pass.stencilAttachment.texture       = depth;
    pass.stencilAttachment.loadAction    = MTLLoadActionClear;
    commands[slot]                       = [[queue commandBuffer] retain];
    [draw encodeShadowMap:commands[slot] camera:&camera];
    auto encoder                         = [commands[slot] renderCommandEncoderWithDescriptor:pass];
    [encoder setDepthStencilState:depthState];
    [draw render:encoder camera:&camera];
    if (after)
      after(encoder);
    [encoder endEncoding];
  }
  Pixels Read(int slot)
  {
    [commands[slot] waitUntilCompleted];
    Check(commands[slot].status == MTLCommandBufferStatusCompleted, "GPU command failed");
    gpuMs = (commands[slot].GPUEndTime - commands[slot].GPUStartTime) * 1000;
    Pixels result(size * size);
    [colors[slot] getBytes:result.data()
               bytesPerRow:size * 4
                fromRegion:MTLRegionMake2D(0, 0, size, size)
               mipmapLevel:0];
    return result;
  }
  Pixels Run(alloy3d::CameraData &camera, const std::function<void()> &submit)
  {
    Begin(0);
    auto t0 = std::chrono::steady_clock::now();
    submit();
    auto t1 = std::chrono::steady_clock::now();
    Encode(0, camera);
    auto t2  = std::chrono::steady_clock::now();
    submitMs = std::chrono::duration<double, std::milli>(t1 - t0).count();
    encodeMs = std::chrono::duration<double, std::milli>(t2 - t1).count();
    [commands[0] commit];
    return Read(0);
  }
};
