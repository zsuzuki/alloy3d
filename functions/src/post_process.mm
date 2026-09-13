#include <alloy3d/metal/post_process.h>
#include <cmath>
#include <stdexcept>
#include <simd/simd.h>

namespace alloy3d::metal
{
PostProcess::PostProcess(id<MTLDevice> device,id<MTLLibrary> library,MTLPixelFormat colorFormat,
                         MTLPixelFormat depthFormat,NSUInteger samples): device_(device),samples_(samples)
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
}
PostProcess::~PostProcess()
{
  for(auto &page:pages_){[page.color release];[page.multisample release];}
  [pipeline_ release];[depthState_ release];
}
void PostProcess::set(const PostProcessing3D &settings)
{
  if(!std::isfinite(settings.exposure) || settings.exposure<0 || settings.exposure>16 ||
     int(settings.toneMapping)<0 || int(settings.toneMapping)>2)
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
    page.color=color;page.multisample=multisample;page.releasePending=false;
  }
  MTLRenderPassDescriptor *pass=[[output copy] autorelease];
  auto color=pass.colorAttachments[0];
  color.texture=page.multisample ? page.multisample : page.color;
  color.resolveTexture=page.multisample ? page.color : nil;
  color.loadAction=MTLLoadActionClear;
  color.storeAction=page.multisample ? MTLStoreActionMultisampleResolve : MTLStoreActionStore;
  return pass;
}
void PostProcess::encode(id<MTLRenderCommandEncoder> encoder,NSUInteger page)
{
  simd_float4 parameters={settings_.exposure,float(settings_.toneMapping),0,0};
  [encoder setRenderPipelineState:pipeline_];
  [encoder setDepthStencilState:depthState_];
  [encoder setCullMode:MTLCullModeNone];
  [encoder setFragmentTexture:pages_.at(page).color atIndex:0];
  [encoder setFragmentBytes:&parameters length:sizeof(parameters) atIndex:0];
  [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
}
void PostProcess::releaseUnusedMemory(){for(auto &page:pages_)page.releasePending=true;}
size_t PostProcess::bytes() const
{
  size_t total=0;for(const auto &page:pages_)total+=page.color.allocatedSize+page.multisample.allocatedSize;
  return total;
}
bool PostProcess::releasePending() const
{
  for(const auto &page:pages_)if(page.releasePending)return true;
  return false;
}
} // namespace alloy3d::metal
