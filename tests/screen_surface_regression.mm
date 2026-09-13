#include "render_harness.h"
int main(int argc,char **argv)
{
  @autoreleasepool {try{
    Check(argc==3,"usage: screen_surface_regression shaders fixtures");auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
    for(NSUInteger samples:{1u,4u})
    {
      Harness h(device,argv[1],256,samples,true,true);h.post->set({1,alloy3d::ToneMapping3D::None});
      auto model=h.Load(std::filesystem::path(argv[2])/"unlit.glb");alloy3d::CameraData camera;std::string error;
      auto shader=[h.draw createModelMaterialShader:"ModelMaterial alloy3dMaterial(ModelMaterial m, ModelMaterialContext c,float4 p){m.normal=normalize(float3(.9238795,0,-.3826834));return m;}" diagnostics:error];Check(bool(shader),error.c_str());
      auto run=[&](alloy3d::ModelScreenSpace3D settings,bool centered){return h.Run(camera,[&]{
        [h.draw setModelShader:{} parameters:{}];[h.draw setModelScreenSpace:alloy3d::ModelScreenSpace3D{}];
        [h.draw drawModel:model position:{centered ? 0.f : .6f,0,.8f} rotation:{} scale:{centered ? 2.f : .6f,2,1} color:{1,0,0,1}];
        [h.draw setModelShader:shader parameters:{}];[h.draw setModelScreenSpace:settings];
        [h.draw drawModel:model position:{0,0,.2f} rotation:{} scale:{1,1,1} color:{0,0,1,.9f}];
      });};
      auto baseline=run({},true),refracted=run({1,0,0,1.8f,.15f},true);size_t center=128*256+128;
      Check(((refracted[center]>>16)&255)>((baseline[center]>>16)&255)+30,"refraction did not use opaque scene color");
      Check((refracted[center]&255)<(baseline[center]&255),"refraction retained surface instead of background");
      auto noReflection=run({},false),reflection=run({0,0,1,1.8f,.15f},false);
      Check(((reflection[center]>>16)&255)>((noReflection[center]>>16)&255)+1,"reflected ray missed known off-axis opaque surface");
      Check(run({0,0,1,.1f,.15f},false)==noReflection,"short ray unexpectedly reached reflected object");
      Check(run({},true)==baseline,"screen effect off did not restore surface");
      bool rejected=false;try{[h.draw setModelScreenSpace:(alloy3d::ModelScreenSpace3D{0,0,1,0,.1f})];}catch(const std::invalid_argument &){rejected=true;}Check(rejected,"invalid ray distance accepted");
      [model release];
    }
    [device release];return 0;
  }catch(const std::exception &e){fprintf(stderr,"FAIL: %s\n",e.what());return 1;}}
}
