//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "sprite.h"
#include <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>
#import <MetalKit/MetalKit.h>
#include <cmath>
#include <simd/simd.h>

@implementation Sprite
{
  CIImage        *image_;
  CIContext      *context_;
  CGColorSpaceRef colorSpace_;
  CIFilter       *filter_;
  SprPosList      posList;
}

@synthesize texObj, color, rotate, align, position, scale;

//
- (nonnull instancetype)initWithTexture:(nullable id<MTLTexture>)texture
{
  self   = [super init];
  texObj = [texture retain];
  posList.resize(4);
  align       = SpriteAlignLeftTop;
  rotate      = 0.0f;
  scale       = 1.0f;
  color.xyzw  = 1.0f;
  image_      = nil;
  context_    = nil;
  colorSpace_ = nil;
  filter_     = nil;
  return self;
}

//
- (nonnull instancetype)initWithImage:(nonnull CIImage *)image
                              texture:(nullable id<MTLTexture>)texture
{
  self   = [super init];
  texObj = [texture retain];
  image_ = [image retain];
  posList.resize(4);
  align       = SpriteAlignLeftTop;
  rotate      = 0.0f;
  scale       = 1.0f;
  color.xyzw  = 1.0f;
  filter_     = nil;
  context_    = [[CIContext alloc] init];
  colorSpace_ = CGColorSpaceCreateDeviceRGB();
  return self;
}

//
- (void)dealloc
{
  if (filter_ != nil)
  {
    [filter_ release];
  }
  if (colorSpace_ != nil)
  {
    CGColorSpaceRelease(colorSpace_);
  }
  if (context_ != nil)
  {
    [context_ release];
  }
  if (texObj != nil)
  {
    [texObj release];
  }
  if (image_ != nil)
  {
    [image_ release];
  }
  [super dealloc];
}

//
- (nonnull CIFilter *)setFilter:(nonnull NSString *)name override:(BOOL)ovrd
{
  if (filter_ == nil || ovrd)
  {
    filter_ = [[CIFilter filterWithName:name] retain];
    [filter_ setValue:image_ forKey:kCIInputImageKey];
  }

  return filter_;
}

- (void)setFilter:(nonnull CIFilter *)filter
{
  if (filter != filter_)
  {
    filter_ = [filter retain];
    [filter_ setValue:image_ forKey:kCIInputImageKey];
  }
}

//
- (void)renderImage:(nullable id<MTLCommandBuffer>)cmdBuff
{
  auto outImg = filter_.outputImage;

  [context_ render:outImg
       toMTLTexture:texObj
      commandBuffer:cmdBuff
             bounds:outImg.extent
         colorSpace:colorSpace_];
}

//
- (const SprPosList &)update
{
  simd_float2 center;
  simd_float2 size = simd_make_float2(texObj.width, texObj.height) * scale;
  int         line = 0;
  if (align <= SpriteAlignRightBottom)
  {
    bool isLR = align & 1;
    line      = align / 2;
    center.x  = isLR ? 0.0f + size.x : 0.0f;
  }
  else
  {
    line     = align - SpriteAlignCenterTop;
    center.x = size.x * 0.5f;
  }
  center.y = line == 0 ? 0.0f : line == 1 ? size.y * 0.5f : size.y;

  if (filter_ == nil)
  {
    posList[0] = simd_make_float2(size.x, 0.0f);
    posList[1] = simd_make_float2(0.0f, 0.0f);
    posList[2] = size;
    posList[3] = simd_make_float2(0.0f, size.y);
  }
  else
  {
    posList[0] = size;
    posList[1] = simd_make_float2(0.0f, size.y);
    posList[2] = simd_make_float2(size.x, 0.0f);
    posList[3] = simd_make_float2(0.0f, 0.0f);
  }

  auto rot    = simd_make_float2(rotate, rotate);
  auto rotcos = simd::cos(rot);
  auto rotsin = simd::sin(rot);
  rotsin.x    = -rotsin.x;
  for (auto &pos : posList)
  {
    auto ofs = pos - center;
    pos      = ofs * rotcos + ofs.yx * rotsin + position;
  }

  return posList;
}

@end
