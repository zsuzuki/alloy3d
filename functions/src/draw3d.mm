//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include "dsemaphore.h"
#include "model_shader_source.h"
#include "shader_def.h"
#import <Metal/Metal.h>
#include <algorithm>
#import <alloy3d/camera.h>
#import <alloy3d/metal/draw3d.h>
#import <alloy3d/metal/font_render.h>
#import <alloy3d/metal/memory_cache.h>
#include <alloy3d/metal/normal_matrix.h>
#include <alloy3d/metal/post_process.h>
#import <alloy3d/metal/texture.h>
#include <alloy3d/metal/vertex_buffer.h>
#include <alloy3d/shadow_camera.h>
#include <alloy3d/visibility.h>
#include <arm_neon.h>
#include <array>
#include <cmath>
#include <list>
#include <memory>
#include <simd/simd.h>
#include <utility>
#include <vector>

namespace
{
constexpr float Pi = 3.14159265358979323846f;

struct DrawText3D
{
  Texture    *texture;
  simd_float3 pos[4];
  simd_float4 color;

  ~DrawText3D() { [texture release]; }
};
using DrawText3DPtr = std::shared_ptr<DrawText3D>;

struct MetalModelShader final : alloy3d::ModelShader
{
  std::shared_ptr<const int> owner;
  id<MTLRenderPipelineState> pipelines[6] =
      {}; // opaque, blend, instances, blend instances, coverage, coverage instances
  ~MetalModelShader() override
  {
    for (auto pipeline : pipelines)
      [pipeline release];
  }
};

id<MTLFunction> NewModelFragment(id<MTLLibrary> library, bool coverage, NSError **error)
{
  auto values = [[MTLFunctionConstantValues alloc] init];
  [values setConstantValue:&coverage type:MTLDataTypeBool atIndex:0];
  auto function = [library newFunctionWithName:@"modelFrag3d" constantValues:values error:error];
  [values release];
  return function;
}

struct DrawModel3D
{
  MetalModel                       *model;
  simd_float3                       position;
  simd_float3                       rotation;
  simd_float3                       scale;
  simd_float4                       color;
  std::shared_ptr<MetalModelShader> shader;
  simd_float4                       parameters{};
  alloy3d::ModelHighlight3D         highlight;
  alloy3d::ModelTextureTransform3D  textureTransform;
  uint32_t                          maxAnisotropy   = 1;
  bool                              alphaToCoverage = false;
  float                             normalStrength  = 1;
  bool                              materialDetail  = false;
  alloy3d::ModelTransmission3D      transmission;
  simd_float2                       coverage = {0, 1};
  alloy3d::ModelWind3D              wind;
  alloy3d::ModelVisibility3D        visibility;
  float                             softDistance = 0;
  alloy3d::ModelScreenSpace3D       screenSpace;
  NSUInteger                        instanceOffset = 0;
  NSUInteger                        instanceCount  = 0;

  DrawModel3D(MetalModel *m, simd_float3 p, simd_float3 r, simd_float3 s, simd_float4 c)
      : model([m retain]), position(p), rotation(r), scale(s), color(c)
  {
  }
  DrawModel3D(MetalModel *m, NSUInteger offset, NSUInteger count)
      : model([m retain]), position{}, rotation{}, scale{}, color{}, instanceOffset(offset),
        instanceCount(count)
  {
  }
  DrawModel3D(const DrawModel3D &)            = delete;
  DrawModel3D &operator=(const DrawModel3D &) = delete;
  DrawModel3D(DrawModel3D &&other) noexcept
      : model(std::exchange(other.model, nil)), position(other.position), rotation(other.rotation),
        scale(other.scale), color(other.color), shader(std::move(other.shader)),
        parameters(other.parameters), highlight(other.highlight),
        textureTransform(other.textureTransform), maxAnisotropy(other.maxAnisotropy),
        alphaToCoverage(other.alphaToCoverage), normalStrength(other.normalStrength),
        materialDetail(other.materialDetail), transmission(other.transmission),
        coverage(other.coverage), wind(other.wind), visibility(other.visibility),
        softDistance(other.softDistance), screenSpace(other.screenSpace),
        instanceOffset(other.instanceOffset), instanceCount(other.instanceCount)
  {
  }
  ~DrawModel3D() { [model release]; }
  DrawModel3D(const DrawModel3D &source, NSUInteger offset, NSUInteger count)
      : DrawModel3D(source.model, offset, count)
  {
    shader           = source.shader;
    parameters       = source.parameters;
    highlight        = source.highlight;
    textureTransform = source.textureTransform;
    maxAnisotropy    = source.maxAnisotropy;
    alphaToCoverage  = source.alphaToCoverage;
    normalStrength   = source.normalStrength;
    materialDetail   = source.materialDetail;
    transmission     = source.transmission;
    coverage         = source.coverage;
    wind             = source.wind;
    visibility       = source.visibility;
    softDistance     = source.softDistance;
    screenSpace      = source.screenSpace;
  }
  bool sameStyle(const DrawModel3D &other) const
  {
    return screenSpace.refraction == other.screenSpace.refraction &&
           screenSpace.refractionPixels == other.screenSpace.refractionPixels &&
           screenSpace.reflection == other.screenSpace.reflection &&
           screenSpace.maxDistance == other.screenSpace.maxDistance &&
           screenSpace.thickness == other.screenSpace.thickness &&
           softDistance == other.softDistance && visibility.visible == other.visibility.visible &&
           visibility.castShadow == other.visibility.castShadow && shader == other.shader &&
           simd_all(parameters == other.parameters) &&
           highlight.strength == other.highlight.strength &&
           highlight.shininess == other.highlight.shininess &&
           simd_all(textureTransform.scale == other.textureTransform.scale) &&
           simd_all(textureTransform.offset == other.textureTransform.offset) &&
           maxAnisotropy == other.maxAnisotropy && alphaToCoverage == other.alphaToCoverage &&
           normalStrength == other.normalStrength && wind.strength == other.wind.strength &&
           wind.time == other.wind.time && simd_all(wind.direction == other.wind.direction) &&
           wind.baseHeight == other.wind.baseHeight && wind.tipHeight == other.wind.tipHeight &&
           wind.frequency == other.wind.frequency && materialDetail == other.materialDetail &&
           transmission.strength == other.transmission.strength &&
           simd_all(transmission.color == other.transmission.color);
  }
};

float WindPhase(simd_float3 position) { return position.x * .65f + position.z * .38f; }
void  SetWindUniforms(MaterialUniforms &material, const DrawModel3D &draw)
{
  material.wind      = {draw.wind.direction.x,
                        draw.wind.direction.y,
                        draw.wind.strength,
                        draw.wind.time * draw.wind.frequency};
  material.windShape = {draw.wind.baseHeight,
                        1.f / (draw.wind.tipHeight - draw.wind.baseHeight),
                        WindPhase(draw.position),
                        0};
}
alloy3d::Bounds3D WindBounds(alloy3d::Bounds3D bounds, const alloy3d::ModelWind3D &wind)
{
  if (bounds.isValid() && wind.strength > 0)
  {
    auto expansion = simd_make_float3(
        std::abs(wind.direction.x) * wind.strength, 0, std::abs(wind.direction.y) * wind.strength);
    bounds.min -= expansion;
    bounds.max += expansion;
  }
  return bounds;
}

struct TransparentPart
{
  const DrawModel3D *draw;
  ModelPart         *part;
  float              depth;
  size_t             order;
};

int ClampSegments(int value, int minValue) { return value < minValue ? minValue : value; }

void BuildBasis(simd_float3 axis, simd_float3 &basisX, simd_float3 &basisZ)
{
  auto helper = std::fabs(axis.y) < 0.95f ? simd_make_float3(0.0f, 1.0f, 0.0f)
                                          : simd_make_float3(1.0f, 0.0f, 0.0f);
  basisX      = simd_normalize(simd_cross(helper, axis));
  basisZ      = simd_normalize(simd_cross(axis, basisX));
}

void BuildEulerBasis(simd_float3 rotation, simd_float3 &axisX, simd_float3 &axisY,
                     simd_float3 &axisZ)
{
  float cx = std::cos(rotation.x);
  float sx = std::sin(rotation.x);
  float cy = std::cos(rotation.y);
  float sy = std::sin(rotation.y);
  float cz = std::cos(rotation.z);
  float sz = std::sin(rotation.z);

  axisX = simd_make_float3(cy * cz, sx * sy * cz + cx * sz, -cx * sy * cz + sx * sz);
  axisY = simd_make_float3(-cy * sz, -sx * sy * sz + cx * cz, cx * sy * sz + sx * cz);
  axisZ = simd_make_float3(sy, -sx * cy, cx * cy);
}

simd_float4x4 BuildModelMatrix(simd_float3 position, simd_float3 rotation, simd_float3 scale)
{
  simd_float3 axisX;
  simd_float3 axisY;
  simd_float3 axisZ;
  BuildEulerBasis(rotation, axisX, axisY, axisZ);

  return simd_matrix(simd_make_float4(axisX * scale.x, 0.0f),
                     simd_make_float4(axisY * scale.y, 0.0f),
                     simd_make_float4(axisZ * scale.z, 0.0f),
                     simd_make_float4(position.x, position.y, position.z, 1.0f));
}

} // namespace

@interface Draw3D ()
@end

@implementation Draw3D
{
  id<MTLDevice>  device_;
  MTLPixelFormat colorFormat_;
  MTLPixelFormat depthFormat_;
  NSUInteger     sampleCount_;
  CGFloat        contentScale_;
  NSUInteger     pageIndex_;

  id<MTLRenderPipelineState>                          pipelineState_;
  id<MTLRenderPipelineState>                          pipelineStateText_;
  id<MTLRenderPipelineState>                          pipelineStateModel_[3];
  id<MTLRenderPipelineState>                          pipelineStateModelInstances_[3];
  bool                                                transparentBatching_;
  bool                                                frustumCulling_;
  simd_float2                                         modelCoverage_;
  alloy3d::ModelWind3D                                modelWind_;
  alloy3d::ModelVisibility3D                          modelVisibility_;
  float                                               softDistance_;
  alloy3d::ModelScreenSpace3D                         screenSpace_;
  id<MTLTexture>                                      sceneColor_, sceneDepth_;
  size_t                                              instanceUsed_;
  id<MTLDepthStencilState>                            modelDepth_[2];
  std::vector<TransparentPart>                        transparentParts_;
  id<MTLBuffer>                                       uniformBuffer_[3][2];
  alloy3d::metal::VertexBuffer<VertexDataPrim3D>      vertices_[3];
  alloy3d::metal::VertexBuffer<VertexDataPrim3D>      verticesPlane_[3];
  alloy3d::metal::VertexBuffer<VertexData3D>          textVertices_[3];
  id<MTLTexture>                                      whiteTexture_;
  NSUInteger                                          nbPrimitives_;
  NSUInteger                                          nbPlanes_;
  simd_float3                                         lightDirection_;
  simd_float3                                         lightColor_;
  float                                               ambientIntensity_;
  float                                               diffuseIntensity_;
  FontRender                                         *fontRender_;
  MemoryCache                                        *textTextureCache_;
  bool                                                releasePending_[3];
  std::list<DrawText3DPtr>                            drawTextList_;
  std::vector<DrawModel3D>                            drawModelList_;
  std::vector<alloy3d::ModelInstance>                 modelInstances_;
  alloy3d::metal::VertexBuffer<ModelInstanceUniforms> instanceBuffers_[3];
  NSUInteger                                          modelDrawCalls_;

  std::shared_ptr<const int>        shaderOwner_;
  std::shared_ptr<MetalModelShader> modelShader_;
  simd_float4                       shaderParameters_;
  alloy3d::ModelHighlight3D         modelHighlight_;
  alloy3d::ModelTextureTransform3D  modelTextureTransform_;
  alloy3d::ModelTextureSampling3D   modelTextureSampling_;
  alloy3d::ModelNormalMapping3D     modelNormalMapping_;
  alloy3d::ModelMaterialDetail3D    modelMaterialDetail_;
  alloy3d::ModelTransmission3D      modelTransmission_;
  id<MTLSamplerState>               modelSamplers_[17]; // Bounded lazy cache, index 1..16.

  SimpleLock                   primLock_;
  SimpleLock                   planeLock_;
  alloy3d::DirectionalShadow3D shadowSettings_;
  alloy3d::Fog3D               fogSettings_;
  alloy3d::HemisphereLight3D   hemisphereSettings_;
  alloy3d::HeightFog3D         heightFogSettings_;
  float                        fogInverseRange_;
  id<MTLTexture>               shadowMaps_[3];
  id<MTLTexture>               shadowFallback_;
  id<MTLRenderPipelineState>   shadowPipelines_[3]; // primitive, model, instanced model
  simd_float4x4                lightViewProjection_;
  bool                         shadowReady_, instancesPrepared_;
  NSUInteger                   shadowDrawCalls_;

  SimpleLock textLock_;
  SimpleLock modelLock_;
}

//
- (void)initializePipeline:(id<MTLLibrary>)library
{
  NSError *error        = nil;
  auto     pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];

  auto vertexFunction   = [library newFunctionWithName:@"primVert3d"];
  auto fragmentFunction = [library newFunctionWithName:@"primFrag3d"];

  // text
  pipelineDesc.label                        = @"PipelinePrim3D";
  pipelineDesc.rasterSampleCount            = sampleCount_;
  pipelineDesc.vertexFunction               = vertexFunction;
  pipelineDesc.fragmentFunction             = fragmentFunction;
  pipelineDesc.vertexDescriptor             = nil;
  pipelineDesc.depthAttachmentPixelFormat   = depthFormat_;
  pipelineDesc.stencilAttachmentPixelFormat = depthFormat_;

  auto colorAttachment                      = pipelineDesc.colorAttachments[0];
  colorAttachment.pixelFormat               = colorFormat_;
  colorAttachment.blendingEnabled           = YES;
  colorAttachment.sourceRGBBlendFactor      = MTLBlendFactorSourceAlpha;
  colorAttachment.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  colorAttachment.rgbBlendOperation         = MTLBlendOperationAdd;

  pipelineState_ = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
  [vertexFunction release];
  [fragmentFunction release];

  vertexFunction   = [library newFunctionWithName:@"textVert3d"];
  fragmentFunction = [library newFunctionWithName:@"textFrag3d"];

  pipelineDesc.label            = @"PipelineText3D";
  pipelineDesc.vertexFunction   = vertexFunction;
  pipelineDesc.fragmentFunction = fragmentFunction;

  pipelineStateText_ = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
  [vertexFunction release];
  [fragmentFunction release];

  vertexFunction   = [library newFunctionWithName:@"modelVert3d"];
  fragmentFunction = NewModelFragment(library, false, &error);

  pipelineDesc.label            = @"PipelineModel3D";
  pipelineDesc.vertexFunction   = vertexFunction;
  pipelineDesc.fragmentFunction = fragmentFunction;

  auto coverageFragment = NewModelFragment(library, true, &error);
  if (!fragmentFunction || !coverageFragment)
    throw std::runtime_error("Alloy3D model fragment specialization failed");
  for (int mode = 0; mode < 3; ++mode)
  {
    bool blend                          = mode == 1;
    pipelineDesc.fragmentFunction       = mode == 2 ? coverageFragment : fragmentFunction;
    pipelineDesc.alphaToCoverageEnabled = pipelineDesc.alphaToOneEnabled =
        sampleCount_ > 1 && mode == 2;
    colorAttachment.blendingEnabled             = blend;
    colorAttachment.sourceAlphaBlendFactor      = MTLBlendFactorOne;
    colorAttachment.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineStateModel_[mode] = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc
                                                                        error:&error];
    if (!pipelineStateModel_[mode])
      throw std::runtime_error("Alloy3D model pipeline creation failed");
    if (mode < 2)
    {
      auto depth                 = [[MTLDepthStencilDescriptor alloc] init];
      depth.depthCompareFunction = MTLCompareFunctionLess;
      depth.depthWriteEnabled    = !blend;
      modelDepth_[mode]          = [device_ newDepthStencilStateWithDescriptor:depth];
      [depth release];
    }
  }
  [vertexFunction release];
  vertexFunction              = [library newFunctionWithName:@"modelInstanceVert3d"];
  pipelineDesc.vertexFunction = vertexFunction;
  for (int mode = 0; mode < 3; ++mode)
  {
    pipelineDesc.fragmentFunction       = mode == 2 ? coverageFragment : fragmentFunction;
    pipelineDesc.alphaToCoverageEnabled = pipelineDesc.alphaToOneEnabled =
        sampleCount_ > 1 && mode == 2;
    colorAttachment.blendingEnabled    = mode == 1;
    pipelineStateModelInstances_[mode] = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc
                                                                                 error:&error];
    if (!pipelineStateModelInstances_[mode])
      throw std::runtime_error("Alloy3D instance pipeline creation failed");
  }
  [vertexFunction release];
  [fragmentFunction release];
  [coverageFragment release];

  [pipelineDesc release];
  auto shadowDesc                          = [[MTLRenderPipelineDescriptor alloc] init];
  shadowDesc.depthAttachmentPixelFormat    = MTLPixelFormatDepth32Float;
  const std::array<NSString *, 3> vertices = {
      @"primVert3d", @"modelVert3d", @"modelInstanceVert3d"};
  for (int i = 0; i < 3; ++i)
  {
    shadowDesc.vertexFunction = [library newFunctionWithName:vertices[i]];
    shadowDesc.fragmentFunction =
        [library newFunctionWithName:i == 0 ? @"shadowPrimFrag3d" : @"shadowModelFrag3d"];
    shadowPipelines_[i] = [device_ newRenderPipelineStateWithDescriptor:shadowDesc error:&error];
    [shadowDesc.vertexFunction release];
    [shadowDesc.fragmentFunction release];
    if (!shadowPipelines_[i])
      throw std::runtime_error("Alloy3D shadow pipeline creation failed");
  }
  [shadowDesc release];
  auto depthDesc =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                         width:1
                                                        height:1
                                                     mipmapped:NO];
  depthDesc.storageMode = MTLStorageModePrivate;
  depthDesc.usage       = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
  shadowFallback_       = [device_ newTextureWithDescriptor:depthDesc];
  if (!shadowFallback_)
    throw std::bad_alloc();
}

- (alloy3d::ModelShaderPtr)createModelShader:(std::string_view)source
                                 diagnostics:(std::string &)diagnostics
{
  return [self createModelShader:source materialStage:false diagnostics:diagnostics];
}

- (alloy3d::ModelShaderPtr)createModelMaterialShader:(std::string_view)source
                                         diagnostics:(std::string &)diagnostics
{
  return [self createModelShader:source materialStage:true diagnostics:diagnostics];
}

- (alloy3d::ModelShaderPtr)createModelShader:(std::string_view)source
                               materialStage:(bool)materialStage
                                 diagnostics:(std::string &)diagnostics
{
  diagnostics.clear();
  if (source.empty() || source.find('\0') != std::string_view::npos)
  {
    diagnostics = "Model shader source must be nonempty UTF-8 without null characters";
    return {};
  }
  @autoreleasepool
  {
    std::string combined = "#include <metal_stdlib>\n#define ALLOY3D_CUSTOM_SURFACE 1\n";
    if (materialStage)
      combined += "#define ALLOY3D_CUSTOM_MATERIAL 1\n";
    combined += ModelShaderPrefix;
    combined += "\n#line 1 \"model_surface_user.metal\"\n";
    combined.append(source);
    if (materialStage)
      combined += "\nfloat3 alloy3dShade(ModelSurface s,float4 p){return s.litColor;}\n";
    combined += "\n#line 1 \"simple3d.metal\"\n";
    combined += ModelShaderBody;
    auto text = [[[NSString alloc] initWithBytes:combined.data()
                                          length:combined.size()
                                        encoding:NSUTF8StringEncoding] autorelease];
    if (!text)
    {
      diagnostics = "Model shader source is not valid UTF-8";
      return {};
    }
    NSError *error   = nil;
    auto     library = [[device_ newLibraryWithSource:text options:nil error:&error] autorelease];
    if (!library)
    {
      diagnostics =
          error ? error.localizedDescription.UTF8String : "Model shader compilation failed";
      return {};
    }
    auto shader                  = std::make_shared<MetalModelShader>();
    shader->owner                = shaderOwner_;
    auto descriptor              = [[[MTLRenderPipelineDescriptor alloc] init] autorelease];
    descriptor.label             = @"Alloy3D custom model surface";
    descriptor.rasterSampleCount = sampleCount_;
    descriptor.depthAttachmentPixelFormat   = depthFormat_;
    descriptor.stencilAttachmentPixelFormat = depthFormat_;
    auto baseFragment     = [NewModelFragment(library, false, &error) autorelease];
    auto coverageFragment = [NewModelFragment(library, true, &error) autorelease];
    if (!baseFragment || !coverageFragment)
    {
      diagnostics = error ? error.localizedDescription.UTF8String : "Model specialization failed";
      return {};
    }
    auto color                        = descriptor.colorAttachments[0];
    color.pixelFormat                 = colorFormat_;
    color.sourceRGBBlendFactor        = MTLBlendFactorSourceAlpha;
    color.destinationRGBBlendFactor   = MTLBlendFactorOneMinusSourceAlpha;
    color.sourceAlphaBlendFactor      = MTLBlendFactorOne;
    color.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    for (int i = 0; i < 6; ++i)
    {
      descriptor.vertexFunction =
          [[library newFunctionWithName:(i == 2 || i == 3 || i == 5) ? @"modelInstanceVert3d"
                                                                     : @"modelVert3d"] autorelease];
      descriptor.fragmentFunction       = i >= 4 ? coverageFragment : baseFragment;
      descriptor.alphaToCoverageEnabled = descriptor.alphaToOneEnabled = sampleCount_ > 1 && i >= 4;
      color.blendingEnabled                                            = i == 1 || i == 3;
      shader->pipelines[i] = [device_ newRenderPipelineStateWithDescriptor:descriptor error:&error];
      if (!shader->pipelines[i])
      {
        diagnostics =
            error ? error.localizedDescription.UTF8String : "Model shader pipeline creation failed";
        return {};
      }
    }
    return shader;
  }
}

- (bool)setModelShader:(alloy3d::ModelShaderPtr)shader parameters:(simd_float4)parameters
{
  if (!std::isfinite(parameters.x) || !std::isfinite(parameters.y) ||
      !std::isfinite(parameters.z) || !std::isfinite(parameters.w))
    return false;
  auto concrete = std::dynamic_pointer_cast<MetalModelShader>(shader);
  if (shader && (!concrete || concrete->owner != shaderOwner_))
    return false;
  modelShader_      = std::move(concrete);
  shaderParameters_ = parameters;
  return true;
}

- (void)setModelTextureTransform:(const alloy3d::ModelTextureTransform3D &)transform
{
  if (!std::isfinite(transform.scale.x) || !std::isfinite(transform.scale.y) ||
      !std::isfinite(transform.offset.x) || !std::isfinite(transform.offset.y))
    throw std::invalid_argument("Alloy3D model texture scale and offset must be finite");
  modelTextureTransform_ = transform;
}

- (id<MTLSamplerState>)modelSampler:(uint32_t)anisotropy
{
  if (!modelSamplers_[anisotropy])
  {
    auto desc      = [[MTLSamplerDescriptor alloc] init];
    desc.minFilter = desc.magFilter = MTLSamplerMinMagFilterLinear;
    desc.mipFilter                  = MTLSamplerMipFilterLinear;
    desc.sAddressMode = desc.tAddressMode = desc.rAddressMode = MTLSamplerAddressModeRepeat;
    desc.maxAnisotropy                                        = anisotropy;
    auto sampler = [device_ newSamplerStateWithDescriptor:desc];
    [desc release];
    if (!sampler)
      throw std::bad_alloc();
    modelSamplers_[anisotropy] = sampler;
  }
  return modelSamplers_[anisotropy];
}

- (void)setModelTextureSampling:(const alloy3d::ModelTextureSampling3D &)sampling
{
  if (sampling.maxAnisotropy < 1 || sampling.maxAnisotropy > 16)
    throw std::invalid_argument("Alloy3D anisotropy must be in [1,16]");
  [self modelSampler:sampling.maxAnisotropy];
  modelTextureSampling_ = sampling;
}

- (void)setModelNormalMapping:(const alloy3d::ModelNormalMapping3D &)mapping
{
  if (!std::isfinite(mapping.strength) || mapping.strength < 0 || mapping.strength > 8)
    throw std::invalid_argument("Alloy3D normal strength must be finite in [0,8]");
  modelNormalMapping_ = mapping;
}

- (void)setModelMaterialDetail:(const alloy3d::ModelMaterialDetail3D &)detail
{
  modelMaterialDetail_ = detail;
}

- (void)setModelTransmission:(const alloy3d::ModelTransmission3D &)transmission
{
  auto color = transmission.color;
  if (!std::isfinite(transmission.strength) || transmission.strength < 0 ||
      transmission.strength > 1 || !simd_all(color >= 0) || !simd_all(color <= 1))
    throw std::invalid_argument("Alloy3D transmission strength and color must be finite in [0,1]");
  modelTransmission_ = transmission;
}

- (void)setModelHighlight:(const alloy3d::ModelHighlight3D &)highlight
{
  if (!std::isfinite(highlight.strength) || highlight.strength < 0 || highlight.strength > 1 ||
      !std::isfinite(highlight.shininess) || highlight.shininess < 1 || highlight.shininess > 128)
    throw std::invalid_argument(
        "Alloy3D model highlight requires strength in [0,1] and shininess in [1,128]");
  modelHighlight_ = highlight;
}

- (void)initializeWhiteTexture
{
  uint8_t pixel[] = {255, 255, 255, 255};

  auto texdesc        = [[MTLTextureDescriptor alloc] init];
  texdesc.width       = 1;
  texdesc.height      = 1;
  texdesc.pixelFormat = MTLPixelFormatRGBA8Unorm;
  texdesc.textureType = MTLTextureType2D;
  texdesc.storageMode = MTLStorageModeManaged;
  texdesc.usage       = MTLTextureUsageShaderRead;

  whiteTexture_ = [device_ newTextureWithDescriptor:texdesc];
  [whiteTexture_ replaceRegion:MTLRegionMake2D(0, 0, 1, 1)
                   mipmapLevel:0
                     withBytes:pixel
                   bytesPerRow:4];
  [texdesc release];
}

//
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
                                   shaderlib:(nonnull id<MTLLibrary>)library
{
  return [self initWithMetalKitView:view shaderlib:library colorFormat:view.colorPixelFormat];
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
                                   shaderlib:(nonnull id<MTLLibrary>)library
                                 colorFormat:(MTLPixelFormat)format
{
  [super init];

  modelCoverage_ = {0, 1};
  shaderOwner_   = std::make_shared<const int>(0);
  device_        = view.device;
  colorFormat_   = format;
  depthFormat_   = view.depthStencilPixelFormat;
  sampleCount_   = view.sampleCount;
  [self modelSampler:1];
  contentScale_     = [[NSScreen mainScreen] backingScaleFactor];
  pageIndex_        = 0;
  nbPrimitives_     = 0;
  nbPlanes_         = 0;
  lightDirection_   = simd_normalize(simd_make_float3(-0.4f, -0.8f, -0.6f));
  lightColor_       = simd_make_float3(1.0f, 1.0f, 1.0f);
  ambientIntensity_ = 0.25f;
  diffuseIntensity_ = 0.85f;
  [self initializePipeline:library];
  [self initializeWhiteTexture];

  for (int i = 0; i < 3; i++)
  {
    for (int phase = 0; phase < 2; ++phase)
      uniformBuffer_[i][phase] = [device_ newBufferWithLength:sizeof(Uniforms)
                                                      options:MTLResourceStorageModeShared];
  }
  fontRender_ = [[FontRender alloc] init];
  textTextureCache_ =
      [[MemoryCache alloc] initWithLimit:alloy3d::TextCacheBudget{}.textureBytes / 2];

  [fontRender_ SetSize:64.0f];

  return self;
}

//
- (void)dealloc
{
  for (auto sampler : modelSamplers_)
    [sampler release];
  for (int i = 0; i < 3; i++)
  {
    for (auto buffer : uniformBuffer_[i])
      [buffer release];
    [shadowMaps_[i] release];
    [shadowPipelines_[i] release];
  }
  [fontRender_ release];
  [textTextureCache_ release];
  [pipelineState_ release];
  [pipelineStateText_ release];
  for (int blend = 0; blend < 3; ++blend)
  {
    [pipelineStateModel_[blend] release];
    if (blend < 2)
      [modelDepth_[blend] release];
  }
  for (auto pipeline : pipelineStateModelInstances_)
    [pipeline release];
  [whiteTexture_ release];
  [shadowFallback_ release];
  [super dealloc];
}

//
- (void)drawLine:(simd_float3)from to:(simd_float3)to color:(simd_float4)color
{
  SimpleGuard guard(primLock_);
  auto       *vtx3d = vertices_[pageIndex_].append(device_, nbPrimitives_, 2);
  nbPrimitives_ += 2;

  auto col16        = vcvt_f16_f32(color);
  vtx3d[0].position = from;
  vtx3d[0].normal   = simd_make_float3(0.0f, 0.0f, 0.0f);
  vtx3d[0].color    = col16;
  vtx3d[1].position = to;
  vtx3d[1].normal   = simd_make_float3(0.0f, 0.0f, 0.0f);
  vtx3d[1].color    = col16;
}

//
- (void)drawTriangle:(simd_float3)p0 p1:(simd_float3)p1 p2:(simd_float3)p2 color:(simd_float4)color
{
  auto normal = simd_cross(p1 - p0, p2 - p0);
  if (simd_length_squared(normal) > 0.000001f)
  {
    normal = simd_normalize(normal);
  }
  else
  {
    normal = simd_make_float3(0.0f, 0.0f, 0.0f);
  }

  [self drawTriangle:p0 normal:normal p1:p1 normal:normal p2:p2 normal:normal color:color];
}

//
- (void)drawTriangle:(simd_float3)p0
              normal:(simd_float3)n0
                  p1:(simd_float3)p1
              normal:(simd_float3)n1
                  p2:(simd_float3)p2
              normal:(simd_float3)n2
               color:(simd_float4)color
{
  SimpleGuard guard(planeLock_);
  auto       *vtx3d = verticesPlane_[pageIndex_].append(device_, nbPlanes_, 3);
  nbPlanes_ += 3;

  auto col16        = vcvt_f16_f32(color);
  vtx3d[0].position = p0;
  vtx3d[0].normal   = n0;
  vtx3d[0].color    = col16;
  vtx3d[1].position = p1;
  vtx3d[1].normal   = n1;
  vtx3d[1].color    = col16;
  vtx3d[2].position = p2;
  vtx3d[2].normal   = n2;
  vtx3d[2].color    = col16;
}

//
- (void)drawQuad:(simd_float3)p0
              p1:(simd_float3)p1
              p2:(simd_float3)p2
              p3:(simd_float3)p3
          normal:(simd_float3)normal
           color:(simd_float4)color
{
  [self drawTriangle:p0 normal:normal p1:p1 normal:normal p2:p2 normal:normal color:color];
  [self drawTriangle:p0 normal:normal p1:p2 normal:normal p2:p3 normal:normal color:color];
}

//
- (void)drawPlane:(simd_float3)p0
               p1:(simd_float3)p1
               p2:(simd_float3)p2
               p3:(simd_float3)p3
            color:(simd_float4)color
{
  [self drawTriangle:p2 p1:p1 p2:p0 color:color];
  [self drawTriangle:p3 p1:p2 p2:p0 color:color];
}

//
- (void)drawSphere:(simd_float3)center
            radius:(float)radius
             color:(simd_float4)color
            slices:(int)slices
            stacks:(int)stacks
{
  if (radius <= 0.0f)
  {
    return;
  }

  slices = ClampSegments(slices, 3);
  stacks = ClampSegments(stacks, 2);

  // Reserve the whole sphere once instead of locking and dispatching twice per cell.
  const NSUInteger maxCells = device_.maxBufferLength / sizeof(VertexDataPrim3D) / 6;
  if (static_cast<NSUInteger>(slices) > maxCells / static_cast<NSUInteger>(stacks))
    throw std::length_error("Alloy3D sphere exceeds device capacity");
  const NSUInteger vertexCount = static_cast<NSUInteger>(slices) * stacks * 6;
  SimpleGuard      guard(planeLock_);
  auto            *vertex = verticesPlane_[pageIndex_].append(device_, nbPlanes_, vertexCount);
  nbPlanes_ += vertexCount;
  const auto col16 = vcvt_f16_f32(color);
  auto       emit  = [&](simd_float3 position, simd_float3 normal)
  {
    vertex->position = position;
    vertex->normal   = normal;
    vertex->color    = col16;
    ++vertex;
  };

  for (int stack = 0; stack < stacks; stack++)
  {
    float phi0 = Pi * (float)stack / (float)stacks;
    float phi1 = Pi * (float)(stack + 1) / (float)stacks;

    for (int slice = 0; slice < slices; slice++)
    {
      float theta0 = 2.0f * Pi * (float)slice / (float)slices;
      float theta1 = 2.0f * Pi * (float)(slice + 1) / (float)slices;

      auto makeNormal = [](float phi, float theta)
      {
        float sinPhi = std::sin(phi);
        return simd_make_float3(sinPhi * std::cos(theta), std::cos(phi), sinPhi * std::sin(theta));
      };

      auto n00 = makeNormal(phi0, theta0);
      auto n10 = makeNormal(phi1, theta0);
      auto n11 = makeNormal(phi1, theta1);
      auto n01 = makeNormal(phi0, theta1);
      auto p00 = center + n00 * radius;
      auto p10 = center + n10 * radius;
      auto p11 = center + n11 * radius;
      auto p01 = center + n01 * radius;

      emit(p00, n00);
      emit(p10, n10);
      emit(p11, n11);
      emit(p00, n00);
      emit(p11, n11);
      emit(p01, n01);
    }
  }
}

//
- (void)drawBox:(simd_float3)center size:(simd_float3)size color:(simd_float4)color
{
  [self drawBox:center size:size rotation:simd_make_float3(0.0f, 0.0f, 0.0f) color:color];
}

//
- (void)drawBox:(simd_float3)center
           size:(simd_float3)size
      rotationY:(float)rotationY
          color:(simd_float4)color
{
  [self drawBox:center size:size rotation:simd_make_float3(0.0f, rotationY, 0.0f) color:color];
}

//
- (void)drawBox:(simd_float3)center
           size:(simd_float3)size
       rotation:(simd_float3)rotation
          color:(simd_float4)color
{
  simd_float3 axisX;
  simd_float3 axisY;
  simd_float3 axisZ;
  BuildEulerBasis(rotation, axisX, axisY, axisZ);

  auto halfSize = size * 0.5f;
  auto hx       = axisX * halfSize.x;
  auto hy       = axisY * halfSize.y;
  auto hz       = axisZ * halfSize.z;

  simd_float3 p000 = center - hx - hy - hz;
  simd_float3 p001 = center - hx - hy + hz;
  simd_float3 p010 = center - hx + hy - hz;
  simd_float3 p011 = center - hx + hy + hz;
  simd_float3 p100 = center + hx - hy - hz;
  simd_float3 p101 = center + hx - hy + hz;
  simd_float3 p110 = center + hx + hy - hz;
  simd_float3 p111 = center + hx + hy + hz;

  [self drawQuad:p001 p1:p101 p2:p111 p3:p011 normal:axisZ color:color];
  [self drawQuad:p100 p1:p000 p2:p010 p3:p110 normal:-axisZ color:color];
  [self drawQuad:p101 p1:p100 p2:p110 p3:p111 normal:axisX color:color];
  [self drawQuad:p000 p1:p001 p2:p011 p3:p010 normal:-axisX color:color];
  [self drawQuad:p010 p1:p011 p2:p111 p3:p110 normal:axisY color:color];
  [self drawQuad:p000 p1:p100 p2:p101 p3:p001 normal:-axisY color:color];
}

//
- (void)drawCylinder:(simd_float3)center
              radius:(float)radius
              height:(float)height
               color:(simd_float4)color
            segments:(int)segments
{
  [self drawCylinder:center
              radius:radius
              height:height
            rotation:simd_make_float3(0.0f, 0.0f, 0.0f)
               color:color
            segments:segments];
}

//
- (void)drawCylinder:(simd_float3)center
              radius:(float)radius
              height:(float)height
            rotation:(simd_float3)rotation
               color:(simd_float4)color
            segments:(int)segments
{
  if (radius <= 0.0f || height <= 0.0f)
  {
    return;
  }

  segments = ClampSegments(segments, 3);
  simd_float3 axisX;
  simd_float3 axisY;
  simd_float3 axisZ;
  BuildEulerBasis(rotation, axisX, axisY, axisZ);

  auto bottomCenter = center - axisY * (height * 0.5f);
  auto topCenter    = center + axisY * (height * 0.5f);
  auto bottomNormal = -axisY;
  auto topNormal    = axisY;

  for (int segment = 0; segment < segments; segment++)
  {
    float theta0 = 2.0f * Pi * (float)segment / (float)segments;
    float theta1 = 2.0f * Pi * (float)(segment + 1) / (float)segments;
    auto  n0     = axisX * std::cos(theta0) + axisZ * std::sin(theta0);
    auto  n1     = axisX * std::cos(theta1) + axisZ * std::sin(theta1);
    auto  b0     = bottomCenter + n0 * radius;
    auto  b1     = bottomCenter + n1 * radius;
    auto  t0     = topCenter + n0 * radius;
    auto  t1     = topCenter + n1 * radius;

    [self drawTriangle:b0 normal:n0 p1:t0 normal:n0 p2:t1 normal:n1 color:color];
    [self drawTriangle:b0 normal:n0 p1:t1 normal:n1 p2:b1 normal:n1 color:color];
    [self drawTriangle:bottomCenter
                normal:bottomNormal
                    p1:b1
                normal:bottomNormal
                    p2:b0
                normal:bottomNormal
                 color:color];
    [self drawTriangle:topCenter
                normal:topNormal
                    p1:t0
                normal:topNormal
                    p2:t1
                normal:topNormal
                 color:color];
  }
}

//
- (void)drawCone:(simd_float3)center
          radius:(float)radius
          height:(float)height
           color:(simd_float4)color
        segments:(int)segments
{
  [self drawCone:center
          radius:radius
          height:height
        rotation:simd_make_float3(0.0f, 0.0f, 0.0f)
           color:color
        segments:segments];
}

//
- (void)drawCone:(simd_float3)center
          radius:(float)radius
          height:(float)height
        rotation:(simd_float3)rotation
           color:(simd_float4)color
        segments:(int)segments
{
  simd_float3 axisX;
  simd_float3 axisY;
  simd_float3 axisZ;
  BuildEulerBasis(rotation, axisX, axisY, axisZ);

  [self drawCone:center direction:axisY radius:radius height:height color:color segments:segments];
}

//
- (void)drawCone:(simd_float3)center
       direction:(simd_float3)direction
          radius:(float)radius
          height:(float)height
           color:(simd_float4)color
        segments:(int)segments
{
  if (radius <= 0.0f || height <= 0.0f || simd_length_squared(direction) <= 0.000001f)
  {
    return;
  }

  segments = ClampSegments(segments, 3);

  auto        axis         = simd_normalize(direction);
  auto        bottomCenter = center - axis * (height * 0.5f);
  auto        apex         = center + axis * (height * 0.5f);
  auto        bottomNormal = -axis;
  simd_float3 basisX;
  simd_float3 basisZ;
  BuildBasis(axis, basisX, basisZ);

  for (int segment = 0; segment < segments; segment++)
  {
    float theta0     = 2.0f * Pi * (float)segment / (float)segments;
    float theta1     = 2.0f * Pi * (float)(segment + 1) / (float)segments;
    auto  d0         = basisX * std::cos(theta0) + basisZ * std::sin(theta0);
    auto  d1         = basisX * std::cos(theta1) + basisZ * std::sin(theta1);
    auto  b0         = bottomCenter + d0 * radius;
    auto  b1         = bottomCenter + d1 * radius;
    auto  n0         = simd_normalize(d0 * height + axis * radius);
    auto  n1         = simd_normalize(d1 * height + axis * radius);
    auto  apexNormal = simd_normalize(n0 + n1);

    [self drawTriangle:b0 normal:n0 p1:b1 normal:n1 p2:apex normal:apexNormal color:color];
    [self drawTriangle:bottomCenter
                normal:bottomNormal
                    p1:b1
                normal:bottomNormal
                    p2:b0
                normal:bottomNormal
                 color:color];
  }
}

//
- (void)setTextFont:(nonnull NSString *)fontName
{
  [fontRender_ SetFont:[fontName UTF8String]];
}

//
- (void)setTextFontSize:(float)fontSize
{
  [fontRender_ SetSize:fontSize];
}

//
- (void)drawText:(nonnull NSString *)message
        position:(simd_float3)position
      lineHeight:(float)lineHeight
           align:(DrawText3DAlign)align
           color:(simd_float4)color
{
  [self drawText:message
        position:position
      lineHeight:lineHeight
        rotation:simd_make_float3(0.0f, 0.0f, 0.0f)
           align:align
           color:color];
}

//
- (void)drawText:(nonnull NSString *)message
        position:(simd_float3)position
      lineHeight:(float)lineHeight
        rotation:(simd_float3)rotation
           align:(DrawText3DAlign)align
           color:(simd_float4)color
{
  if ([message length] == 0 || lineHeight <= 0.0f)
  {
    return;
  }

  NSString *cacheKey = [fontRender_ CacheKey:message];
  [fontRender_ Render:message
             callback:^(CGContextRef ctx, CGRect rect) {
               auto bitmapWidth  = static_cast<float>(std::max<CGFloat>(1.0f, rect.size.width));
               auto bitmapHeight = static_cast<float>(std::max<CGFloat>(1.0f, rect.size.height));
               auto textWidth    = lineHeight * bitmapWidth / bitmapHeight;

               Texture *texture = [textTextureCache_ objectForKey:cacheKey];
               if (texture == nil)
               {
                 texture = [[Texture alloc] initWithMemory:ctx device:device_];
                 [textTextureCache_ setObject:texture
                                       forKey:cacheKey
                                         cost:texture.object.allocatedSize];
               }
               else
               {
                 [texture retain];
               }

               simd_float3 axisX;
               simd_float3 axisY;
               simd_float3 axisZ;
               BuildEulerBasis(rotation, axisX, axisY, axisZ);

               float anchorX = 0.0f;
               if (align == DrawText3DAlignCenterBottom)
               {
                 anchorX = -textWidth * 0.5f;
               }
               else if (align == DrawText3DAlignRightBottom)
               {
                 anchorX = -textWidth;
               }

               auto p0 = position + axisX * (anchorX + textWidth);
               auto p1 = position + axisX * anchorX;
               auto p2 = p0 + axisY * lineHeight;
               auto p3 = p1 + axisY * lineHeight;

               auto dtext     = std::make_shared<DrawText3D>();
               dtext->texture = texture;
               dtext->color   = color;
               dtext->pos[0]  = p0;
               dtext->pos[1]  = p1;
               dtext->pos[2]  = p2;
               dtext->pos[3]  = p3;

               textLock_.lock();
               drawTextList_.push_back(dtext);
               textLock_.unlock();
             }];
}

//
- (void)setLightDirection:(simd_float3)direction ambient:(float)ambient diffuse:(float)diffuse
{
  if (std::isfinite(direction.x) && std::isfinite(direction.y) && std::isfinite(direction.z))
  {
    auto wide = simd_make_double3(direction.x, direction.y, direction.z);
    if (simd_length_squared(wide) > 0.000001)
    {
      wide                  = simd_normalize(wide);
      const auto normalized = simd_make_float3(wide.x, wide.y, wide.z);
      if (shadowSettings_.enabled)
        alloy3d::BuildDirectionalShadowCamera3D(shadowSettings_, normalized);
      lightDirection_ = normalized;
    }
  }
  ambientIntensity_ = fmaxf(0.0f, fminf(1.0f, ambient));
  diffuseIntensity_ = fmaxf(0.0f, fminf(1.0f, diffuse));
}

- (void)setDirectionalLight:(const alloy3d::DirectionalLight3D &)light
{
  for (int i = 0; i < 3; ++i)
    if (!std::isfinite(light.direction[i]) || !std::isfinite(light.color[i]) ||
        light.color[i] < 0 || light.color[i] > 1)
      throw std::invalid_argument(
          "Alloy3D directional light requires finite direction and RGB in [0,1]");
  if (!std::isfinite(light.ambient) || !std::isfinite(light.diffuse) || light.ambient < 0 ||
      light.ambient > 1 || light.diffuse < 0 || light.diffuse > 1)
    throw std::invalid_argument("Alloy3D light intensities must be in [0,1]");
  auto direction = simd_make_double3(light.direction.x, light.direction.y, light.direction.z);
  if (simd_length_squared(direction) == 0)
    throw std::invalid_argument("Alloy3D light direction is zero");
  direction             = simd_normalize(direction);
  const auto normalized = simd_make_float3(direction.x, direction.y, direction.z);
  if (shadowSettings_.enabled)
    alloy3d::BuildDirectionalShadowCamera3D(shadowSettings_, normalized);
  lightDirection_   = normalized;
  lightColor_       = light.color;
  ambientIntensity_ = light.ambient;
  diffuseIntensity_ = light.diffuse;
}

- (void)setDirectionalShadow:(const alloy3d::DirectionalShadow3D &)settings
{
  alloy3d::BuildDirectionalShadowCamera3D(
      settings, lightDirection_); // validate before changing live settings
  shadowSettings_ = settings;
}

- (void)setFog:(const alloy3d::Fog3D &)fog
{
  for (int i = 0; i < 3; ++i)
    if (!std::isfinite(fog.color[i]) || fog.color[i] < 0 || fog.color[i] > 1)
      throw std::invalid_argument("Alloy3D fog RGB must be finite and in [0,1]");
  if (!std::isfinite(fog.start) || !std::isfinite(fog.end) || fog.start < 0 || fog.end <= fog.start)
    throw std::invalid_argument("Alloy3D fog requires finite 0 <= start < end");
  const float inverseRange = 1.0f / (fog.end - fog.start);
  if (!std::isfinite(inverseRange))
    throw std::invalid_argument("Alloy3D fog range is too small");
  fogSettings_     = fog;
  fogInverseRange_ = inverseRange;
}

- (void)setSceneColor:(id<MTLTexture>)color depth:(id<MTLTexture>)depth
{
  sceneColor_ = color;
  sceneDepth_ = depth;
}
- (void)configurePostProcess:(alloy3d::metal::PostProcess *)post
                      camera:(const alloy3d::CameraData &)camera
{
  post->setVolumeScene(camera,
                       lightDirection_,
                       lightColor_ * diffuseIntensity_,
                       lightViewProjection_,
                       simd_float4{shadowReady_ ? 1.f : 0.f, shadowSettings_.depthBias, 0, 0},
                       shadowReady_ ? shadowMaps_[pageIndex_] : shadowFallback_);
}
- (void)setModelScreenSpace:(const alloy3d::ModelScreenSpace3D &)s
{
  if (!std::isfinite(s.refraction) || s.refraction < 0 || s.refraction > 1 ||
      !std::isfinite(s.reflection) || s.reflection < 0 || s.reflection > 1 ||
      !std::isfinite(s.refractionPixels) || s.refractionPixels < 0 || s.refractionPixels > 128 ||
      !std::isfinite(s.maxDistance) || s.maxDistance <= 0 || s.maxDistance > 1000 ||
      !std::isfinite(s.thickness) || s.thickness <= 0 || s.thickness > 10)
    throw std::invalid_argument("Invalid screen-space surface settings");
  screenSpace_ = s;
}
- (void)setModelSoftParticles:(float)distance
{
  if (!std::isfinite(distance) || distance < 0 || distance > 100)
    throw std::invalid_argument("Soft particle distance must be in [0,100]");
  softDistance_ = distance;
}
- (void)setModelVisibility:(const alloy3d::ModelVisibility3D &)visibility
{
  modelVisibility_ = visibility;
}

- (void)setModelWind:(const alloy3d::ModelWind3D &)wind
{
  if (!std::isfinite(wind.strength) || wind.strength < 0 || wind.strength > 10 ||
      !std::isfinite(wind.time) || !simd_all(simd_abs(wind.direction) < INFINITY) ||
      !std::isfinite(wind.baseHeight) || !std::isfinite(wind.tipHeight) ||
      wind.tipHeight <= wind.baseHeight ||
      !std::isfinite(1.f / (wind.tipHeight - wind.baseHeight)) || !std::isfinite(wind.frequency) ||
      wind.frequency < 0 || wind.frequency > 100 || !std::isfinite(wind.time * wind.frequency))
    throw std::invalid_argument("Alloy3D wind requires finite parameters, strength in [0,10], "
                                "frequency in [0,100], tip above base");
  auto direction = simd_make_double2(wind.direction.x, wind.direction.y);
  if (simd_length_squared(direction) == 0)
    throw std::invalid_argument("Alloy3D wind direction is zero");
  direction            = simd_normalize(direction);
  modelWind_           = wind;
  modelWind_.direction = simd_make_float2(direction.x, direction.y);
}

- (void)setModelCoverage:(simd_float2)interval
{
  if (!simd_all(interval >= 0) || !simd_all(interval <= 1) || interval.x > interval.y)
    throw std::invalid_argument("Alloy3D coverage requires 0 <= start <= end <= 1");
  modelCoverage_ = interval;
}

- (void)setFrustumCulling:(bool)enabled
{
  frustumCulling_ = enabled;
}

- (void)setTransparentBatching:(bool)enabled
{
  transparentBatching_ = enabled;
}

- (void)setHeightFog:(const alloy3d::HeightFog3D &)fog
{
  if (!simd_all(fog.color >= 0) || !simd_all(fog.color <= 1) || !std::isfinite(fog.baseHeight) ||
      !std::isfinite(fog.density) || fog.density < 0 || fog.density > 1 ||
      !std::isfinite(fog.falloff) || fog.falloff < 0 || fog.falloff > 100 ||
      !std::isfinite(fog.maxOpacity) || fog.maxOpacity < 0 || fog.maxOpacity > 1)
    throw std::invalid_argument("Alloy3D height fog requires finite height, RGB/density/opacity in "
                                "[0,1], falloff in [0,100]");
  heightFogSettings_ = fog;
}

- (void)setHemisphereLight:(const alloy3d::HemisphereLight3D &)light
{
  for (int i = 0; i < 3; ++i)
    if (!std::isfinite(light.skyColor[i]) || light.skyColor[i] < 0 || light.skyColor[i] > 1 ||
        !std::isfinite(light.groundColor[i]) || light.groundColor[i] < 0 ||
        light.groundColor[i] > 1 || !std::isfinite(light.up[i]))
      throw std::invalid_argument("Alloy3D hemisphere requires finite up and RGB in [0,1]");
  if (!std::isfinite(light.intensity) || light.intensity < 0 || light.intensity > 1)
    throw std::invalid_argument("Alloy3D hemisphere intensity must be in [0,1]");
  auto up = simd_make_double3(light.up.x, light.up.y, light.up.z);
  if (simd_length_squared(up) == 0)
    throw std::invalid_argument("Alloy3D hemisphere up is zero");
  up                     = simd_normalize(up);
  hemisphereSettings_    = light;
  hemisphereSettings_.up = simd_make_float3(up.x, up.y, up.z);
}

- (void)prepareInstances:(simd_float4x4)view
{
  if (instancesPrepared_)
    return;
  auto instances = instanceBuffers_[pageIndex_].append(device_, 0, modelInstances_.size());
  for (NSUInteger i = 0; i < modelInstances_.size(); ++i)
  {
    const auto &source = modelInstances_[i];
    auto       &target = instances[i];
    target.modelView =
        simd_mul(view, BuildModelMatrix(source.position, source.rotation, source.scale));
    target.normalTransform = alloy3d::metal::NormalMatrix(target.modelView);
    target.color           = source.color;
    target.coverage        = source.coverage;
    target.windPhase       = WindPhase(source.position);
  }
  instanceUsed_      = modelInstances_.size();
  instancesPrepared_ = true;
}

- (NSUInteger)shadowDrawCallCount
{
  return shadowDrawCalls_;
}

- (void)encodeShadowMap:(id<MTLCommandBuffer>)commands camera:(alloy3d::CameraData *)camera
{
  shadowReady_     = false;
  shadowDrawCalls_ = 0;
  if (!shadowSettings_.enabled)
    return;
  auto &map = shadowMaps_[pageIndex_];
  if (!map || map.width != shadowSettings_.resolution)
  {
    auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                   width:shadowSettings_.resolution
                                                                  height:shadowSettings_.resolution
                                                               mipmapped:NO];
    desc.storageMode = MTLStorageModePrivate;
    desc.usage       = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    auto replacement = [device_ newTextureWithDescriptor:desc];
    if (!replacement)
      throw std::bad_alloc();
    [map release];
    map = replacement;
  }
  auto lightCamera = alloy3d::BuildDirectionalShadowCamera3D(shadowSettings_, lightDirection_);
  lightViewProjection_ =
      simd_mul(lightCamera.getProjectionMatrix(), lightCamera.getModelViewMatrix());
  const auto view = camera->getModelViewMatrix();
  [self prepareInstances:view];
  auto pass                        = [MTLRenderPassDescriptor renderPassDescriptor];
  pass.depthAttachment.texture     = map;
  pass.depthAttachment.loadAction  = MTLLoadActionClear;
  pass.depthAttachment.storeAction = MTLStoreActionStore;
  pass.depthAttachment.clearDepth  = 1;
  auto encoder                     = [commands renderCommandEncoderWithDescriptor:pass];
  if (!encoder)
    return;
  encoder.label = @"Alloy3D directional shadow";
  [encoder setDepthBias:0 slopeScale:shadowSettings_.slopeScale clamp:.01f];
  [encoder setDepthStencilState:modelDepth_[0]];
  [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
  [encoder setCullMode:MTLCullModeNone];
  Uniforms uniform{};
  if (nbPlanes_)
  {
    uniform.perspectiveTransform = lightViewProjection_;
    uniform.worldTransform       = matrix_identity_float4x4;
    [encoder setRenderPipelineState:shadowPipelines_[0]];
    [encoder setVertexBytes:&uniform length:sizeof(uniform) atIndex:1];
    [encoder setVertexBuffer:verticesPlane_[pageIndex_].buffer() offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:nbPlanes_];
    ++shadowDrawCalls_;
  }
  uniform.perspectiveTransform = simd_mul(lightViewProjection_, simd_inverse(view));
  for (const auto &draw : drawModelList_)
  {
    if (!draw.visibility.castShadow)
      continue;
    bool instanced = draw.instanceCount != 0;
    if (!instanced && draw.color.w < 1)
      continue;
    uniform.worldTransform =
        instanced ? view
                  : simd_mul(view, BuildModelMatrix(draw.position, draw.rotation, draw.scale));
    uniform.modelColor = instanced ? simd_make_float4(1, 1, 1, 1) : draw.color;
    [encoder setRenderPipelineState:shadowPipelines_[instanced ? 2 : 1]];
    [encoder setVertexBytes:&uniform length:sizeof(uniform) atIndex:1];
    if (instanced)
      [encoder setVertexBuffer:instanceBuffers_[pageIndex_].buffer()
                        offset:draw.instanceOffset * sizeof(ModelInstanceUniforms)
                       atIndex:BufferIndexInstances];
    for (ModelPart *part in draw.model.parts)
    {
      if (part.alphaMode == 2)
        continue;
      [encoder setFragmentSamplerState:[self modelSampler:draw.maxAnisotropy] atIndex:0];
      MaterialUniforms material{
          {float(part.alphaMode), part.alphaCutoff, float(part.doubleSided), float(part.unlit)},
          {},
          simd_make_float4(draw.textureTransform.scale, draw.textureTransform.offset)};
      material.coverage = draw.coverage;
      SetWindUniforms(material, draw);
      [encoder setVertexBytes:&material length:sizeof(material) atIndex:BufferIndexMaterial];
      [encoder setFragmentBytes:&material length:sizeof(material) atIndex:BufferIndexMaterial];
      [encoder setVertexBuffer:[part vertexBufferForPage:pageIndex_] offset:0 atIndex:0];
      [encoder setVertexBuffer:[part jointMatrixBufferForPage:pageIndex_]
                        offset:0
                       atIndex:BufferIndexJointMatrices];
      [encoder setFragmentTexture:part.texture ? part.texture : whiteTexture_
                          atIndex:TextureIndexColor];
      [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                          indexCount:part.indexCount
                           indexType:MTLIndexTypeUInt32
                         indexBuffer:part.indexBuffer
                   indexBufferOffset:0
                       instanceCount:instanced ? draw.instanceCount : 1];
      ++shadowDrawCalls_;
    }
  }
  [encoder endEncoding];
  shadowReady_ = true;
}

//
- (void)drawModel:(nonnull MetalModel *)model
         position:(simd_float3)position
         rotation:(simd_float3)rotation
            scale:(simd_float3)scale
            color:(simd_float4)color
{
  if (model == nil || !model.loaded)
  {
    return;
  }

  SimpleGuard guard(modelLock_);
  drawModelList_.emplace_back(model, position, rotation, scale, color);
  drawModelList_.back().shader           = modelShader_;
  drawModelList_.back().parameters       = shaderParameters_;
  drawModelList_.back().highlight        = modelHighlight_;
  drawModelList_.back().textureTransform = modelTextureTransform_;
  drawModelList_.back().maxAnisotropy    = modelTextureSampling_.maxAnisotropy;
  drawModelList_.back().alphaToCoverage  = modelTextureSampling_.alphaToCoverage;
  drawModelList_.back().normalStrength   = modelNormalMapping_.strength;
  drawModelList_.back().materialDetail   = modelMaterialDetail_.enabled;
  drawModelList_.back().transmission     = modelTransmission_;
  drawModelList_.back().wind             = modelWind_;
  drawModelList_.back().visibility       = modelVisibility_;
  drawModelList_.back().softDistance     = softDistance_;
  drawModelList_.back().screenSpace      = screenSpace_;
  drawModelList_.back().coverage         = modelCoverage_;
}

- (void)drawModelInstances:(MetalModel *)model
                 instances:(std::span<const alloy3d::ModelInstance>)instances
{
  if (model == nil || !model.loaded || instances.empty())
    return;
  for (const auto &i : instances)
    if (!simd_all(i.coverage >= 0) || !simd_all(i.coverage <= 1) || i.coverage.x > i.coverage.y)
      throw std::invalid_argument("Alloy3D instance coverage requires 0 <= start <= end <= 1");
  const NSUInteger limit = device_.maxBufferLength / sizeof(ModelInstanceUniforms);
  if (instances.size() > limit || modelInstances_.size() > limit - instances.size())
    throw std::length_error("Alloy3D instances exceed device capacity");

  // Blended parts must be sorted together with other models/parts. Only batches
  // with depth-writing parts and fully opaque placement colors can remain instanced.
  bool batch = std::all_of(
      instances.begin(), instances.end(), [](const auto &i) { return i.color.w >= 1.0f; });
  for (ModelPart *part in model.parts)
    batch &= part.alphaMode != 2;
  SimpleGuard guard(modelLock_);
  if (!batch)
  {
    drawModelList_.reserve(drawModelList_.size() + instances.size());
    for (const auto &i : instances)
    {
      drawModelList_.emplace_back(model, i.position, i.rotation, i.scale, i.color);
      drawModelList_.back().shader           = modelShader_;
      drawModelList_.back().parameters       = shaderParameters_;
      drawModelList_.back().highlight        = modelHighlight_;
      drawModelList_.back().textureTransform = modelTextureTransform_;
      drawModelList_.back().maxAnisotropy    = modelTextureSampling_.maxAnisotropy;
      drawModelList_.back().alphaToCoverage  = modelTextureSampling_.alphaToCoverage;
      drawModelList_.back().normalStrength   = modelNormalMapping_.strength;
      drawModelList_.back().materialDetail   = modelMaterialDetail_.enabled;
      drawModelList_.back().transmission     = modelTransmission_;
      drawModelList_.back().wind             = modelWind_;
      drawModelList_.back().visibility       = modelVisibility_;
      drawModelList_.back().softDistance     = softDistance_;
      drawModelList_.back().screenSpace      = screenSpace_;
      drawModelList_.back().coverage         = i.coverage;
    }
    return;
  }
  const auto offset = modelInstances_.size();
  modelInstances_.insert(modelInstances_.end(), instances.begin(), instances.end());
  try
  {
    drawModelList_.emplace_back(model, offset, instances.size());
    drawModelList_.back().shader           = modelShader_;
    drawModelList_.back().parameters       = shaderParameters_;
    drawModelList_.back().highlight        = modelHighlight_;
    drawModelList_.back().textureTransform = modelTextureTransform_;
    drawModelList_.back().maxAnisotropy    = modelTextureSampling_.maxAnisotropy;
    drawModelList_.back().alphaToCoverage  = modelTextureSampling_.alphaToCoverage;
    drawModelList_.back().normalStrength   = modelNormalMapping_.strength;
    drawModelList_.back().materialDetail   = modelMaterialDetail_.enabled;
    drawModelList_.back().transmission     = modelTransmission_;
    drawModelList_.back().wind             = modelWind_;
    drawModelList_.back().visibility       = modelVisibility_;
    drawModelList_.back().softDistance     = softDistance_;
    drawModelList_.back().screenSpace      = screenSpace_;
  }
  catch (...)
  {
    modelInstances_.resize(offset);
    throw;
  }
}

- (NSUInteger)modelDrawCallCount
{
  return modelDrawCalls_;
}

//
- (void)render:(nullable id<MTLRenderCommandEncoder>)renderEncoder
        camera:(nonnull alloy3d::CameraData *)camera;
{
  [self render:renderEncoder camera:camera phase:ScenePhase::All];
}
- (void)render:(nullable id<MTLRenderCommandEncoder>)renderEncoder
        camera:(nonnull alloy3d::CameraData *)camera
         phase:(ScenePhase)phase
{
  [renderEncoder pushDebugGroup:@"Draw3D"];
  if (phase != ScenePhase::Transparent)
    modelDrawCalls_ = 0;

  if (nbPrimitives_ > 0 || nbPlanes_ > 0 || !drawModelList_.empty() || !drawTextList_.empty())
  {
    auto uniformBuff = uniformBuffer_[pageIndex_][phase == ScenePhase::Transparent];
    auto uniform     = (Uniforms *)uniformBuff.contents;

    auto mdlview                  = camera->getModelViewMatrix();
    uniform->perspectiveTransform = camera->getProjectionMatrix();
    uniform->worldTransform       = mdlview;
    uniform->worldNormalTransform = alloy3d::metal::NormalMatrix(mdlview);
    // Public light direction is in world coordinates; normals are in view coordinates.
    auto viewLight = simd_mul(mdlview, simd_make_float4(lightDirection_, 0.0f)).xyz;
    uniform->lightDirectionAndAmbient = simd_make_float4(viewLight, ambientIntensity_);
    uniform->lightColorAndDiffuse =
        simd_make_float4(lightColor_.x, lightColor_.y, lightColor_.z, diffuseIntensity_);
    uniform->modelColor      = simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f);
    uniform->sceneParameters = {
        sceneDepth_ && phase == ScenePhase::Transparent ? 1.f : 0.f,
        sceneDepth_ ? 1.f / sceneDepth_.width : 0.f,
        sceneDepth_ ? 1.f / sceneDepth_.height : 0.f,
        camera->getProjectionMode() == alloy3d::ProjectionMode::Identity ? 1.f : -1.f};
    [renderEncoder setFragmentTexture:sceneColor_ ? sceneColor_ : whiteTexture_ atIndex:5];
    [renderEncoder setFragmentTexture:sceneDepth_ ? sceneDepth_ : whiteTexture_ atIndex:6];
    uniform->shadowTransform  = shadowReady_ ? simd_mul(lightViewProjection_, simd_inverse(mdlview))
                                             : matrix_identity_float4x4;
    uniform->shadowParameters = simd_make_float4(shadowReady_ ? 1 : 0,
                                                 shadowSettings_.depthBias,
                                                 shadowSettings_.filterRadius,
                                                 1.f / shadowSettings_.resolution);
    uniform->fogColorAndEnabled = simd_make_float4(fogSettings_.color, float(fogSettings_.enabled));
    uniform->fogParameters      = simd_make_float4(fogSettings_.start, fogInverseRange_, 0, 0);
    uniform->heightFogColorDensity = simd_make_float4(
        heightFogSettings_.color, heightFogSettings_.enabled ? heightFogSettings_.density : 0.f);
    uniform->heightFogParameters = {
        heightFogSettings_.baseHeight,
        heightFogSettings_.falloff,
        heightFogSettings_.maxOpacity,
        camera->getProjectionMode() == alloy3d::ProjectionMode::Perspective ? 1.f : 0.f};
    uniform->heightFogWorldUp = {0, 1, 0, 0};
    if (uniform->heightFogColorDensity.w > 0)
    {
      auto inverseView          = simd_inverse(mdlview);
      uniform->heightFogWorldUp = {inverseView.columns[0].y,
                                   inverseView.columns[1].y,
                                   inverseView.columns[2].y,
                                   inverseView.columns[3].y};
    }
    uniform->hemisphereSky =
        simd_make_float4(hemisphereSettings_.skyColor * hemisphereSettings_.intensity, 0);
    uniform->hemisphereGround =
        simd_make_float4(hemisphereSettings_.groundColor * hemisphereSettings_.intensity, 0);
    auto viewUp = simd_mul(mdlview, simd_make_float4(hemisphereSettings_.up, 0)).xyz;
    uniform->hemisphereUpAndEnabled = simd_make_float4(viewUp, float(hemisphereSettings_.enabled));
    [renderEncoder setFragmentTexture:shadowReady_ ? shadowMaps_[pageIndex_] : shadowFallback_
                              atIndex:TextureIndexShadow];
    [renderEncoder setDepthStencilState:modelDepth_[0]];
    [renderEncoder setCullMode:MTLCullModeNone];
    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    // primitive draw
    if (nbPrimitives_ > 0 || nbPlanes_ > 0)
    {
      [renderEncoder setRenderPipelineState:pipelineState_];
      [renderEncoder setVertexBuffer:uniformBuff offset:0 atIndex:1];
      [renderEncoder setFragmentBuffer:uniformBuff offset:0 atIndex:1];

      if (nbPrimitives_ > 0)
      {
        auto vtx = vertices_[pageIndex_].buffer();

        [renderEncoder setVertexBuffer:vtx offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:nbPrimitives_];
      }
      if (nbPlanes_ > 0)
      {
        auto vtx = verticesPlane_[pageIndex_].buffer();

        [renderEncoder setVertexBuffer:vtx offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:nbPlanes_];
      }
    }

    nbPrimitives_ = 0;
    nbPlanes_     = 0;

    if (!drawModelList_.empty())
    {
      [renderEncoder setCullMode:MTLCullModeNone];
      [self prepareInstances:mdlview];

      auto drawPart = [&](const DrawModel3D &dmodel, ModelPart *part, bool blend)
      {
        [renderEncoder setFragmentSamplerState:[self modelSampler:dmodel.maxAnisotropy] atIndex:0];
        const bool instanced = dmodel.instanceCount != 0;
        const bool coverage =
            part.alphaMode == 1 && dmodel.alphaToCoverage && sampleCount_ > 1 && !blend;
        const int mode     = coverage ? 2 : int(blend);
        auto      pipeline = dmodel.shader ? dmodel.shader->pipelines[coverage ? (instanced ? 5 : 4)
                                                                      : instanced ? 2 + int(blend)
                                                                                  : int(blend)]
                                           : (instanced ? pipelineStateModelInstances_[mode]
                                                        : pipelineStateModel_[mode]);
        [renderEncoder setRenderPipelineState:pipeline];
        if (dmodel.shader)
          [renderEncoder setFragmentBytes:&dmodel.parameters
                                   length:sizeof(dmodel.parameters)
                                  atIndex:6];
        [renderEncoder setDepthStencilState:modelDepth_[blend]];
        MaterialUniforms material{
            {float(part.alphaMode), part.alphaCutoff, float(part.doubleSided), float(part.unlit)},
            {dmodel.highlight.strength,
             dmodel.highlight.shininess,
             float(camera->getProjectionMode() == alloy3d::ProjectionMode::Perspective),
             0},
            simd_make_float4(dmodel.textureTransform.scale, dmodel.textureTransform.offset)};
        material.normalMapping = {part.normalTexture && dmodel.normalStrength > 0 ? 1.f : 0.f,
                                  part.normalScale * dmodel.normalStrength,
                                  0,
                                  0};
        material.surfaceDetail = {
            dmodel.materialDetail ? 1.f : 0.f,
            part.roughness,
            part.occlusionStrength,
            float((part.roughnessTexture ? 1 : 0) | (part.occlusionTexture ? 2 : 0))};
        material.transmission =
            simd_make_float4(dmodel.transmission.color, dmodel.transmission.strength);
        material.softDistance    = blend ? dmodel.softDistance : 0;
        material.screenSurface   = {blend ? dmodel.screenSpace.refraction : 0.f,
                                    dmodel.screenSpace.refractionPixels,
                                    blend ? dmodel.screenSpace.reflection : 0.f,
                                    dmodel.screenSpace.maxDistance};
        material.screenThickness = dmodel.screenSpace.thickness;
        material.coverage        = dmodel.coverage;
        SetWindUniforms(material, dmodel);
        [renderEncoder setVertexBytes:&material
                               length:sizeof(material)
                              atIndex:BufferIndexMaterial];
        [renderEncoder setFragmentBytes:&material
                                 length:sizeof(material)
                                atIndex:BufferIndexMaterial];
        if (instanced)
        {
          [renderEncoder setVertexBuffer:uniformBuff offset:0 atIndex:1];
          [renderEncoder setFragmentBuffer:uniformBuff offset:0 atIndex:1];
          [renderEncoder setVertexBuffer:instanceBuffers_[pageIndex_].buffer()
                                  offset:dmodel.instanceOffset * sizeof(ModelInstanceUniforms)
                                 atIndex:BufferIndexInstances];
        }
        else
        {
          Uniforms modelUniform = *uniform;
          modelUniform.worldTransform =
              simd_mul(mdlview, BuildModelMatrix(dmodel.position, dmodel.rotation, dmodel.scale));
          modelUniform.worldNormalTransform =
              alloy3d::metal::NormalMatrix(modelUniform.worldTransform);
          modelUniform.modelColor = dmodel.color;
          [renderEncoder setVertexBytes:&modelUniform length:sizeof(modelUniform) atIndex:1];
          [renderEncoder setFragmentBytes:&modelUniform length:sizeof(modelUniform) atIndex:1];
        }
        [renderEncoder setVertexBuffer:[part vertexBufferForPage:pageIndex_] offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:[part jointMatrixBufferForPage:pageIndex_]
                                offset:0
                               atIndex:BufferIndexJointMatrices];
        [renderEncoder setFragmentTexture:part.texture != nil ? part.texture : whiteTexture_
                                  atIndex:TextureIndexColor];
        [renderEncoder setFragmentTexture:part.normalTexture ? part.normalTexture : whiteTexture_
                                  atIndex:2];
        [renderEncoder
            setFragmentTexture:part.roughnessTexture ? part.roughnessTexture : whiteTexture_
                       atIndex:3];
        [renderEncoder
            setFragmentTexture:part.occlusionTexture ? part.occlusionTexture : whiteTexture_
                       atIndex:4];
        [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                  indexCount:part.indexCount
                                   indexType:MTLIndexTypeUInt32
                                 indexBuffer:part.indexBuffer
                           indexBufferOffset:0
                               instanceCount:instanced ? dmodel.instanceCount : 1];
        ++modelDrawCalls_;
      };
      size_t                   usedInstances = instanceUsed_;
      const alloy3d::Frustum3D frustum(*camera);
      std::vector<size_t>      visible;
      transparentParts_.clear();
      for (const auto &dmodel : drawModelList_)
      {
        if (!dmodel.visibility.visible)
          continue;
        for (ModelPart *part in dmodel.model.parts)
        {
          bool blend = part.alphaMode == 2 || (dmodel.instanceCount == 0 && dmodel.color.w < 1);
          if ((phase == ScenePhase::Opaque && blend) ||
              (phase == ScenePhase::Transparent && !blend))
            continue;
          if (frustumCulling_)
          {
            const auto bounds = WindBounds(part.renderBounds, dmodel.wind);
            if (dmodel.instanceCount)
            {
              visible.clear();
              for (size_t i = 0; i < dmodel.instanceCount; ++i)
              {
                const auto &source = modelInstances_[dmodel.instanceOffset + i];
                if (frustum.intersects(
                        bounds, BuildModelMatrix(source.position, source.rotation, source.scale)))
                  visible.push_back(dmodel.instanceOffset + i);
              }
              if (visible.empty())
                continue;
              if (visible.size() != dmodel.instanceCount)
              {
                SimpleGuard guard(modelLock_);
                auto        target =
                    instanceBuffers_[pageIndex_].append(device_, usedInstances, visible.size());
                auto original = static_cast<const ModelInstanceUniforms *>(
                    instanceBuffers_[pageIndex_].buffer().contents);
                for (size_t i = 0; i < visible.size(); ++i)
                  target[i] = original[visible[i]];
                DrawModel3D culled(dmodel, usedInstances, visible.size());
                usedInstances += visible.size();
                drawPart(culled, part, false);
                continue;
              }
            }
            else if (!frustum.intersects(
                         bounds, BuildModelMatrix(dmodel.position, dmodel.rotation, dmodel.scale)))
              continue;
          }
          if (!blend)
            drawPart(dmodel, part, false);
          else
          {
            auto modelView =
                simd_mul(mdlview, BuildModelMatrix(dmodel.position, dmodel.rotation, dmodel.scale));
            auto  clip  = simd_mul(uniform->perspectiveTransform,
                                   simd_mul(modelView, simd_make_float4(part.sortCenter, 1)));
            float depth = clip.w != 0 ? clip.z / clip.w : 0;
            if (!std::isfinite(depth))
              depth = 0;
            transparentParts_.push_back({&dmodel, part, depth, transparentParts_.size()});
          }
        }
      }
      // Deterministic ties retain submission order without stable_sort's temporary allocation.
      std::sort(transparentParts_.begin(),
                transparentParts_.end(),
                [](const auto &a, const auto &b)
                { return a.depth == b.depth ? a.order < b.order : a.depth > b.depth; });
      instanceUsed_     = usedInstances;
      const auto offset = usedInstances;
      if (transparentBatching_ && !transparentParts_.empty())
      {
        SimpleGuard guard(modelLock_);
        auto        instances =
            instanceBuffers_[pageIndex_].append(device_, offset, transparentParts_.size());
        for (size_t i = 0; i < transparentParts_.size(); ++i)
        {
          const auto &source = *transparentParts_[i].draw;
          instances[i].modelView =
              simd_mul(mdlview, BuildModelMatrix(source.position, source.rotation, source.scale));
          instances[i].normalTransform = alloy3d::metal::NormalMatrix(instances[i].modelView);
          instances[i].color           = source.color;
          instances[i].coverage        = source.coverage;
          instances[i].windPhase       = WindPhase(source.position);
        }
      }
      for (size_t first = 0; first < transparentParts_.size();)
      {
        const auto &part = transparentParts_[first];
        size_t      end  = first + 1;
        if (transparentBatching_)
          while (end < transparentParts_.size() && transparentParts_[end].part == part.part &&
                 part.draw->sameStyle(*transparentParts_[end].draw))
            ++end;
        if (end - first > 1)
        {
          DrawModel3D batch(*part.draw, offset + first, end - first);
          drawPart(batch, part.part, true);
        }
        else
          drawPart(*part.draw, part.part, true);
        first = end;
      }
      transparentParts_.clear();
      if (phase != ScenePhase::Opaque)
      {
        drawModelList_.clear();
        modelInstances_.clear();
      }
    }

    [renderEncoder setDepthStencilState:modelDepth_[0]];
    if (phase != ScenePhase::Opaque && !drawTextList_.empty())
    {
      if (drawTextList_.size() > device_.maxBufferLength / sizeof(VertexData3D) / 4)
        throw std::length_error("Alloy3D 3D text exceeds device capacity");
      textVertices_[pageIndex_].append(device_, 0, drawTextList_.size() * 4);
      auto               textVtx  = textVertices_[pageIndex_].buffer();
      __block NSUInteger vtxCount = 0;
      for (auto dtext : drawTextList_)
      {
        auto *vtx3d = (VertexData3D *)textVtx.contents + vtxCount;
        auto  col16 = vcvt_f16_f32(dtext->color);

        vtx3d[0].position = dtext->pos[0];
        vtx3d[0].normal   = simd_make_float3(0.0f, 0.0f, 0.0f);
        vtx3d[0].texcoord = simd_make_float2(1.0f, 1.0f);
        vtx3d[0].color    = col16;
        vtx3d[1].position = dtext->pos[1];
        vtx3d[1].normal   = simd_make_float3(0.0f, 0.0f, 0.0f);
        vtx3d[1].texcoord = simd_make_float2(0.0f, 1.0f);
        vtx3d[1].color    = col16;
        vtx3d[2].position = dtext->pos[2];
        vtx3d[2].normal   = simd_make_float3(0.0f, 0.0f, 0.0f);
        vtx3d[2].texcoord = simd_make_float2(1.0f, 0.0f);
        vtx3d[2].color    = col16;
        vtx3d[3].position = dtext->pos[3];
        vtx3d[3].normal   = simd_make_float3(0.0f, 0.0f, 0.0f);
        vtx3d[3].texcoord = simd_make_float2(0.0f, 0.0f);
        vtx3d[3].color    = col16;
        vtxCount += 4;
      }

      [renderEncoder setCullMode:MTLCullModeNone];
      [renderEncoder setRenderPipelineState:pipelineStateText_];
      [renderEncoder setVertexBuffer:textVtx offset:0 atIndex:0];
      [renderEncoder setVertexBuffer:uniformBuff offset:0 atIndex:1];
      [renderEncoder setFragmentBuffer:uniformBuff offset:0 atIndex:1];

      vtxCount = 0;
      for (auto dtext : drawTextList_)
      {
        [renderEncoder setFragmentTexture:dtext->texture.object atIndex:TextureIndexColor];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:vtxCount
                          vertexCount:4];
        vtxCount += 4;
      }
      drawTextList_.clear();
    }
  }

  [renderEncoder popDebugGroup];
  if (phase == ScenePhase::Opaque)
    return;
  sceneColor_ = sceneDepth_ = nil;

  shadowReady_       = false;
  instancesPrepared_ = false;
  pageIndex_         = (pageIndex_ + 1) % 3;
}

// No GPU submission: keep the current page available for the next update.
- (void)discardFrame
{
  // A depth prepass is GPU work even if the color encoder could not be created.
  if (shadowReady_)
    pageIndex_ = (pageIndex_ + 1) % 3;
  shadowReady_       = false;
  instancesPrepared_ = false;
  nbPrimitives_      = 0;
  nbPlanes_          = 0;
  drawTextList_.clear();
  drawModelList_.clear();
  modelInstances_.clear();
}

// Called after the host acquires a free frame slot, before adding any draws.
- (void)beginFrame
{
  sceneColor_ = sceneDepth_ = nil;
  shadowDrawCalls_          = 0;
  if (!shadowSettings_.enabled)
  {
    [shadowMaps_[pageIndex_] release];
    shadowMaps_[pageIndex_] = nil;
  }
  if (releasePending_[pageIndex_] && nbPrimitives_ == 0 && nbPlanes_ == 0)
  {
    vertices_[pageIndex_].releaseUnused();
    verticesPlane_[pageIndex_].releaseUnused();
    textVertices_[pageIndex_].releaseUnused();
    instanceBuffers_[pageIndex_].releaseUnused();
    releasePending_[pageIndex_] = false;
  }
}

- (void)setTextBitmapLimit:(NSUInteger)bitmapBytes textureLimit:(NSUInteger)textureBytes
{
  [fontRender_ setCacheLimit:bitmapBytes];
  [textTextureCache_ setLimit:textureBytes];
}

- (void)releaseUnusedMemory
{
  if (transparentParts_.empty())
    std::vector<TransparentPart>{}.swap(transparentParts_);
  [fontRender_ clearRenderCache];
  [textTextureCache_ removeAllObjects];
  for (auto &pending : releasePending_)
    pending = true;
}

- (alloy3d::RenderMemoryStats)memoryStats
{
  alloy3d::RenderMemoryStats stats;
  for (NSUInteger page = 0; page < 3; ++page)
  {
    stats.vertexBufferBytes +=
        vertices_[page].bytes() + verticesPlane_[page].bytes() + textVertices_[page].bytes();
    stats.instanceBufferBytes += instanceBuffers_[page].bytes();
    stats.releasePending |= releasePending_[page];
    if (shadowMaps_[page])
    {
      stats.shadowMapBytes += shadowMaps_[page].width * shadowMaps_[page].height * sizeof(float);
      stats.releasePending |=
          !shadowSettings_.enabled || shadowMaps_[page].width != shadowSettings_.resolution;
    }
  }
  stats.shadowMapBytes += shadowFallback_ ? sizeof(float) : 0;
  stats.textBitmapCacheBytes  = [fontRender_ cacheBytes];
  stats.textTextureCacheBytes = [textTextureCache_ bytes];
  stats.textCacheEntries      = [fontRender_ cacheCount] + [textTextureCache_ count];
  return stats;
}

@end
