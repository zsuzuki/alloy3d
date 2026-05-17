//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <CoreGraphics/CoreGraphics.h>
#import <MetalKit/MetalKit.h>

@interface Texture : NSObject

@property(readonly) _Nullable id<MTLTexture> object;
@property(readonly) size_t                   width;
@property(readonly) size_t                   height;

- (nonnull instancetype)initWithMemory:(nonnull CGContextRef)ctx
                                device:(nonnull id<MTLDevice>)device;

- (nonnull instancetype)initWithFile:(nonnull NSString *)fname device:(nonnull id<MTLDevice>)device;

@end
