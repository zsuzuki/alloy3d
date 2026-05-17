//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "renderer.h"
#include <alloy3d/application.h>
#import <alloy3d/camera.h>
#import <alloy3d/metal/draw2d.h>
#import <alloy3d/metal/draw3d.h>
#import <alloy3d/metal/model.h>
#import <alloy3d/metal/sprite.h>
#include <alloy3d/model.h>
#include <alloy3d/sprite.h>
#include <AppKit/AppKit.h>
#import <Metal/Metal.h>
#include <cstddef>
#include <memory>
#import <simd/simd.h>
#include <string>
#include <string_view>

static const NSUInteger MaxBuffersInFlight = 3;

namespace
{
NSString *StringViewToNSString(std::string_view value)
{
  if (value.empty())
  {
    return @"";
  }

  NSString *string = [[NSString alloc] initWithBytes:value.data()
                                             length:value.size()
                                           encoding:NSUTF8StringEncoding];
  if (string == nil)
  {
    return @"";
  }
  return [string autorelease];
}

DrawText3DAlign ToDrawText3DAlign(alloy3d::TextAlign3D align)
{
  switch (align)
  {
  case alloy3d::TextAlign3D::CenterBottom:
    return DrawText3DAlignCenterBottom;
  case alloy3d::TextAlign3D::RightBottom:
    return DrawText3DAlignRightBottom;
  case alloy3d::TextAlign3D::LeftBottom:
  default:
    return DrawText3DAlignLeftBottom;
  }
}
} // namespace

//
class SpriteImpl : public alloy3d::Sprite
{
  NSArray<MetalSprite *> *sprPtr_;

public:
  SpriteImpl(NSArray<MetalSprite *> *sprl) : sprPtr_(sprl) {}
  ~SpriteImpl() override
  {
    [sprPtr_[0] release];
    [sprPtr_ release];
  }

  bool IsLoaded() const override { return [sprPtr_ count] > 0 && sprPtr_[0]; }

  void SetAlign(Align align) override { sprPtr_[0].align = (SpriteAlign)align; }
  void SetScale(float scale) override { sprPtr_[0].scale = scale; }
  void SetRotate(float rotate) override { sprPtr_[0].rotate = rotate; }
  void SetPosition(float x, float y) override { sprPtr_[0].position = simd_make_float2(x, y); }
  void SetFaceColor(float red, float green, float blue, float alpha) override
  {
    sprPtr_[0].color = simd_make_float4(red, green, blue, alpha);
  }

  MetalSprite *GetSprite() { return sprPtr_[0]; }
};

//
class ModelImpl : public alloy3d::Model
{
  MetalModel *model_;

public:
  ModelImpl(MetalModel *model) : model_(model) {}
  ~ModelImpl() override { [model_ release]; }

  bool IsLoaded() const override { return model_ != nil && model_.loaded; }
  std::size_t AnimationCount() const override { return model_ != nil ? [model_ animationCount] : 0; }
  std::string AnimationName(std::size_t index) const override
  {
    if (model_ == nil)
    {
      return {};
    }
    auto *name = [model_ animationNameAtIndex:index];
    return name != nil ? std::string([name UTF8String]) : std::string{};
  }
  float AnimationDuration(std::size_t index) const override
  {
    return model_ != nil ? [model_ animationDurationAtIndex:index] : 0.0f;
  }
  std::size_t CurrentAnimationIndex() const override
  {
    return model_ != nil ? [model_ currentAnimationIndex] : 0;
  }
  float CurrentAnimationDuration() const override
  {
    return model_ != nil ? [model_ currentAnimationDuration] : 0.0f;
  }
  void SetAnimation(std::size_t index) override
  {
    if (model_ != nil)
    {
      [model_ setAnimationIndex:index];
    }
  }
  bool SetAnimation(std::string_view name) override
  {
    if (model_ == nil)
    {
      return false;
    }
    return [model_ setAnimationName:StringViewToNSString(name)];
  }
  void SetAnimationTime(float seconds) override
  {
    if (model_ != nil)
    {
      [model_ setAnimationTime:seconds];
    }
  }
  std::size_t RigCount() const override { return model_ != nil ? [model_ rigCount] : 0; }
  std::string RigName(std::size_t index) const override
  {
    if (model_ == nil)
    {
      return {};
    }
    auto *name = [model_ rigNameAtIndex:index];
    return name != nil ? std::string([name UTF8String]) : std::string{};
  }
  int RigIndex(std::string_view name) const override
  {
    return model_ != nil ? static_cast<int>([model_ rigIndexForName:StringViewToNSString(name)]) : -1;
  }
  bool RigTransform(std::size_t index, simd_float4x4 &transform) const override
  {
    return model_ != nil && [model_ rigTransformAtIndex:index transform:&transform];
  }

  MetalModel *GetModel() { return model_; }
};

//
class AppCtx : public alloy3d::ApplicationContext
{
public:
  Draw2D     *draw2d_;
  Draw3D     *draw3d_;
  alloy3d::CameraData *camera_;
  id<MTLDevice> device_;

  AppCtx()           = default;
  ~AppCtx() override = default;

  float ContentScale() const override { return [[NSScreen mainScreen] backingScaleFactor]; }

  void Print(std::string_view msg, float x, float y) override
  {
    [draw2d_ print:StringViewToNSString(msg) x:x y:y];
  }
  void SetTextColor(float red, float green, float blue, float alpha) override
  {
    [draw2d_ setTextColorRed:red green:green blue:blue alpha:alpha];
  }
  void SetTextFont(std::string_view fontName) override
  {
    auto string = StringViewToNSString(fontName);
    [draw2d_ setTextFont:string];
    [draw3d_ setTextFont:string];
  }
  void SetTextFontSize(float fontSize) override
  {
    [draw2d_ setTextFontSize:fontSize];
    [draw3d_ setTextFontSize:fontSize];
  }
  void SetTextFontColor(float red, float green, float blue, float alpha) override
  {
    [draw2d_ setTextFontColorRed:red green:green blue:blue alpha:alpha];
  }

  void DrawLine(simd_float2 from, simd_float2 to, simd_float4 color) override
  {
    [draw2d_ drawLine:from to:to color:color];
  }
  void DrawRect(simd_float2 from, simd_float2 to, simd_float4 color) override
  {
    [draw2d_ drawRect:from to:to color:color];
  }
  void DrawRoundRect(simd_float2 from, simd_float2 to, float radius, simd_float4 color) override
  {
    [draw2d_ drawRoundRect:from to:to radius:radius color:color];
  }
  void DrawPolygon(simd_float2 pos, float rad, float rot, int sides, simd_float4 color) override
  {
    [draw2d_ drawPolygon:pos radius:rad rotate:rot numSides:sides color:color];
  }
  void FillPolygon(simd_float2 pos, float rad, float rot, int sides, simd_float4 color) override
  {
    [draw2d_ fillPolygon:pos radius:rad rotate:rot numSides:sides color:color];
  }

  void FillRect(simd_float2 from, simd_float2 to, simd_float4 color) override
  {
    [draw2d_ fillRect:from to:to color:color];
  }
  void FillRoundRect(simd_float2 from, simd_float2 to, float radius, simd_float4 color) override
  {
    [draw2d_ fillRoundRect:from to:to radius:radius color:color];
  }

  alloy3d::CameraData &GetCamera() override { return *camera_; }

  void SetLight3D(simd_float3 direction, float ambient, float diffuse) override
  {
    [draw3d_ setLightDirection:direction ambient:ambient diffuse:diffuse];
  }

  void DrawLine3D(simd_float3 from, simd_float3 to, simd_float4 color) override
  {
    [draw3d_ drawLine:from to:to color:color];
  }
  void DrawTriangle3D(simd_float3 p0, simd_float3 p1, simd_float3 p2, simd_float4 color) override
  {
    [draw3d_ drawTriangle:p0 p1:p1 p2:p2 color:color];
  }
  void DrawPlane3D(simd_float3 p0, simd_float3 p1, simd_float3 p2, simd_float3 p3,
                   simd_float4 color) override
  {
    [draw3d_ drawPlane:p0 p1:p1 p2:p2 p3:p3 color:color];
  }
  void DrawSphere3D(simd_float3 center, float radius, simd_float4 color, int slices,
                    int stacks) override
  {
    [draw3d_ drawSphere:center radius:radius color:color slices:slices stacks:stacks];
  }
  void DrawBox3D(simd_float3 center, simd_float3 size, simd_float4 color) override
  {
    [draw3d_ drawBox:center size:size color:color];
  }
  void DrawBox3D(simd_float3 center, simd_float3 size, float rotationY,
                 simd_float4 color) override
  {
    [draw3d_ drawBox:center size:size rotationY:rotationY color:color];
  }
  void DrawBox3D(simd_float3 center, simd_float3 size, simd_float3 rotation,
                 simd_float4 color) override
  {
    [draw3d_ drawBox:center size:size rotation:rotation color:color];
  }
  void DrawCylinder3D(simd_float3 center, float radius, float height, simd_float4 color,
                      int segments) override
  {
    [draw3d_ drawCylinder:center radius:radius height:height color:color segments:segments];
  }
  void DrawCylinder3D(simd_float3 center, float radius, float height, simd_float3 rotation,
                      simd_float4 color, int segments) override
  {
    [draw3d_ drawCylinder:center radius:radius height:height rotation:rotation color:color
                 segments:segments];
  }
  void DrawCone3D(simd_float3 center, float radius, float height, simd_float4 color,
                  int segments) override
  {
    [draw3d_ drawCone:center radius:radius height:height color:color segments:segments];
  }
  void DrawCone3D(simd_float3 center, float radius, float height, simd_float3 rotation,
                  simd_float4 color, int segments) override
  {
    [draw3d_ drawCone:center radius:radius height:height rotation:rotation color:color
             segments:segments];
  }
  void DrawCone3D(simd_float3 center, simd_float3 direction, float radius, float height,
                  simd_float4 color, int segments) override
  {
    [draw3d_ drawCone:center direction:direction radius:radius height:height color:color
             segments:segments];
  }
  void DrawText3D(std::string_view msg, simd_float3 position, float lineHeight, simd_float4 color,
                  alloy3d::TextAlign3D align) override
  {
    [draw3d_ drawText:StringViewToNSString(msg)
             position:position
           lineHeight:lineHeight
                align:ToDrawText3DAlign(align)
                color:color];
  }
  void DrawText3D(std::string_view msg, simd_float3 position, float lineHeight,
                  simd_float3 rotation, simd_float4 color, alloy3d::TextAlign3D align) override
  {
    [draw3d_ drawText:StringViewToNSString(msg)
             position:position
           lineHeight:lineHeight
             rotation:rotation
                align:ToDrawText3DAlign(align)
                color:color];
  }

  ModelPtr LoadModel(std::string fname) override
  {
    auto fnstr = [NSString stringWithUTF8String:fname.c_str()];
    auto model = [[MetalModel alloc] initWithFile:fnstr device:device_];
    return std::make_shared<ModelImpl>(model);
  }

  void DrawModel3D(ModelPtr model,
                   simd_float3 position,
                   simd_float3 rotation,
                   simd_float3 scale,
                   simd_float4 color) override
  {
    if (auto modeli = std::dynamic_pointer_cast<ModelImpl>(model))
    {
      if (modeli->IsLoaded())
      {
        [draw3d_ drawModel:modeli->GetModel()
                  position:position
                  rotation:rotation
                     scale:scale
                     color:color];
      }
    }
  }

  SpritePtr CreateSprite(std::string fname) override
  {
    auto fnstr = [NSString stringWithUTF8String:fname.c_str()];

    NSArray<NSString *> *fnarr = @[ fnstr ];

    if (auto sprList = [draw2d_ createSprites:fnarr])
    {
      return std::make_shared<SpriteImpl>(sprList);
    }
    return {};
  }
  void DrawSprite(SpritePtr spr) override
  {
    if (auto spri = std::dynamic_pointer_cast<SpriteImpl>(spr))
    {
      if (spri->IsLoaded())
      {
        [draw2d_ drawSprite:spri->GetSprite()];
      }
    }
  }
};

@implementation Renderer
{
  dispatch_semaphore_t     renderSemaphore_;
  uint8_t                  uniformBufferIndex_;
  id<MTLDevice>            device_;
  id<MTLCommandQueue>      commandQueue_;
  id<MTLLibrary>           shaderLibrary_;
  id<MTLDepthStencilState> depthState_;

  alloy3d::ApplicationLoop *appLoop_;

  alloy3d::CameraData camera_;
  Draw2D    *draw2d_;
  Draw3D    *draw3d_;
  bool       applicationStarted_;
}

+ (id<MTLLibrary>)createShaderLibrary:(id<MTLDevice>)device fromName:(NSString *)libraryName
{
  NSURL *libraryURL = [[NSBundle mainBundle] URLForResource:libraryName withExtension:@"metallib"];
  if (libraryURL == nil)
  {
    NSLog(@"Couldn't find library file: %@", libraryName);
    return nil;
  }

  NSError       *libraryError = nil;
  id<MTLLibrary> library      = [device newLibraryWithURL:libraryURL error:&libraryError];
  if (library == nil)
  {
    NSLog(@"Couldn't create library: %@", libraryName);
    return nil;
  }

  return library;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
{
  self = [super init];
  if (self != nil)
  {
    device_          = view.device;
    renderSemaphore_ = dispatch_semaphore_create(MaxBuffersInFlight);
    commandQueue_    = [device_ newCommandQueue];

    // initialize
    shaderLibrary_ = [Renderer createShaderLibrary:device_ fromName:@"shaders/shaders"];
    draw2d_        = [[Draw2D alloc] initWithMetalKitView:view shaderlib:shaderLibrary_];
    draw3d_        = [[Draw3D alloc] initWithMetalKitView:view shaderlib:shaderLibrary_];

    //

    auto depthStateDesc                 = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled    = YES;
    depthState_ = [device_ newDepthStencilStateWithDescriptor:depthStateDesc];
  }

  return self;
}

- (void)dealloc
{
  [depthState_ release];
  [draw2d_ release];
  [draw3d_ release];
  [super dealloc];
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
  dispatch_semaphore_wait(renderSemaphore_, DISPATCH_TIME_FOREVER);

  uniformBufferIndex_ = (uniformBufferIndex_ + 1) % MaxBuffersInFlight;

  id<MTLCommandBuffer> commandBuffer = [commandQueue_ commandBuffer];
  commandBuffer.label                = @"MyCommand";

  __block dispatch_semaphore_t block_sema = renderSemaphore_;
  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    dispatch_semaphore_signal(block_sema);
  }];

  AppCtx appctx;
  appctx.draw2d_ = draw2d_;
  appctx.draw3d_ = draw3d_;
  appctx.camera_ = &camera_;
  appctx.device_ = device_;
  appLoop_->Update(appctx);

  // render
  auto renderPassDescriptor = view.currentRenderPassDescriptor;

  if (renderPassDescriptor != nil)
  {
    auto renderEncoder  = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    renderEncoder.label = @"MyRenderEncoder";

    [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
    [renderEncoder setCullMode:MTLCullModeBack];
    [renderEncoder setDepthStencilState:depthState_];

    // 3D Graphics
    [draw3d_ render:renderEncoder camera:&camera_];

    // 2D Graphics
    [renderEncoder setCullMode:MTLCullModeNone];
    [draw2d_ render:renderEncoder];

    // Game Render End

    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:view.currentDrawable];
  }

  [commandBuffer commit];
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
  float aspect       = size.width / (float)size.height;
  draw2d_.screenSize = size;
  camera_.buildPerspective(45.0f, aspect, 0.1f, 1000.0f);
  appLoop_->ResizeWindow(size.width, size.height);
}

- (void)setApplicationLoop:(nonnull alloy3d::ApplicationLoop *)appLoop
{
  appLoop_ = appLoop;
}

- (void)startApplicationLoop
{
  if (appLoop_ == nullptr || applicationStarted_)
  {
    return;
  }

  applicationStarted_ = true;

  AppCtx appctx;
  appctx.draw2d_ = draw2d_;
  appctx.draw3d_ = draw3d_;
  appctx.camera_ = &camera_;
  appctx.device_ = device_;
  appLoop_->Start(appctx);
}

@end
