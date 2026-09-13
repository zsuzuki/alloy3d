#include "render_harness.h"
int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc == 3, "usage: material_shader_regression shaders.metallib fixtures");
      auto device = MTLCreateSystemDefaultDevice();
      if (!device)
        return 77;
      {
        Harness             h(device, argv[1]);
        alloy3d::CameraData camera;
        auto                root = std::filesystem::path(argv[2]);
        std::string         error;
        auto                identity =
            [h.draw createModelMaterialShader:"ModelMaterial alloy3dMaterial(ModelMaterial "
                                              "m,ModelMaterialContext c,float4 p){return m;}"
                                  diagnostics:error];
        Check(bool(identity), error.c_str());
        auto edit = [h.draw
            createModelMaterialShader:
                "ModelMaterial alloy3dMaterial(ModelMaterial m,ModelMaterialContext c,float4 "
                "p){m.baseColor=p.rgb;m.normal=float3(0,1,0);m.occlusion=.5;m.emissive=float3(.1,0,"
                "0);return m;}"
                          diagnostics:error];
        Check(bool(edit), error.c_str());
        [h.draw setDirectionalLight:(alloy3d::DirectionalLight3D{{0, 0, -1}, {1, 1, 1}, .2f, .8f})];
        for (const char *name :
             {"single_sided", "mask_checker", "blend_lit", "mirrored_skin", "animated_blend"})
        {
          auto model = h.Load(root / (std::string(name) + ".glb"));
          [model setAnimationTime:.4f];
          auto submit = [&]
          {
            [h.draw drawModel:model
                     position:{0, 0, .2f}
                     rotation:{}
                        scale:{1, 1, 1}
                        color:{1, 1, 1, 1}];
          };
          [h.draw setModelShader:{} parameters:{}];
          auto reference = h.Run(camera, submit);
          [h.draw setModelShader:identity parameters:{}];
          Check(reference == h.Run(camera, submit),
                "identity material hook changed built-in shading");
          [h.draw setModelShader:edit parameters:{1, 1, 1, 0}];
          auto modified = h.Run(camera, submit);
          Check(reference != modified, "material hook did not affect lighting");
          Instance instance{{0, 0, .2f}, {}, {1, 1, 1}, {1, 1, 1, 1}};
          Check(modified ==
                    h.Run(camera,
                          [&]
                          { [h.draw drawModelInstances:model instances:std::span(&instance, 1)]; }),
                "material hook differs in instances");
          if (std::string(name) == "single_sided")
          {
            auto p = modified[128 * 256 + 128];
            Check(std::abs(int((p >> 16) & 255) - 51) <= 2 &&
                      std::abs(int((p >> 8) & 255) - 26) <= 2,
                  "material normal/AO/emissive did not feed shared lighting");
            alloy3d::Fog3D fog{true, {0, 0, 0}, 0, .4f};
            [h.draw setFog:fog];
            // Identity projection points in +Z, so use a real camera to verify post-light fog.
            camera.buildModelView({0, 0, 2}, {0, 0, 0}, {0, 1, 0});
            camera.buildOrthographic(2, 1, .1f, 10);
            auto fogged = h.Run(camera, submit);
            Check((fogged[128 * 256 + 128] & 0xffffff) == 0, "emissive bypassed fog");
            camera = alloy3d::CameraData();
            [h.draw setFog:alloy3d::Fog3D{}];
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
