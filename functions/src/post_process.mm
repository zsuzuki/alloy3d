#include <alloy3d/metal/post_process.h>
#include <cmath>
#include <stdexcept>
#include <simd/simd.h>

namespace alloy3d::metal
{
PostProcess::PostProcess(id<MTLDevice> device,id<MTLLibrary> library,MTLPixelFormat colorFormat,
                         MTLPixelFormat depthFormat,NSUInteger samples,bool sceneEffects): device_(device),samples_(samples),sceneEffects_(sceneEffects)
{
  auto desc=[[[MTLRenderPipelineDescriptor alloc] init] autorelease];
  desc.label=@"Alloy3D HDR tone mapping";
  desc.vertexFunction=[[library newFunctionWithName:@"postProcessVertex"] autorelease];
  desc.fragmentFunction=[[library newFunctionWithName:@"toneMapFragment"] autorelease];
  desc.rasterSampleCount=samples;
  desc.colorAttachments[0].pixelFormat=colorFormat;
  desc.depthAttachmentPixelFormat=desc.stencilAttachmentPixelFormat=depthFormat;
  NSError *error=nil;pipeline_=[device newRenderPipelineStateWithDescriptor:desc error:&error];
  if(!pipeline_) throw std::runtime_error(error ? error.localizedDescription.UTF8String : "HDR pipeline creation failed");
  auto depth=[[[MTLDepthStencilDescriptor alloc] init] autorelease];
  depth.depthCompareFunction=MTLCompareFunctionAlways;depth.depthWriteEnabled=NO;
  depthState_=[device newDepthStencilStateWithDescriptor:depth];
  library_=[library retain];
}
PostProcess::~PostProcess()
{
  for(auto &page:pages_){[page.color release];[page.multisample release];[page.bloom release];[page.bloomScratch release];[page.depth release];[page.sceneColor release];[page.sceneDepth release];}
  [depthPipeline_ release];[pipeline_ release];[depthState_ release];[library_ release];[bloomExtract_ release];[bloomBlur_ release];
}
void PostProcess::set(const PostProcessing3D &settings)
{
  if(!std::isfinite(settings.exposure) || settings.exposure<0 || settings.exposure>16 ||
     int(settings.toneMapping)<0 || int(settings.toneMapping)>2 ||
     !std::isfinite(settings.bloom.strength) || settings.bloom.strength<0 || settings.bloom.strength>4 ||
     !std::isfinite(settings.bloom.threshold) || settings.bloom.threshold<0 || settings.bloom.threshold>64 ||
     !std::isfinite(settings.bloom.radius) || settings.bloom.radius<1 || settings.bloom.radius>32)
    throw std::invalid_argument("Alloy3D post processing requires exposure in [0,16] and a valid tone mapper");
  settings_=settings;
}
MTLRenderPassDescriptor *PostProcess::begin(MTLRenderPassDescriptor *output,NSUInteger index)
{
  auto &page=pages_.at(index);
  auto target=output.colorAttachments[0].texture;
  if(!target || !target.width || !target.height) throw std::invalid_argument("HDR requires a nonempty output target");
  if(!page.color || page.color.width!=target.width || page.color.height!=target.height || page.releasePending)
  {
    auto desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
        width:target.width height:target.height mipmapped:NO];
    desc.storageMode=MTLStorageModePrivate;
    desc.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
    auto color=[device_ newTextureWithDescriptor:desc];
    if(!color) throw std::bad_alloc();
    id<MTLTexture> multisample=nil;
    if(samples_>1)
    {
      desc.textureType=MTLTextureType2DMultisample;desc.sampleCount=samples_;
      desc.usage=MTLTextureUsageRenderTarget;
      multisample=[device_ newTextureWithDescriptor:desc];
      if(!multisample){[color release];throw std::bad_alloc();}
    }
    [page.color release];[page.multisample release];
    [page.bloom release];[page.bloomScratch release];page.bloom=page.bloomScratch=nil;
    page.color=color;page.multisample=multisample;page.releasePending=false;
    [page.depth release];[page.sceneColor release];[page.sceneDepth release];page.depth=page.sceneColor=page.sceneDepth=nil;
    if(sceneEffects_)
    {
      desc.textureType=MTLTextureType2D;desc.sampleCount=1;
      desc.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
      page.sceneColor=[device_ newTextureWithDescriptor:desc];
      desc.pixelFormat=MTLPixelFormatR32Float;desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
      page.sceneDepth=[device_ newTextureWithDescriptor:desc];
      desc.pixelFormat=output.depthAttachment.texture.pixelFormat;
      desc.textureType=samples_>1 ? MTLTextureType2DMultisample : MTLTextureType2D;desc.sampleCount=samples_;
      desc.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
      page.depth=[device_ newTextureWithDescriptor:desc];
      if(!page.sceneColor || !page.sceneDepth || !page.depth)throw std::bad_alloc();
    }
  }
  MTLRenderPassDescriptor *pass=[[output copy] autorelease];
  auto color=pass.colorAttachments[0];
  color.texture=page.multisample ? page.multisample : page.color;
  color.resolveTexture=page.multisample ? page.color : nil;
  color.loadAction=MTLLoadActionClear;
  color.storeAction=page.multisample ? MTLStoreActionMultisampleResolve : MTLStoreActionStore;
  if(sceneEffects_)
  {
    color.resolveTexture=page.multisample ? page.sceneColor : nil;
    color.storeAction=page.multisample ? MTLStoreActionStoreAndMultisampleResolve : MTLStoreActionStore;
    pass.depthAttachment.texture=pass.stencilAttachment.texture=page.depth;
    pass.depthAttachment.storeAction=pass.stencilAttachment.storeAction=MTLStoreActionStore;
  }
  return pass;
}
MTLRenderPassDescriptor *PostProcess::transparentPass(MTLRenderPassDescriptor *output,NSUInteger index)
{
  auto &page=pages_.at(index);MTLRenderPassDescriptor *pass=[[output copy] autorelease];
  auto color=pass.colorAttachments[0];color.texture=page.multisample ? page.multisample : page.color;
  color.resolveTexture=page.multisample ? page.color : nil;
  color.loadAction=MTLLoadActionLoad;color.storeAction=page.multisample ? MTLStoreActionMultisampleResolve : MTLStoreActionStore;
  pass.depthAttachment.texture=pass.stencilAttachment.texture=page.depth;
  pass.depthAttachment.loadAction=pass.stencilAttachment.loadAction=MTLLoadActionLoad;
  pass.depthAttachment.storeAction=pass.stencilAttachment.storeAction=MTLStoreActionDontCare;
  return pass;
}
void PostProcess::captureScene(id<MTLCommandBuffer> commands,NSUInteger index,const CameraData &camera)
{
  auto &page=pages_.at(index);
  if(!sceneEffects_)return;
  if(samples_==1)
  {
    auto blit=[commands blitCommandEncoder];[blit copyFromTexture:page.color toTexture:page.sceneColor];[blit endEncoding];
  }
  if(!depthPipeline_)
  {
    NSError *error=nil;
    depthPipeline_=[device_ newComputePipelineStateWithFunction:[[library_ newFunctionWithName:samples_>1 ? @"resolveSceneDepthMS" : @"resolveSceneDepth"] autorelease] error:&error];
    if(!depthPipeline_)throw std::runtime_error(error.localizedDescription.UTF8String);
  }
  struct { simd_float4x4 inverseProjection;simd_float4 parameters; } uniforms{
    simd_inverse(camera.getProjectionMatrix()),{camera.getProjectionMode()==ProjectionMode::Identity ? 1.f : -1.f,0,0,0}};
  auto encoder=[commands computeCommandEncoder];
  [encoder setComputePipelineState:depthPipeline_];[encoder setTexture:page.depth atIndex:0];[encoder setTexture:page.sceneDepth atIndex:1];
  [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
  [encoder dispatchThreads:MTLSizeMake(page.color.width,page.color.height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
  [encoder endEncoding];
}
void PostProcess::prepare(id<MTLCommandBuffer> commands,NSUInteger index)
{
  if(settings_.bloom.strength<=0)return;
  auto &page=pages_.at(index);
  if(!bloomExtract_)
  {
    NSError *error=nil;
    auto extract=[device_ newComputePipelineStateWithFunction:[[library_ newFunctionWithName:@"bloomExtract"] autorelease] error:&error];
    auto blur=[device_ newComputePipelineStateWithFunction:[[library_ newFunctionWithName:@"bloomBlur"] autorelease] error:&error];
    if(!extract || !blur){[extract release];[blur release];throw std::runtime_error("Bloom pipeline creation failed");}
    bloomExtract_=extract;bloomBlur_=blur;
  }
  if(!page.bloom)
  {
    auto desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
        width:(page.color.width+1)/2 height:(page.color.height+1)/2 mipmapped:NO];
    desc.storageMode=MTLStorageModePrivate;desc.usage=MTLTextureUsageShaderRead|MTLTextureUsageShaderWrite;
    auto bloom=[device_ newTextureWithDescriptor:desc],scratch=[device_ newTextureWithDescriptor:desc];
    if(!bloom || !scratch){[bloom release];[scratch release];throw std::bad_alloc();}
    page.bloom=bloom;page.bloomScratch=scratch;
  }
  auto dispatch=[&](id<MTLComputePipelineState> pipeline,id<MTLTexture> input,id<MTLTexture> output,simd_float4 parameters)
  {
    auto encoder=[commands computeCommandEncoder];encoder.label=@"Alloy3D bloom";
    [encoder setComputePipelineState:pipeline];[encoder setTexture:input atIndex:0];[encoder setTexture:output atIndex:1];
    [encoder setBytes:&parameters length:sizeof(parameters) atIndex:0];
    [encoder dispatchThreads:MTLSizeMake(output.width,output.height,1) threadsPerThreadgroup:MTLSizeMake(8,8,1)];
    [encoder endEncoding];
  };
  dispatch(bloomExtract_,page.color,page.bloom,simd_float4{settings_.bloom.threshold,0,0,0});
  dispatch(bloomBlur_,page.bloom,page.bloomScratch,simd_float4{settings_.bloom.radius,1,0,0});
  dispatch(bloomBlur_,page.bloomScratch,page.bloom,simd_float4{settings_.bloom.radius,0,1,0});
}
void PostProcess::encode(id<MTLRenderCommandEncoder> encoder,NSUInteger page)
{
  simd_float4 parameters={settings_.exposure,float(settings_.toneMapping),settings_.bloom.strength,0};
  [encoder setRenderPipelineState:pipeline_];
  [encoder setDepthStencilState:depthState_];
  [encoder setCullMode:MTLCullModeNone];
  [encoder setFragmentTexture:pages_.at(page).color atIndex:0];
  [encoder setFragmentTexture:settings_.bloom.strength>0 ? pages_.at(page).bloom : pages_.at(page).color atIndex:1];
  [encoder setFragmentBytes:&parameters length:sizeof(parameters) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
}
void PostProcess::releaseUnusedMemory(){for(auto &page:pages_)page.releasePending=true;}
size_t PostProcess::bytes() const
{
  size_t total=0;for(const auto &page:pages_)total+=page.color.allocatedSize+page.multisample.allocatedSize+page.bloom.allocatedSize+page.bloomScratch.allocatedSize+page.depth.allocatedSize+page.sceneColor.allocatedSize+page.sceneDepth.allocatedSize;
  return total;
}
bool PostProcess::releasePending() const
{
  for(const auto &page:pages_)if(page.releasePending)return true;
  return false;
}
} // namespace alloy3d::metal
