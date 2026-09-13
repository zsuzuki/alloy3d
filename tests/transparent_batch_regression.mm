#include "render_harness.h"

int main(int argc,char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc==3,"usage: transparent_batch_regression shaders.metallib material-fixtures");
      auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
      {
        Harness h(device,argv[1]);alloy3d::CameraData camera;
        auto root=std::filesystem::path(argv[2]);auto opaque=h.Load(root/"opaque_alpha.glb");
        auto blue=h.Load(root/"blend_blue.glb");
        std::vector<Instance> instances(300);
        for(size_t i=0;i<instances.size();++i)
          instances[i]={{float(i%20)*.07f-.7f,float(i/20)*.08f-.6f,.2f+float(i%17)*.03f},
                        {0,0,float(i)*.03f},{i%2 ? -.16f : .16f,.16f,1},{1,.8f,1,.6f}};
        std::string error;auto shader=[h.draw createModelShader:
            "float3 alloy3dShade(ModelSurface s,float4 p){return s.litColor*p.rgb;}" diagnostics:error];
        Check(bool(shader),error.c_str());
        alloy3d::DirectionalShadow3D shadow;shadow.enabled=true;[h.draw setDirectionalShadow:shadow];
        [h.draw setFog:(alloy3d::Fog3D{true,{.3f,.4f,.5f},0,8})];
        for(const char *name:{"blend_red","blend_lit","blend_parts","opaque_alpha","mask_checker","animated_blend"})
        {
          auto model=h.Load(root/(std::string(name)+".glb"));[model setAnimationTime:.4f];
          for(bool custom:{false,true})
          {
            auto submit=[&]{
              // Opaque instances exercise buffer growth after the shadow encoder references it.
              [h.draw setModelShader:{} parameters:{}];
              Instance base{{0,0,.8f},{},{1.5f,1.5f,1},{1,1,1,1}};
              [h.draw drawModelInstances:opaque instances:std::span(&base,1)];
              [h.draw setModelShader:custom ? shader : nullptr parameters:{.8f,1,.6f,1}];
              [h.draw setModelHighlight:{.2f,40}];
              [h.draw setModelTransmission:(alloy3d::ModelTransmission3D{.1f,{1,.8f,.3f}})];
              [h.draw setModelTextureSampling:{8}];
              [h.draw setModelTextureTransform:(alloy3d::ModelTextureTransform3D{{1.4f,.8f},{.12f,.2f}})];
              [h.draw drawModelInstances:model instances:instances];
              [h.draw drawModel:blue position:{0,0,.45f} rotation:{} scale:{.8f,.8f,1} color:{1,1,1,1}];
            };
            [h.draw setTransparentBatching:false];auto reference=h.Run(camera,submit);auto scalar=[h.draw modelDrawCallCount];
            [h.draw setTransparentBatching:true];auto batched=h.Run(camera,submit);auto calls=[h.draw modelDrawCallCount];
            Check(reference==batched,"transparent batching changed sorted composite");
            Check(calls<=scalar,"transparent batching increased draw count");
            if(model.parts.count==1)Check(calls<20,"single-part transparency did not batch around intervening model");
            std::printf("%s custom=%d draws %lu -> %lu\n",name,custom,(unsigned long)scalar,(unsigned long)calls);
          }
          [model release];
        }
        // Different shader parameters at identical depth must remain separate and ordered.
        auto submitStyles=[&]{
          for(int i=0;i<4;++i)
          {
            [h.draw setModelShader:shader parameters:(simd_float4{i%2 ? 1.f : 0.f,0,i%2 ? 0.f : 1.f,1})];
            [h.draw drawModel:blue position:{0,0,.4f} rotation:{} scale:{1,1,1} color:{1,1,1,.5f}];
          }
        };
        [h.draw setTransparentBatching:false];auto reference=h.Run(camera,submitStyles);
        [h.draw setTransparentBatching:true];Check(reference==h.Run(camera,submitStyles),"batch mixed shader parameters");
        Check([h.draw modelDrawCallCount]==4,"incompatible styles were merged");
        [opaque release];[blue release];
      }
      [device release];return 0;
    }
    catch(const std::exception &e){std::fprintf(stderr,"FAIL: %s\n",e.what());return 1;}
  }
}
