#include "render_harness.h"
#include <alloy3d/lod.h>
int main(int argc,char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc==3,"usage: lod_regression shaders.metallib fixtures");
      std::array<float,2> thresholds={.5f,.2f};
      Check(alloy3d::SelectLod3D(1,thresholds).nearLevel==0,"large object lost detail");
      Check(alloy3d::SelectLod3D(.1f,thresholds).nearLevel==2,"small object retained full detail");
      auto mid=alloy3d::SelectLod3D(.5f,thresholds);
      Check(mid.nearLevel==0 && mid.farLevel==1 && std::abs(mid.farWeight-.5f)<1e-5f,"LOD midpoint incorrect");
      alloy3d::CameraData camera;camera.buildPerspective(1,1,.1f,100);
      float size=alloy3d::ProjectedHeight3D(camera,{0,0,-10},1);
      Check(std::abs(size-1.f/(10*std::tan(.5f)))<1e-5f,"invalid size");
      Check(std::abs(alloy3d::ProjectedHeight3D(camera,{0,0,-20},1)*2-size)<1e-5f,"size did not scale with depth");
      camera.buildOrthographic(10,1,.1f,100);
      Check(std::abs(alloy3d::ProjectedHeight3D(camera,{0,0,-20},1)-.2f)<1e-5f,"orthographic screen size incorrect");
      auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
      for (NSUInteger samples : {1u,4u})
      {
        Harness h(device,argv[1],256,samples);camera=alloy3d::CameraData();
        for(const char *name:{"opaque_alpha","mask_checker","blend_red"})
        {
          auto model=h.Load(std::filesystem::path(argv[2])/(std::string(name)+".glb"));
          for(bool custom:{false,true})
          {
            std::string error;auto shader=custom ? [h.draw createModelShader:"float3 alloy3dShade(ModelSurface s,float4 p){return s.litColor;}" diagnostics:error] : nullptr;
            Check(!custom || bool(shader),error.c_str());[h.draw setModelShader:shader parameters:{}];
            Instance base{{0,0,.4f},{},{1,1,1},{1,1,1,1}};
            auto full=h.Run(camera,[&]{[h.draw drawModelInstances:model instances:std::span(&base,1)];});
            for(float split:{0.f,.1f,.5f,.9f,1.f})
            {
              std::array<Instance,2> pair={base,base};pair[0].coverage={0,split};pair[1].coverage={split,1};
              for(bool batching:{false,true})
              {
                [h.draw setTransparentBatching:batching];
                Check(full==h.Run(camera,[&]{[h.draw drawModelInstances:model instances:pair];}),"complementary dither changed pixels");
              }
              Check(full==h.Run(camera,[&]{
                for(auto &i:pair){[h.draw setModelCoverage:i.coverage];[h.draw drawModel:model position:i.position rotation:i.rotation scale:i.scale color:i.color];}
                [h.draw setModelCoverage:(simd_float2{0,1})];
              }),"single-draw dither snapshot incorrect");
            }
            auto empty=h.Run(camera,[&]{[h.draw setModelCoverage:(simd_float2{0,0})];[h.draw drawModel:model position:base.position rotation:{} scale:base.scale color:base.color];});
            Check(std::all_of(empty.begin(),empty.end(),[](auto p){return p==0;}),"empty coverage drew pixels");
            [h.draw setModelCoverage:(simd_float2{0,1})];
          }
          [model release];
        }
        // Dither the caster as well as its visible surface; the receiver must not change.
        auto caster=h.Load(std::filesystem::path(argv[2])/"mask_checker.glb");
        camera.buildModelView({0,0,5},{0,0,0},{0,1,0});camera.buildOrthographic(4,1,.1f,20);
        [h.draw setModelShader:{} parameters:{}];
        [h.draw setDirectionalLight:(alloy3d::DirectionalLight3D{{.8f,0,-1},{1,1,1},.2f,.8f})];
        alloy3d::DirectionalShadow3D shadow;shadow.enabled=true;shadow.resolution=256;
        [h.draw setDirectionalShadow:shadow];
        Instance base{{-.3f,0,1},{},{.6f,.6f,.6f},{1,1,1,1}};
        auto submit=[&](std::span<const Instance> instances){
          [h.draw drawTriangle:{-2,-2,0} p1:{2,-2,0} p2:{2,2,0} color:{1,1,1,1}];
          [h.draw drawTriangle:{-2,-2,0} p1:{2,2,0} p2:{-2,2,0} color:{1,1,1,1}];
          [h.draw drawModelInstances:caster instances:instances];
        };
        auto full=h.Run(camera,[&]{submit(std::span(&base,1));});
        std::array<Instance,2> pair={base,base};pair[0].coverage={0,.375f};pair[1].coverage={.375f,1};
        Check(full==h.Run(camera,[&]{submit(pair);}),"dither changed shadow coverage");
        bool rejected=false;
        try{[h.draw setModelCoverage:(simd_float2{.8f,.2f})];}catch(const std::invalid_argument &){rejected=true;}
        Check(rejected,"reversed coverage accepted");
        [caster release];
      }
      [device release];return 0;
    }
    catch(const std::exception &e){std::fprintf(stderr,"FAIL: %s\n",e.what());return 1;}
  }
}
