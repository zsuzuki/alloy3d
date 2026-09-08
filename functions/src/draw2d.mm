//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <alloy3d/metal/draw2d.h>
#include "dsemaphore.h"
#import <alloy3d/metal/memory_cache.h>
#include <alloy3d/metal/vertex_buffer.h>
#import <alloy3d/metal/font_render.h>
#include "shader_def.h"
#import <alloy3d/metal/sprite.h>
#import <alloy3d/metal/texture.h>
#import <Metal/Metal.h>
#include <arm_neon.h>
#include <algorithm>
#include <cmath>
#include <list>
#include <memory>
#include <simd/simd.h>
#include <vector>

namespace
{
const int        RoundRectCornerSegments    = 8;

// 文字列管理
struct DrawString
{
  Texture    *stringTex_;
  simd_float2 pos_[4];
  simd_float4 color_;
  BOOL        keep_;

  ~DrawString() { [stringTex_ release]; }
};
using DrawStringPtr = std::shared_ptr<DrawString>;

simd_float2 minPoint(simd_float2 a, simd_float2 b)
{
  return simd_make_float2(std::min(a.x, b.x), std::min(a.y, b.y));
}

simd_float2 maxPoint(simd_float2 a, simd_float2 b)
{
  return simd_make_float2(std::max(a.x, b.x), std::max(a.y, b.y));
}

std::vector<simd_float2> roundRectPoints(simd_float2 from, simd_float2 to, float radius)
{
  auto minPos = minPoint(from, to);
  auto maxPos = maxPoint(from, to);
  auto size   = maxPos - minPos;
  auto rad    = std::min(radius, std::min(size.x, size.y) * 0.5f);

  std::vector<simd_float2> points;
  if (size.x <= 0.0f || size.y <= 0.0f || rad <= 0.0f)
  {
    return points;
  }

  points.reserve((RoundRectCornerSegments + 1) * 4);

  const simd_float2 centers[] = {
      simd_make_float2(maxPos.x - rad, minPos.y + rad),
      simd_make_float2(maxPos.x - rad, maxPos.y - rad),
      simd_make_float2(minPos.x + rad, maxPos.y - rad),
      simd_make_float2(minPos.x + rad, minPos.y + rad),
  };

  const float starts[] = {
      -static_cast<float>(M_PI) * 0.5f,
      0.0f,
      static_cast<float>(M_PI) * 0.5f,
      static_cast<float>(M_PI),
  };

  const float step = (static_cast<float>(M_PI) * 0.5f) / RoundRectCornerSegments;
  for (int corner = 0; corner < 4; corner++)
  {
    for (int sidx = 0; sidx <= RoundRectCornerSegments; sidx++)
    {
      auto angle = starts[corner] + step * sidx;
      points.push_back(centers[corner] + simd_make_float2(std::cos(angle), std::sin(angle)) * rad);
    }
  }

  return points;
}

} // namespace

//
//
//
@interface Draw2D ()
{
}
@end

@implementation Draw2D
{
  id<MTLDevice>  device_;
  id<MTLBuffer>  uniformBuffer_[3];
  MTLPixelFormat colorFormat_;
  MTLPixelFormat depthFormat_;
  NSUInteger     sampleCount_;
  CGFloat        contentScale_;
  NSUInteger     pageIndex_;

  // text draw
  id<MTLDepthStencilState>   depthState_;
  id<MTLRenderPipelineState> pipelineStateText_;
  FontRender                *fontRender_;
  MemoryCache                *textTextureCache_;
  bool releasePending_[3];
  alloy3d::metal::VertexBuffer<VertexDataPrim2D> textVtx_[3];
  simd_float4                textColor_;
  BOOL                       requestClearText_;
  std::list<DrawStringPtr>   drawStringList;
  std::list<DrawStringPtr>   drawStringListBack;

  // primitive
  id<MTLRenderPipelineState> pipelineStatePrim_;
  alloy3d::metal::VertexBuffer<VertexDataPrim2D> vertices_[3];
  NSUInteger                 nbPrimitives_;
  alloy3d::metal::VertexBuffer<VertexDataPrim2D> fillVertices_[3];
  NSUInteger                 nbFillPrimitives_;

  //
  SimpleLock primLock_;
  SimpleLock fillLock_;

  // sprite
  NSMutableArray<MetalSprite *> *spriteList;
}

@synthesize screenSize;

- (CGFloat)P:(CGFloat)num
{
  return num * contentScale_;
}

- (void)drawLine:(simd_float2)from to:(simd_float2)to color:(simd_float4)color
{
  SimpleGuard guard(primLock_);
  auto *vtx2d = vertices_[pageIndex_].append(device_, nbPrimitives_, 2);
  nbPrimitives_ += 2;

  auto col16        = vcvt_f16_f32(color);
  vtx2d[0].position = from * contentScale_;
  vtx2d[0].color    = col16;
  vtx2d[1].position = to * contentScale_;
  vtx2d[1].color    = col16;
}

- (void)drawRect:(simd_float2)from to:(simd_float2)to color:(simd_float4)color
{
  SimpleGuard guard(primLock_);
  auto *vtx2d = vertices_[pageIndex_].append(device_, nbPrimitives_, 8);
  nbPrimitives_ += 8;

  from *= contentScale_;
  to *= contentScale_;

  auto col16        = vcvt_f16_f32(color);
  vtx2d[0].position = from;
  vtx2d[0].color    = col16;
  vtx2d[1].position = simd_make_float2(to.x, from.y);
  vtx2d[1].color    = col16;
  vtx2d[2].position = from;
  vtx2d[2].color    = col16;
  vtx2d[3].position = simd_make_float2(from.x, to.y);
  vtx2d[3].color    = col16;
  vtx2d[4].position = simd_make_float2(to.x, from.y);
  vtx2d[4].color    = col16;
  vtx2d[5].position = to;
  vtx2d[5].color    = col16;
  vtx2d[6].position = simd_make_float2(from.x, to.y);
  vtx2d[6].color    = col16;
  vtx2d[7].position = to;
  vtx2d[7].color    = col16;
}

- (void)drawRoundRect:(simd_float2)from
                   to:(simd_float2)to
               radius:(float)radius
                color:(simd_float4)color
{
  auto points = roundRectPoints(from, to, radius);
  if (points.empty())
  {
    [self drawRect:from to:to color:color];
    return;
  }

  SimpleGuard guard(primLock_);
  auto *vtx2d = vertices_[pageIndex_].append(device_, nbPrimitives_, points.size() * 2);
  nbPrimitives_ += points.size() * 2;

  auto col16 = vcvt_f16_f32(color);
  for (size_t idx = 0; idx < points.size(); idx++)
  {
    auto next = (idx + 1) % points.size();

    vtx2d[0].position = points[idx] * contentScale_;
    vtx2d[0].color    = col16;
    vtx2d[1].position = points[next] * contentScale_;
    vtx2d[1].color    = col16;
    vtx2d += 2;
  }
}

- (void)drawPolygon:(simd_float2)pos
             radius:(float)rad
             rotate:(float)rot
           numSides:(int)sides
              color:(simd_float4)color
{
  if (sides < 3)
  {
    return;
  }

  SimpleGuard guard(primLock_);
  auto *vtx2d = vertices_[pageIndex_].append(device_, nbPrimitives_, static_cast<NSUInteger>(sides) * 2);
  nbPrimitives_ += static_cast<NSUInteger>(sides) * 2;

  auto col16 = vcvt_f16_f32(color);

  float step = (M_PI * 2) / (float)sides;
  for (int sidx = 0; sidx < sides; sidx++)
  {
    auto rot1 = (float)sidx * step + rot;
    auto rot2 = (float)(sidx + 1) * step + rot;
    auto pos1 = simd_make_float2(std::sin(rot1), std::cos(rot1));
    auto pos2 = simd_make_float2(std::sin(rot2), std::cos(rot2));

    (*vtx2d).position = (pos1 * rad + pos) * contentScale_;
    (*vtx2d).color    = col16;
    vtx2d++;
    (*vtx2d).position = (pos2 * rad + pos) * contentScale_;
    (*vtx2d).color    = col16;
    vtx2d++;
  }
}

- (void)fillRect:(simd_float2)from to:(simd_float2)to color:(simd_float4)color
{
  SimpleGuard guard(fillLock_);
  auto *vtx2d = fillVertices_[pageIndex_].append(device_, nbFillPrimitives_, 6);
  nbFillPrimitives_ += 6;

  from *= contentScale_;
  to *= contentScale_;

  auto col16        = vcvt_f16_f32(color);
  vtx2d[0].position = from;
  vtx2d[0].color    = col16;
  vtx2d[1].position = simd_make_float2(to.x, from.y);
  vtx2d[1].color    = col16;
  vtx2d[2].position = simd_make_float2(from.x, to.y);
  vtx2d[2].color    = col16;
  vtx2d[3].position = simd_make_float2(to.x, from.y);
  vtx2d[3].color    = col16;
  vtx2d[4].position = simd_make_float2(from.x, to.y);
  vtx2d[4].color    = col16;
  vtx2d[5].position = to;
  vtx2d[5].color    = col16;
}

- (void)fillRoundRect:(simd_float2)from
                   to:(simd_float2)to
               radius:(float)radius
                color:(simd_float4)color
{
  auto points = roundRectPoints(from, to, radius);
  if (points.empty())
  {
    [self fillRect:from to:to color:color];
    return;
  }

  SimpleGuard guard(fillLock_);
  auto *vtx2d = fillVertices_[pageIndex_].append(device_, nbFillPrimitives_, points.size() * 3);
  nbFillPrimitives_ += points.size() * 3;

  auto minPos = minPoint(from, to);
  auto maxPos = maxPoint(from, to);
  auto center = (minPos + maxPos) * 0.5f;
  auto col16  = vcvt_f16_f32(color);
  for (size_t idx = 0; idx < points.size(); idx++)
  {
    auto next = (idx + 1) % points.size();

    vtx2d[0].position = center * contentScale_;
    vtx2d[0].color    = col16;
    vtx2d[1].position = points[idx] * contentScale_;
    vtx2d[1].color    = col16;
    vtx2d[2].position = points[next] * contentScale_;
    vtx2d[2].color    = col16;
    vtx2d += 3;
  }
}

- (void)fillPolygon:(simd_float2)pos
             radius:(float)rad
             rotate:(float)rot
           numSides:(int)sides
              color:(simd_float4)color
{
  if (sides < 3)
  {
    return;
  }

  SimpleGuard guard(fillLock_);
  auto *vtx2d = fillVertices_[pageIndex_].append(device_, nbFillPrimitives_, static_cast<NSUInteger>(sides) * 3);
  nbFillPrimitives_ += static_cast<NSUInteger>(sides) * 3;

  auto col16 = vcvt_f16_f32(color);

  float step = (M_PI * 2) / (float)sides;
  for (int sidx = 0; sidx < sides; sidx++)
  {
    auto rot1 = (float)sidx * step + rot;
    auto rot2 = (float)(sidx + 1) * step + rot;
    auto pos1 = simd_make_float2(std::sin(rot1), std::cos(rot1));
    auto pos2 = simd_make_float2(std::sin(rot2), std::cos(rot2));

    (*vtx2d).position = pos * contentScale_;
    (*vtx2d).color    = col16;
    vtx2d++;
    (*vtx2d).position = (pos1 * rad + pos) * contentScale_;
    (*vtx2d).color    = col16;
    vtx2d++;
    (*vtx2d).position = (pos2 * rad + pos) * contentScale_;
    (*vtx2d).color    = col16;
    vtx2d++;
  }
}

// テキスト描画カラー
- (void)setTextColorRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
  textColor_ = simd_make_float4(red, green, blue, alpha);
}

- (void)setTextFont:(nonnull NSString *)fontName
{
  [fontRender_ SetFont:[fontName UTF8String]];
}

- (void)setTextFontSize:(float)fontSize
{
  [fontRender_ SetSize:fontSize];
}

- (void)setTextFontColorRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
  [fontRender_ SetColor:red green:green blue:blue alpha:alpha];
}

// テキスト描画
- (void)print:(nonnull NSString *)message x:(CGFloat)x y:(CGFloat)y keep:(BOOL)keep
{
  NSString *cacheKey = [fontRender_ CacheKey:message];
  [fontRender_ Render:message
             callback:^(CGContextRef ctx, CGRect rect) {
               Texture *texture = [textTextureCache_ objectForKey:cacheKey];
               if (texture == nil)
               {
                 texture = [[Texture alloc] initWithMemory:ctx device:device_];
                 [textTextureCache_ setObject:texture forKey:cacheKey
                                         cost:texture.object.allocatedSize];
               }
               else
               {
                 [texture retain];
               }

               auto dstr        = std::make_shared<DrawString>();
               dstr->stringTex_ = texture;
               dstr->color_     = textColor_;
               dstr->keep_      = keep;
               const CGFloat x1 = [self P:x + rect.origin.x];
               const CGFloat y1 = [self P:y + rect.origin.y];
               const CGFloat x2 = x1 + [self P:rect.size.width];
               const CGFloat y2 = y1 + [self P:rect.size.height];
               dstr->pos_[0]    = simd_make_float2(x2, y1);
               dstr->pos_[1]    = simd_make_float2(x1, y1);
               dstr->pos_[2]    = simd_make_float2(x2, y2);
               dstr->pos_[3]    = simd_make_float2(x1, y2);
               drawStringList.push_back(dstr);
             }];
}

- (void)print:(nonnull NSString *)message x:(CGFloat)x y:(CGFloat)y
{
  [self print:message x:x y:y keep:NO];
}

// テキストクリア
- (void)clearText
{
  requestClearText_ = YES;
}

//
- (BOOL)initializePipeline:(id<MTLLibrary>)library
{
  NSError *error        = nil;
  auto     pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];

  auto vertexFunction   = [library newFunctionWithName:@"vert2d"];
  auto fragmentFunction = [library newFunctionWithName:@"frag2d"];

  // text
  pipelineDesc.label                        = @"PipelineText";
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

  pipelineStateText_ = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

  // primitive
  auto vertexPrimFunction   = [library newFunctionWithName:@"primVert2d"];
  auto fragmentPrimFunction = [library newFunctionWithName:@"primFrag2d"];

  pipelineDesc.label             = @"Pipeline2D";
  pipelineDesc.rasterSampleCount = sampleCount_;
  pipelineDesc.vertexFunction    = vertexPrimFunction;
  pipelineDesc.fragmentFunction  = fragmentPrimFunction;

  pipelineStatePrim_ = [device_ newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];

  [vertexFunction release];
  [fragmentFunction release];
  [vertexPrimFunction release];
  [fragmentPrimFunction release];
  [pipelineDesc release];
  return YES;
}

//
- (void)initializeDepthState
{
  auto depthStateDesc                 = [[MTLDepthStencilDescriptor alloc] init];
  depthStateDesc.depthCompareFunction = MTLCompareFunctionAlways;
  depthStateDesc.depthWriteEnabled    = NO;
  depthState_                         = [device_ newDepthStencilStateWithDescriptor:depthStateDesc];
  [depthStateDesc release];
}

// 初期化
- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
                                   shaderlib:(nonnull id<MTLLibrary>)library
{
  self = [super init];
  if (self != nil)
  {
    device_        = view.device;
    colorFormat_   = view.colorPixelFormat;
    depthFormat_   = view.depthStencilPixelFormat;
    sampleCount_   = view.sampleCount;
    contentScale_  = [[NSScreen mainScreen] backingScaleFactor];
    pageIndex_     = 0;
    nbPrimitives_  = 0;
    spriteList     = [[NSMutableArray alloc] init];
    if ([self initializePipeline:library] == NO)
    {
      NSLog(@"init failed pipeline");
    }
    [self initializeDepthState];

    for (int i = 0; i < 3; i++)
    {
      uniformBuffer_[i] = [device_ newBufferWithLength:sizeof(Uniforms2D)
                                             options:MTLResourceStorageModeShared];
    }
    requestClearText_ = NO;
    fontRender_            = [[FontRender alloc] init];
    textTextureCache_ = [[MemoryCache alloc] initWithLimit:alloy3d::TextCacheBudget{}.textureBytes / 2];

    [fontRender_ SetSize:24.0f];
    [self setTextColorRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
  }

  return self;
}

//
- (void)dealloc
{
  [spriteList release];
  for (int i = 0; i < 3; i++)
  {
    [uniformBuffer_[i] release];
  }
  [fontRender_ release];
  [textTextureCache_ release];
  [depthState_ release];
  [pipelineStateText_ release];
  [pipelineStatePrim_ release];
  [super dealloc];
}

//
- (void)setupDrawText
{
  const NSUInteger quads = [spriteList count] + drawStringList.size();
  if (quads > device_.maxBufferLength / sizeof(VertexDataPrim2D) / 4)
    throw std::length_error("Alloy3D 2D text exceeds device capacity");
  textVtx_[pageIndex_].append(device_, 0, quads * 4);
  auto textVtx = textVtx_[pageIndex_].buffer();
  __block NSUInteger vtxCount = 0;
  [spriteList
      enumerateObjectsUsingBlock:^(MetalSprite *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        auto  poslist = [obj update];
        auto *sprvtx  = (VertexDataPrim2D *)textVtx.contents + vtxCount;
        for (int i = 0; i < 4; i++)
        {
          sprvtx[i].position = poslist[i];
          sprvtx[i].color    = vcvt_f16_f32(obj.color);
        }
        vtxCount += 4;
      }];
  for (auto dstr : drawStringList)
  {
    auto *vtx2d = (VertexDataPrim2D *)textVtx.contents + vtxCount;
    for (int i = 0; i < 4; i++)
    {
      vtx2d[i].position = dstr->pos_[i];
      vtx2d[i].color    = vcvt_f16_f32(dstr->color_);
    }
    vtxCount += 4;
  }
}

//
- (void)drawText:(id<MTLRenderCommandEncoder>)renderEncoder
{
  __block NSUInteger vtxCount = 0;
  [spriteList
      enumerateObjectsUsingBlock:^(MetalSprite *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        [renderEncoder setFragmentTexture:obj.texObj atIndex:TextureIndexColor];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                          vertexStart:vtxCount
                          vertexCount:4];
        vtxCount += 4;
      }];
  for (auto dstr : drawStringList)
  {
    [renderEncoder setFragmentTexture:dstr->stringTex_.object atIndex:TextureIndexColor];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:vtxCount vertexCount:4];
    vtxCount += 4;
  }
  drawStringList.swap(drawStringListBack);
  drawStringList.clear();
}

// 描画
- (void)render:(nullable id<MTLRenderCommandEncoder>)renderEncoder
{
  [renderEncoder pushDebugGroup:@"Draw2D"];

  auto *uniform2d    = (Uniforms2D *)uniformBuffer_[pageIndex_].contents;
  uniform2d->size[0] = screenSize.width;
  uniform2d->size[1] = screenSize.height;

  [renderEncoder setDepthStencilState:depthState_];

  if (nbPrimitives_ > 0 || nbFillPrimitives_ > 0)
  {
    [renderEncoder setRenderPipelineState:pipelineStatePrim_];
  }

  if (nbFillPrimitives_ > 0)
  {
    // fill primitive draw
    auto vtx = fillVertices_[pageIndex_].buffer();

    [renderEncoder setVertexBuffer:uniformBuffer_[pageIndex_] offset:0 atIndex:1];
    [renderEncoder setFragmentBuffer:uniformBuffer_[pageIndex_] offset:0 atIndex:1];
    [renderEncoder setVertexBuffer:vtx offset:0 atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                      vertexStart:0
                      vertexCount:nbFillPrimitives_];
    nbFillPrimitives_ = 0;
  }

  if (nbPrimitives_ > 0)
  {
    // primitive draw
    auto vtx = vertices_[pageIndex_].buffer();

    [renderEncoder setVertexBuffer:uniformBuffer_[pageIndex_] offset:0 atIndex:1];
    [renderEncoder setFragmentBuffer:uniformBuffer_[pageIndex_] offset:0 atIndex:1];
    [renderEncoder setVertexBuffer:vtx offset:0 atIndex:0];
    [renderEncoder drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:nbPrimitives_];
    nbPrimitives_ = 0;
  }

  // text draw
  [renderEncoder setRenderPipelineState:pipelineStateText_];

  [renderEncoder setVertexBuffer:uniformBuffer_[pageIndex_] offset:0 atIndex:1];
  [renderEncoder setFragmentBuffer:uniformBuffer_[pageIndex_] offset:0 atIndex:1];

  [self setupDrawText];
  [renderEncoder setVertexBuffer:textVtx_[pageIndex_].buffer() offset:0 atIndex:0];
  [self drawText:renderEncoder];

  [renderEncoder popDebugGroup];

  [spriteList removeAllObjects];
  pageIndex_ = (pageIndex_ + 1) % 3;
}

//
- (nonnull NSArray<MetalSprite *> *)createSprites:(nonnull NSArray<NSString *> *)fileList
{
  auto texloader = [[MTKTextureLoader alloc] initWithDevice:device_];

  NSMutableArray<NSURL *> *urlList = [[NSMutableArray alloc] init];
  [fileList
      enumerateObjectsUsingBlock:^(NSString *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        NSURL *fURL = [[NSBundle mainBundle] URLForResource:obj withExtension:nil];
        [urlList addObject:fURL];
      }];

  NSMutableArray<MetalSprite *> *sprList = [[NSMutableArray alloc] init];
  [texloader newTexturesWithContentsOfURLs:urlList
                                   options:nil
                         completionHandler:^(NSArray<id<MTLTexture>> *_Nonnull textures,
                                             NSError *_Nullable error) {
                           [textures enumerateObjectsUsingBlock:^(id<MTLTexture> _Nonnull obj,
                                                                  NSUInteger idx,
                                                                  BOOL *_Nonnull stop) {
                             auto spr = [[MetalSprite alloc] initWithTexture:obj];
                             [sprList addObject:spr];
                           }];
                         }];
  [urlList release];
  return sprList;
}

//
- (nonnull NSArray<MetalSprite *> *)createSpritesByImage:(NSArray<NSString *> *)fileList
{
  NSMutableArray<MetalSprite *> *sprList = [[NSMutableArray alloc] init];
  [fileList
      enumerateObjectsUsingBlock:^(NSString *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
        NSURL *fURL         = [[NSBundle mainBundle] URLForResource:obj withExtension:nil];
        auto   img          = [[CIImage alloc] initWithContentsOfURL:fURL];
        auto   texdesc      = [[MTLTextureDescriptor alloc] init];
        texdesc.width       = img.extent.size.width;
        texdesc.height      = img.extent.size.height;
        texdesc.pixelFormat = colorFormat_;
        texdesc.textureType = MTLTextureType2D;
        texdesc.storageMode = MTLStorageModeManaged;
        texdesc.usage       = MTLResourceUsageRead | MTLResourceUsageWrite;
        auto tex            = [device_ newTextureWithDescriptor:texdesc];
        auto spr            = [[MetalSprite alloc] initWithImage:img texture:tex];
        [sprList addObject:spr];
        [spr release];
        [texdesc release];
      }];
  return sprList;
}

//
- (void)drawSprite:(MetalSprite *)sprite
{
  [spriteList addObject:sprite];
}

// No GPU submission: keep the current page available for the next update.
- (void)discardFrame
{
  nbPrimitives_ = 0;
  nbFillPrimitives_ = 0;
  drawStringList.clear();
  drawStringListBack.clear();
  [spriteList removeAllObjects];
}

// Called after the host acquires a free frame slot, before adding any draws.
- (void)beginFrame
{
  if (releasePending_[pageIndex_] && nbPrimitives_ == 0 && nbFillPrimitives_ == 0)
  {
    vertices_[pageIndex_].releaseUnused();
    fillVertices_[pageIndex_].releaseUnused();
    textVtx_[pageIndex_].releaseUnused();
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
  drawStringListBack.clear();
  [fontRender_ clearRenderCache];
  [textTextureCache_ removeAllObjects];
  for (auto &pending : releasePending_) pending = true;
}

- (alloy3d::RenderMemoryStats)memoryStats
{
  alloy3d::RenderMemoryStats stats;
  for (NSUInteger page = 0; page < 3; ++page)
  {
    stats.vertexBufferBytes += vertices_[page].bytes() + fillVertices_[page].bytes() + textVtx_[page].bytes();
    stats.releasePending |= releasePending_[page];
  }
  stats.textBitmapCacheBytes = [fontRender_ cacheBytes];
  stats.textTextureCacheBytes = [textTextureCache_ bytes];
  stats.textCacheEntries = [fontRender_ cacheCount] + [textTextureCache_ count];
  return stats;
}

@end
