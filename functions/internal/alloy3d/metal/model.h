//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <MetalKit/MetalKit.h>
#include <alloy3d/bounds.h>
#include <simd/vector_types.h>

@interface ModelPart : NSObject

@property(readonly) _Nullable id<MTLBuffer>  vertexBuffer;
@property(readonly) _Nullable id<MTLBuffer>  indexBuffer;
@property(readonly) _Nullable id<MTLTexture> texture;
@property(readonly) _Nullable id<MTLTexture> normalTexture;
@property(readonly) float                    normalScale;
@property(readonly) _Nullable id<MTLTexture> roughnessTexture;
@property(readonly) _Nullable id<MTLTexture> occlusionTexture;
@property(readonly) float                    roughness;
@property(readonly) float                    occlusionStrength;
@property(readonly) NSUInteger               indexCount;
@property(readonly) simd_float4              baseColor;
// glTF alpha modes: 0 OPAQUE, 1 MASK, 2 BLEND.
@property(readonly) NSUInteger alphaMode;
@property(readonly) float      alphaCutoff;
@property(readonly) BOOL       doubleSided;
@property(readonly) BOOL       unlit;
// Conservative current-pose center for per-part transparency sorting (cached).
@property(readonly) simd_float3       sortCenter;
@property(readonly) alloy3d::Bounds3D renderBounds;

- (nonnull instancetype)initWithVertexBuffer:(nonnull id<MTLBuffer>)vertexBuffer
                                 indexBuffer:(nonnull id<MTLBuffer>)indexBuffer
                                     texture:(nullable id<MTLTexture>)texture
                                  indexCount:(NSUInteger)indexCount
                                   baseColor:(simd_float4)baseColor;
- (nullable id<MTLBuffer>)vertexBufferForPage:(NSUInteger)pageIndex;
- (nullable id<MTLBuffer>)jointMatrixBufferForPage:(NSUInteger)pageIndex;

@end

@interface MetalModel : NSObject

@property(readonly) BOOL loaded;
@property(readonly) NSArray<ModelPart *> *_Nonnull parts;

- (nonnull instancetype)initWithFile:(nonnull NSString *)fname device:(nonnull id<MTLDevice>)device;
- (nonnull MetalModel *)newInstance;
- (BOOL)getBounds:(nonnull alloy3d::Bounds3D *)bounds;
// Diagnostic identity for immutable node/skin/clip data (not a public API).
- (BOOL)sharesAssetWith:(nonnull MetalModel *)other;
- (NSUInteger)animationCount;
- (nonnull NSString *)animationNameAtIndex:(NSUInteger)index;
- (float)animationDurationAtIndex:(NSUInteger)index;
- (NSUInteger)currentAnimationIndex;
- (float)currentAnimationDuration;
- (void)setAnimationIndex:(NSUInteger)index;
- (BOOL)setAnimationName:(nonnull NSString *)name;
- (void)setAnimationTime:(float)seconds;
- (void)setAnimationBlendFrom:(NSUInteger)animationA
                        timeA:(float)timeASeconds
                           to:(NSUInteger)animationB
                        timeB:(float)timeBSeconds
                       weight:(float)weight;
- (NSUInteger)rigCount;
- (nonnull NSString *)rigNameAtIndex:(NSUInteger)index;
- (NSInteger)rigIndexForName:(nonnull NSString *)name;
- (BOOL)rigTransformAtIndex:(NSUInteger)index transform:(nonnull simd_float4x4 *)transform;

@end
