//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <MetalKit/MetalKit.h>
#include <simd/vector_types.h>

@interface ModelPart : NSObject

@property(readonly) _Nullable id<MTLBuffer> vertexBuffer;
@property(readonly) _Nullable id<MTLBuffer> indexBuffer;
@property(readonly) _Nullable id<MTLTexture> texture;
@property(readonly) NSUInteger indexCount;
@property(readonly) simd_float4 baseColor;

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
- (NSUInteger)animationCount;
- (nonnull NSString *)animationNameAtIndex:(NSUInteger)index;
- (float)animationDurationAtIndex:(NSUInteger)index;
- (NSUInteger)currentAnimationIndex;
- (float)currentAnimationDuration;
- (void)setAnimationIndex:(NSUInteger)index;
- (BOOL)setAnimationName:(nonnull NSString *)name;
- (void)setAnimationTime:(float)seconds;
- (NSUInteger)rigCount;
- (nonnull NSString *)rigNameAtIndex:(NSUInteger)index;
- (NSInteger)rigIndexForName:(nonnull NSString *)name;
- (BOOL)rigTransformAtIndex:(NSUInteger)index transform:(nonnull simd_float4x4 *)transform;

@end
