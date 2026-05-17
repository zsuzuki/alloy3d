//
// Copyright 2023 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "font_render.h"
#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreText/CTLine.h>
#include <Foundation/Foundation.h>
#include <algorithm>
#include <cmath>
#import <string>

namespace
{
const NSUInteger MaxRenderCacheEntries = 512;
}

//
//
//
@interface FontRenderCacheEntry : NSObject
{
  CGContextRef context_;
  CGRect       rect_;
}

- (nonnull instancetype)initWithContext:(nonnull CGContextRef)context rect:(CGRect)rect;
- (nonnull CGContextRef)context;
- (CGRect)rect;

@end

//
//
//
@implementation FontRenderCacheEntry

- (nonnull instancetype)initWithContext:(nonnull CGContextRef)context rect:(CGRect)rect
{
  self = [super init];
  if (self != nil)
  {
    context_ = CGContextRetain(context);
    rect_    = rect;
  }
  return self;
}

- (void)dealloc
{
  CGContextRelease(context_);
  [super dealloc];
}

- (nonnull CGContextRef)context
{
  return context_;
}

- (CGRect)rect
{
  return rect_;
}

@end

//
//
//
@interface FontRender ()
{
  NSString            *fontName_;
  NSFont              *font_;
  NSDictionary        *attributes_;
  NSColor             *color_;
  NSMutableDictionary *renderCache_;
  NSMutableArray      *renderCacheKeys_;
  CGFloat              size_;
}
@end

//
//
//
@implementation FontRender

- (id)init
{
  self = [super init];
  if (self != nil)
  {
    size_            = 20.0f;
    fontName_        = [@"ヒラギノ角ゴシック" copy];
    renderCache_     = [[NSMutableDictionary alloc] init];
    renderCacheKeys_ = [[NSMutableArray alloc] init];
    [self makeFont];
    [self SetColor:1.0f green:1.0f blue:1.0f];
  }
  return self;
}

- (void)dealloc
{
  [self ClearFont];
  [super dealloc];
}

- (void)ClearFont
{
  [self clearAttribute];
  [self clearRenderCache];
  [color_ release];
  [font_ release];
  [fontName_ release];
  [renderCache_ release];
  [renderCacheKeys_ release];
  font_            = nil;
  fontName_        = nil;
  color_           = nil;
  renderCache_     = nil;
  renderCacheKeys_ = nil;
}

// internal function
- (void)clearAttribute
{
  [attributes_ release];
  attributes_ = nil;
}

- (void)clearRenderCache
{
  [renderCache_ removeAllObjects];
  [renderCacheKeys_ removeAllObjects];
}

- (void)makeFont
{
  [font_ release];
  font_ = [[NSFont fontWithName:fontName_ size:size_] retain];
  [self clearAttribute];
  [self clearRenderCache];
}

//
//
//
- (void)SetFont:(const char *_Nonnull)fontName
{
  NSString *newFontName = [NSString stringWithUTF8String:fontName];
  if (newFontName == nil)
  {
    return;
  }
  if ([fontName_ isEqualToString:newFontName])
  {
    return;
  }

  [fontName_ release];
  fontName_ = [newFontName copy];
  [self makeFont];
}
- (void)SetSize:(float)fontSize
{
  if (size_ == fontSize)
  {
    return;
  }

  size_ = fontSize;
  [self makeFont];
}
- (void)SetColor:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
  [self SetColor:red green:green blue:blue alpha:1.0f];
}
- (void)SetColor:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
  if (color_ != nil)
  {
    CGFloat currentRed = 0.0f, currentGreen = 0.0f, currentBlue = 0.0f, currentAlpha = 0.0f;
    auto    rgbColor = [color_ colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
    [rgbColor getRed:&currentRed green:&currentGreen blue:&currentBlue alpha:&currentAlpha];
    if (currentRed == red && currentGreen == green && currentBlue == blue && currentAlpha == alpha)
    {
      return;
    }
  }

  [color_ release];
  color_ = [[NSColor colorWithRed:red green:green blue:blue alpha:alpha] retain];
  [self clearAttribute];
  [self clearRenderCache];
}

- (nonnull NSString *)CacheKey:(nonnull NSString *)message
{
  CGFloat red = 0.0f, green = 0.0f, blue = 0.0f, alpha = 0.0f;
  auto    rgbColor = [color_ colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
  [rgbColor getRed:&red green:&green blue:&blue alpha:&alpha];
  return [NSString stringWithFormat:@"%@\x1f%@\x1f%.8g\x1f%.8g\x1f%.8g\x1f%.8g\x1f%.8g",
                                    fontName_,
                                    message,
                                    size_,
                                    red,
                                    green,
                                    blue,
                                    alpha];
}

//
//
//
- (void)Render:(nonnull NSString *)message callback:(nonnull RenderCallback)callback
{
  NSString *cacheKey    = [self CacheKey:message];
  auto      cachedEntry = (FontRenderCacheEntry *)[renderCache_ objectForKey:cacheKey];
  if (cachedEntry != nil)
  {
    callback([cachedEntry context], [cachedEntry rect]);
    return;
  }

  // フォント情報がなければ生成
  if (attributes_ == nil)
  {
    auto attrib = @{
      NSFontAttributeName : font_,
      NSForegroundColorAttributeName : color_,
    };
    attributes_ = [attrib retain];
  }

  // セットアップ
  CGFloat ascent, descent;
  auto    attrStr    = [[NSAttributedString alloc] initWithString:message attributes:attributes_];
  auto    colorSpace = [[NSColorSpace deviceRGBColorSpace] CGColorSpace];
  auto    line       = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrStr);
  auto    rect       = CTLineGetImageBounds(line, nullptr);
  auto    lineWidth  = CTLineGetTypographicBounds(line, &ascent, &descent, nullptr);
  auto    hasInk     = !CGRectIsNull(rect) && !CGRectIsEmpty(rect);
  auto    originX    = hasInk ? std::floor(std::min<CGFloat>(0.0f, CGRectGetMinX(rect))) : 0.0f;
  auto    rightX =
      hasInk ? std::ceil(std::max<CGFloat>(lineWidth, CGRectGetMaxX(rect))) : std::ceil(lineWidth);
  auto textWidth     = std::max<CGFloat>(1.0f, rightX - originX);
  auto bitmapOriginY = hasInk ? -rect.origin.y : descent;
  auto baseHeight    = hasInk ? std::ceil(rect.size.height + descent) : std::ceil(ascent + descent);
  auto textHeight    = std::max<CGFloat>(1.0f, baseHeight);
  auto layoutOriginY = size_ - textHeight + bitmapOriginY;

  // レンダリング
  auto ctx = CGBitmapContextCreate(
      nullptr, textWidth, textHeight, 8, 4 * textWidth, colorSpace, kCGImageAlphaPremultipliedLast);
  auto offsetY = descent + bitmapOriginY;
  CGContextSetTextPosition(ctx, -originX, offsetY);
  CTLineDraw(line, ctx);
  CGFloat width  = CGBitmapContextGetWidth(ctx);
  CGFloat height = CGBitmapContextGetHeight(ctx);

  auto      bbox       = CGRectMake(originX, layoutOriginY, width, height);
  auto      cacheEntry = [[FontRenderCacheEntry alloc] initWithContext:ctx rect:bbox];
  if ([renderCacheKeys_ count] >= MaxRenderCacheEntries)
  {
    NSString *oldCacheKey = [renderCacheKeys_ objectAtIndex:0];
    [renderCache_ removeObjectForKey:oldCacheKey];
    [renderCacheKeys_ removeObjectAtIndex:0];
  }
  [renderCache_ setObject:cacheEntry forKey:cacheKey];
  [renderCacheKeys_ addObject:cacheKey];
  [cacheEntry release];

  callback(ctx, bbox);

  [attrStr release];
  CFRelease(colorSpace);
  CFRelease(line);
  CFRelease(ctx);
}

@end
