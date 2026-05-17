//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <alloy3d/camera.h>
#import <alloy3d/metal/model.h>
#import <MetalKit/MetalKit.h>
#include <simd/vector_types.h>

typedef NS_ENUM(NSInteger, DrawText3DAlign) {
  DrawText3DAlignLeftBottom = 0,
  DrawText3DAlignCenterBottom,
  DrawText3DAlignRightBottom,
};

@interface Draw3D : NSObject

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view
                                   shaderlib:(nonnull id<MTLLibrary>)library;
- (void)render:(nullable id<MTLRenderCommandEncoder>)renderEncoder
        camera:(nonnull alloy3d::CameraData *)camera;
- (void)drawLine:(simd_float3)from to:(simd_float3)to color:(simd_float4)color;
- (void)drawTriangle:(simd_float3)p0 p1:(simd_float3)p1 p2:(simd_float3)p2 color:(simd_float4)color;
- (void)drawPlane:(simd_float3)p0
               p1:(simd_float3)p1
               p2:(simd_float3)p2
               p3:(simd_float3)p3
            color:(simd_float4)color;
- (void)drawSphere:(simd_float3)center
            radius:(float)radius
             color:(simd_float4)color
            slices:(int)slices
            stacks:(int)stacks;
- (void)drawBox:(simd_float3)center size:(simd_float3)size color:(simd_float4)color;
- (void)drawBox:(simd_float3)center
           size:(simd_float3)size
      rotationY:(float)rotationY
          color:(simd_float4)color;
- (void)drawBox:(simd_float3)center
           size:(simd_float3)size
       rotation:(simd_float3)rotation
          color:(simd_float4)color;
- (void)drawCylinder:(simd_float3)center
              radius:(float)radius
              height:(float)height
               color:(simd_float4)color
            segments:(int)segments;
- (void)drawCylinder:(simd_float3)center
              radius:(float)radius
              height:(float)height
            rotation:(simd_float3)rotation
               color:(simd_float4)color
            segments:(int)segments;
- (void)drawCone:(simd_float3)center
          radius:(float)radius
          height:(float)height
           color:(simd_float4)color
        segments:(int)segments;
- (void)drawCone:(simd_float3)center
          radius:(float)radius
          height:(float)height
        rotation:(simd_float3)rotation
           color:(simd_float4)color
        segments:(int)segments;
- (void)drawCone:(simd_float3)center
       direction:(simd_float3)direction
          radius:(float)radius
          height:(float)height
           color:(simd_float4)color
        segments:(int)segments;
- (void)setTextFont:(nonnull NSString *)fontName;
- (void)setTextFontSize:(float)fontSize;
- (void)drawText:(nonnull NSString *)message
        position:(simd_float3)position
      lineHeight:(float)lineHeight
           align:(DrawText3DAlign)align
           color:(simd_float4)color;
- (void)drawText:(nonnull NSString *)message
        position:(simd_float3)position
      lineHeight:(float)lineHeight
        rotation:(simd_float3)rotation
           align:(DrawText3DAlign)align
           color:(simd_float4)color;
- (void)drawModel:(nonnull MetalModel *)model
         position:(simd_float3)position
         rotation:(simd_float3)rotation
            scale:(simd_float3)scale
            color:(simd_float4)color;
- (void)setLightDirection:(simd_float3)direction ambient:(float)ambient diffuse:(float)diffuse;

@end
