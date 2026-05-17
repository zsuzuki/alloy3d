//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "draw3d.h"
#import "camera.h"
#include "dsemaphore.h"
#import "font_render.h"
#include "shader_def.h"
#import "texture.h"
#import <Metal/Metal.h>
#include <arm_neon.h>
#include <algorithm>
#include <cmath>
#include <list>
#include <memory>
#include <simd/simd.h>

namespace
{
constexpr float Pi = 3.14159265358979323846f;
const NSUInteger MaxTextTextureCacheEntries = 512;

struct DrawText3D
{
  Texture     *texture;
  simd_float3 pos[4];
  simd_float4 color;

  ~DrawText3D() { [texture release]; }
};
using DrawText3DPtr = std::shared_ptr<DrawText3D>;

struct DrawModel3D
{
  Model       *model;
  simd_float3 position;
  simd_float3 rotation;
  simd_float3 scale;
  simd_float4 color;

  ~DrawModel3D() { [model release]; }
};
using DrawModel3DPtr = std::shared_ptr<DrawModel3D>;

int ClampSegments(int value, int minValue)
{
  return value < minValue ? minValue : value;
}

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

  id<MTLRenderPipelineState> pipelineState_;
  id<MTLRenderPipelineState> pipelineStateText_;
  id<MTLRenderPipelineState> pipelineStateModel_;
  id<MTLBuffer>              uniformBuffer_[3];
  id<MTLBuffer>              vertices_[3];
  id<MTLBuffer>              verticesPlane_[3];
  id<MTLBuffer>              textVertices_[3];
  id<MTLTexture>             whiteTexture_;
  NSUInteger                 nbPrimitives_;
  NSUInteger                 nbPlanes_;
  simd_float3                lightDirection_;
  simd_float3                lightColor_;
  float                      ambientIntensity_;
  float                      diffuseIntensity_;
  FontRender                *fontRender_;
  NSMutableDictionary       *textTextureCache_;
  NSMutableArray            *textTextureCacheKeys_;
  std::list<DrawText3DPtr>   drawTextList_;
  std::list<DrawModel3DPtr>  drawModelList_;

  SimpleLock primLock_;
  SimpleLock planeLock_;
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

  vertexFunction   = [library newFunctionWithName:@"textVert3d"];
  fragmentFunction = [library newFunctionWithName:@"textFrag3d"];

  pipelineDesc.label            = @"PipelineText3D";
  pipelineDesc.vertexFunction   = vertexFunction;
  pipelineDesc.fragmentFunction = fragmentFunction;

  pipelineStateText_ = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

  vertexFunction   = [library newFunctionWithName:@"modelVert3d"];
  fragmentFunction = [library newFunctionWithName:@"modelFrag3d"];

  pipelineDesc.label            = @"PipelineModel3D";
  pipelineDesc.vertexFunction   = vertexFunction;
  pipelineDesc.fragmentFunction = fragmentFunction;

  pipelineStateModel_ = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

  [pipelineDesc release];
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
  [super init];

  device_           = view.device;
  colorFormat_      = view.colorPixelFormat;
  depthFormat_      = view.depthStencilPixelFormat;
  sampleCount_      = view.sampleCount;
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
    uniformBuffer_[i] = [device_ newBufferWithLength:sizeof(Uniforms)
                                             options:MTLResourceStorageModeShared];
    vertices_[i]      = [device_ newBufferWithLength:sizeof(VertexDataPrim3D) * 4 * 30000
                                             options:MTLResourceStorageModeShared];
    verticesPlane_[i] = [device_ newBufferWithLength:sizeof(VertexDataPrim3D) * 3 * 100000
                                             options:MTLResourceStorageModeShared];
    textVertices_[i]  = [device_ newBufferWithLength:sizeof(VertexData3D) * 4 * 5000
                                             options:MTLResourceStorageModeShared];
  }
  fontRender_           = [[FontRender alloc] init];
  textTextureCache_     = [[NSMutableDictionary alloc] init];
  textTextureCacheKeys_ = [[NSMutableArray alloc] init];
  [fontRender_ SetSize:64.0f];

  return self;
}

//
- (void)dealloc
{
  for (int i = 0; i < 3; i++)
  {
    [uniformBuffer_[i] release];
    [vertices_[i] release];
    [verticesPlane_[i] release];
    [textVertices_[i] release];
  }
  [fontRender_ release];
  [textTextureCache_ release];
  [textTextureCacheKeys_ release];
  [pipelineState_ release];
  [pipelineStateText_ release];
  [pipelineStateModel_ release];
  [whiteTexture_ release];
  [super dealloc];
}

//
- (void)drawLine:(simd_float3)from to:(simd_float3)to color:(simd_float4)color
{
  primLock_.lock();
  auto  vtx   = vertices_[pageIndex_];
  auto *vtx3d = (VertexDataPrim3D *)vtx.contents + nbPrimitives_;

  nbPrimitives_ += 2;
  primLock_.unlock();

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
  planeLock_.lock();
  auto  vtx   = verticesPlane_[pageIndex_];
  auto *vtx3d = (VertexDataPrim3D *)vtx.contents + nbPlanes_;

  nbPlanes_ += 3;
  planeLock_.unlock();

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
        return simd_make_float3(sinPhi * std::cos(theta), std::cos(phi),
                                sinPhi * std::sin(theta));
      };

      auto n00 = makeNormal(phi0, theta0);
      auto n10 = makeNormal(phi1, theta0);
      auto n11 = makeNormal(phi1, theta1);
      auto n01 = makeNormal(phi0, theta1);
      auto p00 = center + n00 * radius;
      auto p10 = center + n10 * radius;
      auto p11 = center + n11 * radius;
      auto p01 = center + n01 * radius;

      [self drawTriangle:p00 normal:n00 p1:p10 normal:n10 p2:p11 normal:n11 color:color];
      [self drawTriangle:p00 normal:n00 p1:p11 normal:n11 p2:p01 normal:n01 color:color];
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
    [self drawTriangle:bottomCenter normal:bottomNormal p1:b1 normal:bottomNormal p2:b0
                normal:bottomNormal color:color];
    [self drawTriangle:topCenter normal:topNormal p1:t0 normal:topNormal p2:t1 normal:topNormal
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

  [self drawCone:center
       direction:axisY
          radius:radius
          height:height
           color:color
        segments:segments];
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

  auto axis         = simd_normalize(direction);
  auto bottomCenter = center - axis * (height * 0.5f);
  auto apex         = center + axis * (height * 0.5f);
  auto bottomNormal = -axis;
  simd_float3 basisX;
  simd_float3 basisZ;
  BuildBasis(axis, basisX, basisZ);

  for (int segment = 0; segment < segments; segment++)
  {
    float theta0 = 2.0f * Pi * (float)segment / (float)segments;
    float theta1 = 2.0f * Pi * (float)(segment + 1) / (float)segments;
    auto  d0     = basisX * std::cos(theta0) + basisZ * std::sin(theta0);
    auto  d1     = basisX * std::cos(theta1) + basisZ * std::sin(theta1);
    auto  b0     = bottomCenter + d0 * radius;
    auto  b1     = bottomCenter + d1 * radius;
    auto  n0     = simd_normalize(d0 * height + axis * radius);
    auto  n1     = simd_normalize(d1 * height + axis * radius);
    auto  apexNormal = simd_normalize(n0 + n1);

    [self drawTriangle:b0 normal:n0 p1:b1 normal:n1 p2:apex normal:apexNormal color:color];
    [self drawTriangle:bottomCenter normal:bottomNormal p1:b1 normal:bottomNormal p2:b0
                normal:bottomNormal color:color];
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
                 if ([textTextureCacheKeys_ count] >= MaxTextTextureCacheEntries)
                 {
                   NSString *oldCacheKey = [textTextureCacheKeys_ objectAtIndex:0];
                   [textTextureCache_ removeObjectForKey:oldCacheKey];
                   [textTextureCacheKeys_ removeObjectAtIndex:0];
                 }
                 [textTextureCache_ setObject:texture forKey:cacheKey];
                 [textTextureCacheKeys_ addObject:cacheKey];
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
  if (simd_length_squared(direction) > 0.000001f)
  {
    lightDirection_ = simd_normalize(direction);
  }
  ambientIntensity_ = fmaxf(0.0f, fminf(1.0f, ambient));
  diffuseIntensity_ = fmaxf(0.0f, fminf(1.0f, diffuse));
}

//
- (void)drawModel:(nonnull Model *)model
         position:(simd_float3)position
         rotation:(simd_float3)rotation
            scale:(simd_float3)scale
            color:(simd_float4)color
{
  if (model == nil || !model.loaded)
  {
    return;
  }

  auto dmodel      = std::make_shared<DrawModel3D>();
  dmodel->model    = [model retain];
  dmodel->position = position;
  dmodel->rotation = rotation;
  dmodel->scale    = scale;
  dmodel->color    = color;

  modelLock_.lock();
  drawModelList_.push_back(dmodel);
  modelLock_.unlock();
}

//
- (void)render:(nullable id<MTLRenderCommandEncoder>)renderEncoder
        camera:(nonnull CameraData *)camera;
{
  [renderEncoder pushDebugGroup:@"Draw3D"];

  if (nbPrimitives_ > 0 || nbPlanes_ > 0 || !drawModelList_.empty() || !drawTextList_.empty())
  {
    auto uniformBuff = uniformBuffer_[pageIndex_];
    auto uniform     = (Uniforms *)uniformBuff.contents;

    auto mdlview                  = camera->getModelViewMatrix();
    uniform->perspectiveTransform = camera->getProjectionMatrix();
    uniform->worldTransform       = mdlview;
    uniform->worldNormalTransform =
        simd_matrix(mdlview.columns[0].xyz, mdlview.columns[1].xyz, mdlview.columns[2].xyz);
    uniform->lightDirectionAndAmbient = simd_make_float4(
        lightDirection_.x, lightDirection_.y, lightDirection_.z, ambientIntensity_);
    uniform->lightColorAndDiffuse =
        simd_make_float4(lightColor_.x, lightColor_.y, lightColor_.z, diffuseIntensity_);
    uniform->modelColor = simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f);
    // primitive draw
    if (nbPrimitives_ > 0 || nbPlanes_ > 0)
    {
      [renderEncoder setRenderPipelineState:pipelineState_];
      [renderEncoder setVertexBuffer:uniformBuff offset:0 atIndex:1];
      [renderEncoder setFragmentBuffer:uniformBuff offset:0 atIndex:1];

      if (nbPrimitives_ > 0)
      {
        auto vtx = vertices_[pageIndex_];
        [vtx didModifyRange:NSMakeRange(0, nbPrimitives_ * sizeof(VertexDataPrim3D))];
        [renderEncoder setVertexBuffer:vtx offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:nbPrimitives_];
      }
      if (nbPlanes_ > 0)
      {
        auto vtx = verticesPlane_[pageIndex_];
        [vtx didModifyRange:NSMakeRange(0, nbPlanes_ * sizeof(VertexDataPrim3D))];
        [renderEncoder setVertexBuffer:vtx offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:nbPlanes_];
      }
    }

    nbPrimitives_ = 0;
    nbPlanes_     = 0;

    if (!drawModelList_.empty())
    {
      [renderEncoder setCullMode:MTLCullModeNone];
      [renderEncoder setRenderPipelineState:pipelineStateModel_];

      for (auto dmodel : drawModelList_)
      {
        auto modelMatrix = BuildModelMatrix(dmodel->position, dmodel->rotation, dmodel->scale);
        auto modelView   = simd_mul(mdlview, modelMatrix);

        Uniforms modelUniform{};
        modelUniform.perspectiveTransform = camera->getProjectionMatrix();
        modelUniform.worldTransform       = modelView;
        modelUniform.worldNormalTransform =
            simd_matrix(modelView.columns[0].xyz, modelView.columns[1].xyz, modelView.columns[2].xyz);
        modelUniform.lightDirectionAndAmbient = uniform->lightDirectionAndAmbient;
        modelUniform.lightColorAndDiffuse     = uniform->lightColorAndDiffuse;
        modelUniform.modelColor               = dmodel->color;

        [renderEncoder setVertexBytes:&modelUniform length:sizeof(modelUniform) atIndex:1];
        [renderEncoder setFragmentBytes:&modelUniform length:sizeof(modelUniform) atIndex:1];

        for (ModelPart *part in dmodel->model.parts)
        {
          [renderEncoder setVertexBuffer:[part vertexBufferForPage:pageIndex_] offset:0 atIndex:0];
          [renderEncoder setVertexBuffer:[part jointMatrixBufferForPage:pageIndex_]
                                  offset:0
                                 atIndex:BufferIndexJointMatrices];
          [renderEncoder setFragmentTexture:part.texture != nil ? part.texture : whiteTexture_
                                    atIndex:TextureIndexColor];
          [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                    indexCount:part.indexCount
                                     indexType:MTLIndexTypeUInt32
                                   indexBuffer:part.indexBuffer
                             indexBufferOffset:0];
        }
      }
      drawModelList_.clear();
    }

    if (!drawTextList_.empty())
    {
      auto               textVtx  = textVertices_[pageIndex_];
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
      [textVtx didModifyRange:NSMakeRange(0, vtxCount * sizeof(VertexData3D))];

      [renderEncoder setCullMode:MTLCullModeNone];
      [renderEncoder setRenderPipelineState:pipelineStateText_];
      [renderEncoder setVertexBuffer:textVtx offset:0 atIndex:0];
      [renderEncoder setVertexBuffer:uniformBuff offset:0 atIndex:1];

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

  pageIndex_ = (pageIndex_ + 1) % 3;
}

@end
