//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <CoreImage/CoreImage.h>
#import <MetalKit/MetalKit.h>
#include <simd/vector_types.h>
#include <vector>

using SprPosList = std::vector<simd_float2>;

@interface Sprite : NSObject

typedef NS_ENUM(NSUInteger, SpriteAlign) {
  SpriteAlignLeftTop,
  SpriteAlignRightTop,
  SpriteAlignLeftCenter,
  SpriteAlignRightCenter,
  SpriteAlignLeftBottom,
  SpriteAlignRightBottom,
  SpriteAlignCenterTop,
  SpriteAlignCenter,
  SpriteAlignCenterBottom,
};

@property(readonly) _Nullable id<MTLTexture> texObj;
@property simd_float4                        color;
@property float                              rotate;
@property float                              scale;
@property SpriteAlign                        align;
@property simd_float2                        position;

- (nonnull instancetype)initWithTexture:(nullable id<MTLTexture>)texture;
- (nonnull instancetype)initWithImage:(nonnull CIImage *)image
                              texture:(nullable id<MTLTexture>)texture;
- (nonnull CIFilter *)setFilter:(nonnull NSString *)name override:(BOOL)ovrd;
- (void)setFilter:(nonnull CIFilter *)filter;
- (void)renderImage:(nullable id<MTLCommandBuffer>)cmdBuff;
- (const SprPosList &)update;

@end
