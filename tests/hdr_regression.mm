#include "render_harness.h"
#import <alloy3d/metal/draw2d.h>
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: hdr_regression shaders.metallib fixtures");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      for (NSUInteger samples : {1u, 4u})
      {
        Harness             h(device, argv[1], 256, samples, true);
        alloy3d::CameraData camera;
        Check(h.post->bytes() == 0, "disabled/unallocated HDR targets used memory");
        auto        model = h.Load(std::filesystem::path(argv[2]) / "unlit.glb");
        std::string error;
        auto        shader =
            [h.draw createModelShader:"float3 alloy3dShade(ModelSurface s,float4 p){return p.rgb;}"
                          diagnostics:error];
        Check(bool(shader), error.c_str());
        auto submit = [&]
        {
          [h.draw setModelShader:shader parameters:{4, 2, .5f, 1}];
          [h.draw drawModel:model
                   position:{0, 0, .4f}
                   rotation:{}
                      scale:{1, 1, 1}
                      color:{1, 1, 1, 1}];
        };
        auto center = [](const Pixels &p) { return p[128 * 256 + 128]; };
        h.post->set({.1f, alloy3d::ToneMapping3D::None});
        auto low = center(h.Run(camera, submit));
        Check(std::abs(int((low >> 16) & 255) - 102) <= 1 &&
                  std::abs(int((low >> 8) & 255) - 51) <= 1,
              "HDR clipped before exposure");
        h.post->set({1, alloy3d::ToneMapping3D::Reinhard});
        auto mapped = center(h.Run(camera, submit));
        Check(std::abs(int((mapped >> 16) & 255) - 204) <= 1 &&
                  std::abs(int((mapped >> 8) & 255) - 170) <= 1,
              "Reinhard output incorrect");
        h.post->set({1, alloy3d::ToneMapping3D::ACES});
        auto aces = center(h.Run(camera, submit));
        Check(std::abs(int((aces >> 16) & 255) - 248) <= 1, "ACES output incorrect");
        bool rejected = false;
        try
        {
          h.post->set({NAN});
        }
        catch (const std::invalid_argument &)
        {
          rejected = true;
        }
        Check(rejected && aces == center(h.Run(camera, submit)),
              "invalid exposure mutated live settings");
        for (int page = 0; page < 3; ++page)
        {
          h.Begin(page);
          submit();
          h.Encode(page, camera);
          [h.commands[page] commit];
          Check(center(h.Read(page)) == aces, "HDR frame pages differ");
        }
        size_t bytes = h.post->bytes();
        Check(bytes >= 256 * 256 * 8 * 3, "HDR targets were not accounted");
        h.post->releaseUnusedMemory();
        Check(h.post->releasePending(), "HDR release not scheduled");
        for (int page = 0; page < 3; ++page)
        {
          h.Begin(page);
          submit();
          h.Encode(page, camera);
          [h.commands[page] commit];
          h.Read(page);
        }
        Check(!h.post->releasePending() && bytes == h.post->bytes(),
              "HDR page reuse leaked target capacity");
        // 2D is composed after exposure and tone mapping, with the drawable format/sample count.
        Draw2D *overlay    = [[Draw2D alloc] initWithMetalKitView:h.view shaderlib:h.library];
        overlay.screenSize = CGSizeMake(256, 256);
        h.post->set({0, alloy3d::ToneMapping3D::ACES});
        h.Begin(0);
        submit();
        [overlay beginFrame];
        [overlay fillRect:{0, 0} to:{256, 256} color:{1, 0, 0, 1}];
        h.Encode(0, camera, [&](id<MTLRenderCommandEncoder> encoder) { [overlay render:encoder]; });
        [h.commands[0] commit];
        Check(center(h.Read(0)) == 0xffff0000, "HDR processing affected 2D overlay");
        [overlay release];
        [model release];
        auto smallerDesc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                               width:128
                                                              height:128
                                                           mipmapped:NO];
        smallerDesc.usage                   = MTLTextureUsageRenderTarget;
        auto smaller                        = [device newTextureWithDescriptor:smallerDesc];
        auto resized                        = [MTLRenderPassDescriptor renderPassDescriptor];
        resized.colorAttachments[0].texture = smaller;
        h.post->begin(resized, 0);
        Check(h.post->color(0).width == 128 && h.post->bytes() < bytes,
              "HDR targets did not shrink on resize");
        [smaller release];
      }
      [device release];
      return 0;
    }
    catch (const std::exception &e)
    {
      std::fprintf(stderr, "FAIL: %s\n", e.what());
      return 1;
    }
  }
}
