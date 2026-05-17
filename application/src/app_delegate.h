//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import <Cocoa/Cocoa.h>
#include <memory>

#include "app_launch.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

- (nonnull instancetype)initWithAppLoop:(nonnull ApplicationLoop *)appLoop;

@end
