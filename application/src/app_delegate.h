//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <Cocoa/Cocoa.h>
#include <memory>

#include <alloy3d/application.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (nonnull instancetype)initWithAppLoop:(nonnull alloy3d::ApplicationLoop *)appLoop;

@end
