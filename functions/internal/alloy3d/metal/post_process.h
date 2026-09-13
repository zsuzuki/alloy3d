#pragma once
#import <Metal/Metal.h>
#include <alloy3d/camera.h>
#include <alloy3d/post_processing.h>
#include <array>

namespace alloy3d::metal
{
// Optional HDR targets. The caller must only reuse a page after its GPU work has completed.
struct VolumeUniforms
{
  simd_float4x4 inverseProjection, inverseView, shadowTransform;
  simd_float4   lightDirection, lightColor, shadowParameters;
  simd_float4   densityParameters, marchParameters;
};
class PostProcess
{
  struct Page
  {
    id<MTLTexture> color = nil, multisample = nil, bloom = nil, bloomScratch = nil, depth = nil,
                   sceneColor = nil, sceneDepth = nil, volume = nil;
    bool           releasePending = false;
  };
  id<MTLDevice>               device_;
  id<MTLLibrary>              library_      = nil;
  id<MTLComputePipelineState> bloomExtract_ = nil, bloomBlur_ = nil;
  id<MTLRenderPipelineState>  pipeline_   = nil;
  id<MTLDepthStencilState>    depthState_ = nil;
  NSUInteger                  samples_;
  bool                        sceneEffects_;
  id<MTLComputePipelineState> depthPipeline_ = nil, volumePipeline_ = nil;
  VolumeUniforms              volumeUniforms_{};
  id<MTLTexture>              volumeShadow_ = nil;
  void                        prepareVolume(id<MTLCommandBuffer>, NSUInteger);
  std::array<Page, 3>         pages_{};
  PostProcessing3D            settings_{};

public:
  PostProcess(id<MTLDevice>, id<MTLLibrary>, MTLPixelFormat colorFormat, MTLPixelFormat depthFormat,
              NSUInteger samples, bool sceneEffects = false);
  ~PostProcess();
  PostProcess(const PostProcess &)                        = delete;
  PostProcess             &operator=(const PostProcess &) = delete;
  void                     set(const PostProcessing3D &);
  MTLRenderPassDescriptor *begin(MTLRenderPassDescriptor *output, NSUInteger page);
  bool                     sceneEffects() const { return sceneEffects_; }
  void setVolumeScene(const CameraData &, simd_float3 lightDirection, simd_float3 lightColor,
                      simd_float4x4 shadowTransform, simd_float4 shadowParameters,
                      id<MTLTexture> shadowMap);
  void captureScene(id<MTLCommandBuffer>, NSUInteger page, const CameraData &camera);
  MTLRenderPassDescriptor *transparentPass(MTLRenderPassDescriptor *, NSUInteger page);
  id<MTLTexture>           sceneColor(NSUInteger page) const { return pages_.at(page).sceneColor; }
  id<MTLTexture>           sceneDepth(NSUInteger page) const { return pages_.at(page).sceneDepth; }
  void                     prepare(id<MTLCommandBuffer>, NSUInteger page);
  void                     encode(id<MTLRenderCommandEncoder>, NSUInteger page);
  void                     releaseUnusedMemory();
  size_t                   bytes() const;
  bool                     releasePending() const;
  id<MTLTexture>           color(NSUInteger page) const { return pages_.at(page).color; }
};
} // namespace alloy3d::metal
