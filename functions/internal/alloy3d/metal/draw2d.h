//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <alloy3d/metal/sprite.h>
#import <MetalKit/MetalKit.h>
#include <simd/vector_types.h>

@interface Draw2D : NSObject

@property CGSize screenSize;

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
                                   shaderlib:(nonnull id<MTLLibrary>)library;
- (void)render:(nullable id<MTLRenderCommandEncoder>)renderEncoder;
- (void)setTextColorRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (void)setTextFont:(nonnull NSString *)fontName;
- (void)setTextFontSize:(float)fontSize;
- (void)setTextFontColorRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (void)print:(nonnull NSString *)message x:(CGFloat)x y:(CGFloat)y keep:(BOOL)keep;
- (void)print:(nonnull NSString *)message x:(CGFloat)x y:(CGFloat)y;
- (void)drawLine:(simd_float2)from to:(simd_float2)to color:(simd_float4)color;
- (void)drawRect:(simd_float2)from to:(simd_float2)to color:(simd_float4)color;
- (void)drawRoundRect:(simd_float2)from
                   to:(simd_float2)to
               radius:(float)radius
                color:(simd_float4)color;
- (void)drawPolygon:(simd_float2)pos
             radius:(float)rad
             rotate:(float)rot
           numSides:(int)sides
              color:(simd_float4)color;
- (void)fillRect:(simd_float2)from to:(simd_float2)to color:(simd_float4)color;
- (void)fillRoundRect:(simd_float2)from
                   to:(simd_float2)to
               radius:(float)radius
                color:(simd_float4)color;
- (void)fillPolygon:(simd_float2)pos
             radius:(float)rad
             rotate:(float)rot
           numSides:(int)sides
              color:(simd_float4)color;
- (nonnull NSArray<MetalSprite *> *)createSprites:(nonnull NSArray<NSString *> *)fileList;
- (nonnull NSArray<MetalSprite *> *)createSpritesByImage:(nonnull NSArray<NSString *> *)fileList;
- (void)drawSprite:(nonnull MetalSprite *)sprite;

@end
