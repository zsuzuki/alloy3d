//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <MetalKit/MetalKit.h>

#include "app_launch.h"

@interface Renderer : NSObject <MTKViewDelegate>

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view;
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size;
- (void)drawInMTKView:(nonnull MTKView *)view;

- (void)setApplicationLoop:(nonnull ApplicationLoop *)appLoop;
- (void)startApplicationLoop;

@end
