//
// Copyright 2023 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import <CoreText/CTFont.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>
#include <cinttypes>

//
//
//
@interface FontRender : NSObject

typedef void (^RenderCallback)(CGContextRef _Nonnull ctx, CGRect rect);

- (void)SetFont:(const char *_Nonnull)fontName;
- (void)SetSize:(float)fontSize;
- (void)SetColor:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue;
- (void)SetColor:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (void)ClearFont;
- (nonnull NSString *)CacheKey:(nonnull NSString *)message;
- (void)Render:(nonnull NSString *)message callback:(nonnull RenderCallback)callback;

@end
