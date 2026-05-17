//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "app_delegate.h"
#import "renderer.h"
#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <MetalKit/MetalKit.h>
#include <simd/vector_types.h>
#include <string>
#include <vector>

// c++ interface
#include <alloy3d/application.h>

//
// InputView
//
@interface MyInputView : NSView <NSDraggingDestination>
- (instancetype)initWithFrame:(NSRect)frame applicationLoop:(alloy3d::ApplicationLoop *)appLoop;
@end

@implementation MyInputView
{
  alloy3d::ApplicationLoop *appLoop_;
}

- (instancetype)initWithFrame:(NSRect)frame applicationLoop:(alloy3d::ApplicationLoop *)appLoop
{
  self = [super initWithFrame:frame];
  if (self)
  {
    appLoop_ = appLoop;
    [self registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
  }
  return self;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}
- (void)keyDown:(NSEvent *)event
{
  // NSLog(@"keyDown");
}

- (void)keyUp:(NSEvent *)event
{
  // NSLog(@"keyDown");
}

- (void)mouseDown:(NSEvent *)event
{
  // NSLog@"mouseDown");
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
  if ([[sender draggingPasteboard] canReadObjectForClasses:@[ [NSURL class] ]
                                                   options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }])
  {
    return NSDragOperationCopy;
  }
  return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
  if (!appLoop_)
  {
    return NO;
  }

  NSPasteboard *pb = [sender draggingPasteboard];
  NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[ [NSURL class] ]
                                             options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
  if (urls.count == 0)
  {
    return NO;
  }

  std::vector<std::string> paths;
  paths.reserve(urls.count);
  for (NSURL *url in urls)
  {
    if (![url isFileURL])
    {
      continue;
    }
    NSString *path = [url path];
    if (path.length > 0)
    {
      paths.emplace_back(path.UTF8String);
    }
  }

  if (paths.empty())
  {
    return NO;
  }

  appLoop_->DroppedFiles(paths);
  return YES;
}

@end

//
// WindowDelegate
//
@interface WindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation WindowDelegate
- (void)windowDidMove:(NSNotification *)notification
{
  // NSLog(@"DidMove");
}
- (void)windowDidBecomeKey:(NSNotification *)notification
{
  // NSLog(@"DidKey");
}
- (void)windowDidBecomeMain:(NSNotification *)notification
{
  // NSLog(@"DidMain");
}
@end

//
// 枠の無いウィンドウでもキー入力を受け付けるようにする
// https://stackoverflow.com/a/11638926
//
@interface BorderlessWindow : NSWindow
@end

@implementation BorderlessWindow

- (BOOL)canBecomeKeyWindow
{
  return YES;
}

- (BOOL)canBecomeMainWindow
{
  return YES;
}

@end

//
// AppDelegate
//
@interface AppDelegate ()
{
  NSWindow       *window_;
  MTKView        *view_;
  id<MTLDevice>   device_;
  MyInputView    *inputView_;
  Renderer       *renderer_;
  WindowDelegate *windowDelegate_;

  alloy3d::ApplicationLoop *appLoop_;
}

NSMenu *createMenu();

@end

@implementation AppDelegate

- (instancetype)initWithAppLoop:(nonnull alloy3d::ApplicationLoop *)appLoop
{
  self     = [super init];
  appLoop_ = appLoop;
  return self;
}

- (void)quitCallback:(NSObject *)sender
{
  //   NSLog(@"Quit Push");
  appLoop_->WillCloseWindow();
  auto app = [NSApplication sharedApplication];
  [app terminate:sender];
}

- (NSMenu *)createMenu
{
  auto menu    = [[[NSMenu alloc] init] autorelease];
  auto appMenu = [[[NSMenu alloc] initWithTitle:@"Appname"] autorelease];
  @autoreleasepool
  {
    auto appMenuItem = [[[NSMenuItem alloc] init] autorelease];
    auto appName     = [NSRunningApplication.currentApplication localizedName];

    [appMenu addItemWithTitle:@"Quit" action:@selector(quitCallback:) keyEquivalent:@"q"];

    [appMenuItem setSubmenu:appMenu];

    [menu addItem:appMenuItem];
  }
  return menu;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
  auto           menu = [self createMenu];
  NSApplication *app  = notification.object;
  [app setMainMenu:menu];
  [app setActivationPolicy:NSApplicationActivationPolicy::NSApplicationActivationPolicyRegular];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  CGRect frame = {0.0, 0.0, 1600.0, 960.0};

  bool   border     = false;
  auto   resize     = appLoop_->InitialWindowSize(frame.size.width, frame.size.height, border);
  double clearRed   = 0.0;
  double clearGreen = 0.0;
  double clearBlue  = 0.0;
  double clearAlpha = 1.0;
  appLoop_->WindowClearColor(clearRed, clearGreen, clearBlue, clearAlpha);

  auto style = NSWindowStyleMaskClosable | (resize ? NSWindowStyleMaskResizable : 0) |
               (border ? NSWindowStyleMaskTitled : NSWindowStyleMaskBorderless);

  window_                       = [[BorderlessWindow alloc] initWithContentRect:frame
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:false];
  device_                       = MTLCreateSystemDefaultDevice();
  view_                         = [[MTKView alloc] initWithFrame:frame device:device_];
  view_.colorPixelFormat        = MTLPixelFormatRGBA8Unorm_sRGB;
  view_.clearColor              = MTLClearColorMake(clearRed, clearGreen, clearBlue, clearAlpha);
  view_.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
  view_.clearDepth              = 1.0f;
  view_.sampleCount             = 1;

  renderer_      = [[Renderer alloc] initWithMetalKitView:view_];
  view_.delegate = renderer_;
  [renderer_ setApplicationLoop:appLoop_];
  [renderer_ mtkView:view_ drawableSizeWillChange:view_.drawableSize];

  windowDelegate_     = [[WindowDelegate alloc] init];
  window_.delegate    = windowDelegate_;
  window_.contentView = view_;
  [window_ center];

  inputView_ = [[MyInputView alloc] initWithFrame:view_.bounds applicationLoop:appLoop_];
  [inputView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [view_ addSubview:inputView_];
  [window_ makeFirstResponder:view_];

  window_.title = [NSString stringWithUTF8String:appLoop_->GetApplicationName()];
  [renderer_ startApplicationLoop];
  [window_ makeKeyAndOrderFront:nil];

  NSApplication *app = notification.object;
  [app activateIgnoringOtherApps:true];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
  NSLog(@"terminate APP");
  [renderer_ release];
  [windowDelegate_ release];
  [device_ release];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  return YES;
}

@end

//
void alloy3d::LaunchApplication(std::shared_ptr<alloy3d::ApplicationLoop> apploop)
{
  AppDelegate *del  = [[AppDelegate alloc] initWithAppLoop:apploop.get()];
  auto         sapp = [NSApplication sharedApplication];
  [sapp setDelegate:del];
  [sapp run];
}

//
