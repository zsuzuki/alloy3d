#include "render_harness.h"
#include <alloy3d/visibility.h>
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: visibility_regression shaders.metallib fixtures");
      alloy3d::CameraData camera;
      alloy3d::Frustum3D  identity(camera);
      Check(identity.intersects({{1, 0, 0}, {2, 1, 1}}), "touching side plane was culled");
      Check(!identity.intersects({{1.01f, 0, 0}, {2, 1, 1}}), "outside side plane was visible");
      Check(!identity.intersects({{0, 0, -2}, {1, 1, -1}}), "Metal near clip plane was ignored");
      Check(identity.intersects({}), "unknown bounds should stay visible");
      camera.buildPerspective(.9f, 1, .1f, 50);
      camera.buildModelView({2, 3, 6}, {0, 0, 0}, {0, 1, 0});
      Check(alloy3d::Frustum3D(camera).intersects({{-1, -1, -1}, {1, 1, 1}}),
            "rotated camera lost target");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness                      h(device, argv[1]);
        auto                         root = std::filesystem::path(argv[2]);
        alloy3d::DirectionalShadow3D shadow;
        shadow.enabled = true;
        [h.draw setDirectionalShadow:shadow];
        [h.draw setTransparentBatching:true];
        for (const char *name : {"opaque_alpha", "mask_checker", "blend_parts", "animated_blend"})
        {
          auto model = h.Load(root / (std::string(name) + ".glb"));
          [model setAnimationTime:.6f];
          std::vector<Instance> instances;
          for (int i = 0; i < 60; ++i)
            instances.push_back({{float(i % 10) * 4 - 18, float(i / 10) * 3 - 7, 0},
                                 {0, float(i) * .1f, 0},
                                 {i % 2 ? -.9f : .9f, 1, 1},
                                 {1, 1, 1, 1}});
          for (bool instanced : {false, true})
          {
            auto submit = [&]
            {
              if (instanced)
                [h.draw drawModelInstances:model instances:instances];
              else
                for (auto &i : instances)
                  [h.draw drawModel:model
                           position:i.position
                           rotation:i.rotation
                              scale:i.scale
                              color:i.color];
            };
            [h.draw setFrustumCulling:false];
            auto reference = h.Run(camera, submit);
            auto shadows   = [h.draw shadowDrawCallCount];
            auto calls     = [h.draw modelDrawCallCount];
            [h.draw setFrustumCulling:true];
            Check(reference == h.Run(camera, submit), "culling changed visible pixels or shadows");
            Check([h.draw shadowDrawCallCount] == shadows, "culling removed shadow casters");
            Check([h.draw modelDrawCallCount] <= calls, "culling increased draw count");
            [h.draw setShadowCulling:true];
            Check(reference == h.Run(camera, submit), "light-frustum culling changed pixels");
            Check([h.draw shadowDrawCallCount] <= shadows, "shadow culling increased draw count");
            [h.draw setShadowCulling:false];
          }
          [model release];
        }
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
