#include "render_harness.h"
int main(int argc,char **argv)
{
  @autoreleasepool {try {
    Check(argc==3,"usage: volumetric_regression shaders fixtures");auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
    for(NSUInteger samples:{1u,4u})
    {
      Harness h(device,argv[1],129,samples,true,true);alloy3d::CameraData camera;
      auto model=h.Load(std::filesystem::path(argv[2])/"unlit.glb");
      alloy3d::PostProcessing3D settings{1,alloy3d::ToneMapping3D::None};h.post->set(settings);
      auto submit=[&](int blocker){
        [h.draw setLightDirection:{0,0,1} ambient:0 diffuse:1];
        alloy3d::DirectionalShadow3D shadow;shadow.enabled=blocker==2;shadow.bounds={{-1,-1,-.5f},{1,1,1.5f}};shadow.resolution=256;
        [h.draw setDirectionalShadow:shadow];
        [h.draw setModelVisibility:(alloy3d::ModelVisibility3D{blocker!=2,true})];
        if(blocker)[h.draw drawModel:model position:{0,0,.3f} rotation:{0,blocker==2 ? 3.14159265f : 0.f,0} scale:{2,2,1} color:{0,0,0,1}];
        [h.draw setModelVisibility:alloy3d::ModelVisibility3D{}];
      };
      auto off=h.Run(camera,[&]{submit(0);});auto baseBytes=h.post->bytes();
      settings.volumetric={.5f,1,0,0,1,0,64};h.post->set(settings);
      auto clear=h.Run(camera,[&]{submit(0);}),blocked=h.Run(camera,[&]{submit(1);}),shadow=h.Run(camera,[&]{submit(2);});
      size_t center=64*129+64;
      Check(std::abs(int(clear[center]&255)-81)<=2,"volume integral differs from analytic extinction");
      Check(std::abs(int(blocked[center]&255)-33)<=2,"opaque depth failed to limit scattering distance");
      Check((shadow[center]&255)+20<(clear[center]&255),"shadow-only blocker did not occlude volumetric light");
      Check((clear[center]>>24)==(off[center]>>24),"volume changed scene alpha");
      Check(h.post->bytes()>baseBytes,"volume allocation missing from memory stats");
      settings.volumetric.strength=0;h.post->set(settings);Check(h.Run(camera,[&]{submit(0);})==off,"volume off failed to restore frame");
      h.post->releaseUnusedMemory();h.Run(camera,[&]{submit(0);});Check(h.post->bytes()==baseBytes,"volume target survived release and reuse");
      bool rejected=false;settings.volumetric.steps=0;try{h.post->set(settings);}catch(const std::invalid_argument &){rejected=true;}Check(rejected,"zero ray steps accepted");
      [model release];
    }
    [device release];return 0;
  }catch(const std::exception &e){fprintf(stderr,"FAIL: %s\n",e.what());return 1;}}
}
