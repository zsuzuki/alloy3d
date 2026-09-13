#pragma once
#import <Metal/Metal.h>
#include <alloy3d/post_processing.h>
#include <array>

namespace alloy3d::metal
{
// Optional HDR targets. The caller must only reuse a page after its GPU work has completed.
class PostProcess
{
  struct Page { id<MTLTexture> color=nil, multisample=nil, bloom=nil, bloomScratch=nil; bool releasePending=false; };
  id<MTLDevice> device_;
  id<MTLLibrary> library_=nil;
  id<MTLComputePipelineState> bloomExtract_=nil, bloomBlur_=nil;
  id<MTLRenderPipelineState> pipeline_=nil;
  id<MTLDepthStencilState> depthState_=nil;
  NSUInteger samples_;
  std::array<Page,3> pages_{};
  PostProcessing3D settings_{};
public:
  PostProcess(id<MTLDevice>,id<MTLLibrary>,MTLPixelFormat colorFormat,MTLPixelFormat depthFormat,NSUInteger samples);
  ~PostProcess();
  PostProcess(const PostProcess&)=delete;
  PostProcess& operator=(const PostProcess&)=delete;
  void set(const PostProcessing3D&);
  MTLRenderPassDescriptor *begin(MTLRenderPassDescriptor *output,NSUInteger page);
  void prepare(id<MTLCommandBuffer>,NSUInteger page);
  void encode(id<MTLRenderCommandEncoder>,NSUInteger page);
  void releaseUnusedMemory();
  size_t bytes() const;
  bool releasePending() const;
  id<MTLTexture> color(NSUInteger page) const { return pages_.at(page).color; }
};
} // namespace alloy3d::metal
