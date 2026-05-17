//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "texture.h"
#import <CoreImage/CoreImage.h>
#import <MetalKit/MetalKit.h>

@interface Texture ()
@end

@implementation Texture
{
  id<MTLDevice> device_;
}

@synthesize width, height, object;

- (void)dealloc
{
  [object release];
  [super dealloc];
}

- (void)buildTexture:(CGContextRef)ctx
{
  width        = CGBitmapContextGetWidth(ctx);
  height       = CGBitmapContextGetHeight(ctx);
  auto *bitmap = static_cast<uint8_t *>(CGBitmapContextGetData(ctx));

  auto texdesc        = [[MTLTextureDescriptor alloc] init];
  texdesc.width       = width;
  texdesc.height      = height;
  texdesc.pixelFormat = MTLPixelFormatRGBA8Unorm;
  texdesc.textureType = MTLTextureType2D;
  texdesc.storageMode = MTLStorageModeManaged;
  texdesc.usage       = MTLTextureUsageShaderRead;

  auto region = MTLRegionMake2D(0, 0, width, height);
  object      = [device_ newTextureWithDescriptor:texdesc];
  [object replaceRegion:region mipmapLevel:0 withBytes:bitmap bytesPerRow:width * 4];
  [texdesc release];
}

- (nonnull instancetype)initWithMemory:(nonnull CGContextRef)ctx
                                device:(nonnull id<MTLDevice>)device
{
  self = [super init];
  if (self != nil)
  {
    device_ = device;
    [self buildTexture:ctx];
  }

  return self;
}

- (nonnull instancetype)initWithFile:(nonnull NSString *)fname device:(nonnull id<MTLDevice>)device
{
  self = [super init];

  NSURL *fileURL = [[NSBundle mainBundle] URLForResource:fname withExtension:nil];

  auto texloader = [[MTKTextureLoader alloc] initWithDevice:device];

  NSArray *flist = @[ fileURL ];
  [texloader newTexturesWithContentsOfURLs:flist
                                   options:nil
                         completionHandler:^(NSArray<id<MTLTexture>> *_Nonnull textures,
                                             NSError *_Nullable error) {
                           object = [textures[0] retain];
                           width  = object.width;
                           height = object.height;
                           if (error != nil)
                           {
                             NSLog(@"error");
                           }
                         }];
  return self;
}

@end
