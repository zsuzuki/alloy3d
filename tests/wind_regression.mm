#include "render_harness.h"
int main(int argc,char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc==3,"usage: wind_regression shaders.metallib fixtures");
      auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
      {
        Harness h(device,argv[1]);alloy3d::CameraData camera;
        auto root=std::filesystem::path(argv[2]);
        std::string error;auto shader=[h.draw createModelShader:
            "float3 alloy3dShade(ModelSurface s,float4 p){return s.normal*.5+.5;}" diagnostics:error];
        Check(bool(shader),error.c_str());
        for(const char *name:{"single_sided","mask_checker","mirrored_skin","animated_blend","wind_strip"})
        {
          auto model=h.Load(root/(std::string(name)+".glb"));[model setAnimationTime:.6f];
          for(bool custom:{false,true})
          {
            [h.draw setModelShader:custom ? shader : nullptr parameters:{}];
            Instance instance{{0,0,.4f},{},{.7f,.7f,.7f},{1,1,1,1}};
            auto submit=[&]{[h.draw drawModel:model position:instance.position rotation:instance.rotation scale:instance.scale color:instance.color];};
            [h.draw setModelWind:alloy3d::ModelWind3D{}];auto still=h.Run(camera,submit);
            alloy3d::ModelWind3D wind;wind.strength=.4f;wind.time=1;wind.tipHeight=1;
            [h.draw setModelWind:wind];auto bent=h.Run(camera,submit);
            Check(still!=bent,"wind did not deform model or normals");
            Check(bent==h.Run(camera,[&]{[h.draw drawModelInstances:model instances:std::span(&instance,1)];}),"instanced wind differs from scalar");
            [h.draw setTransparentBatching:true];
            Check(bent==h.Run(camera,submit),"wind changed with batching");
            [h.draw setFrustumCulling:true];
            Check(bent==h.Run(camera,submit),"wind bounds culled visible geometry");
            // A subdivided grid contains vertices along the anchor boundary.
            if (std::string(name)=="wind_strip") Check(std::equal(still.begin()+160*256,still.end(),bent.begin()+160*256),"wind moved anchored base");
            wind.baseHeight=100;wind.tipHeight=101;[h.draw setModelWind:wind];
            Check(still==h.Run(camera,submit),"wind below base was not identity");
            wind={};[h.draw setModelWind:wind];Check(still==h.Run(camera,submit),"wind disable did not restore model");
            wind.tipHeight=wind.baseHeight;
            bool rejected=false;try{[h.draw setModelWind:wind];}catch(const std::invalid_argument &){rejected=true;}
            Check(rejected && still==h.Run(camera,submit),"invalid wind mutated state");
          }
          [model release];
        }
        auto model=h.Load(root/"mask_checker.glb");
        camera.buildModelView({0,0,5},{0,0,0},{0,1,0});camera.buildOrthographic(4,1,.1f,20);
        [h.draw setModelShader:{} parameters:{}];
        [h.draw setDirectionalLight:(alloy3d::DirectionalLight3D{{.8f,0,-1},{1,1,1},.2f,.8f})];
        alloy3d::DirectionalShadow3D shadow;shadow.enabled=true;shadow.resolution=512;shadow.bounds={{-2,-2,-.2f},{2,2,2}};
        [h.draw setDirectionalShadow:shadow];
        Instance instance{{-.3f,0,1},{},{.8f,.8f,.8f},{1,1,1,1}};
        auto render=[&](float time,bool instanced){
          alloy3d::ModelWind3D wind;wind.strength=.7f;wind.time=time;[h.draw setModelWind:wind];
          return h.Run(camera,[&]{
            [h.draw drawTriangle:{-2,-2,0} p1:{2,-2,0} p2:{2,2,0} color:{1,1,1,1}];
          [h.draw drawTriangle:{-2,-2,0} p1:{2,2,0} p2:{-2,2,0} color:{1,1,1,1}];
            if(instanced)[h.draw drawModelInstances:model instances:std::span(&instance,1)];
            else[h.draw drawModel:model position:instance.position rotation:instance.rotation scale:instance.scale color:instance.color];
          });
        };
        auto first=render(0,false),next=render(1,false);
        Check(first!=next,"wind shadow scene did not animate");
        size_t shadowChanges=0;
        for(int y=60;y<130;++y)for(int x=164;x<208;++x)shadowChanges+=first[y*256+x]!=next[y*256+x];
        std::printf("wind shadow changed pixels: %zu\n",shadowChanges);
        Check(shadowChanges>20,"wind did not move the cast shadow");
        Check(next==render(1,true),"wind shadow differs between instance and scalar");
        Check(first==render(0,true),"wind phase depends on previous frame");
        [model release];
      }
      [device release];return 0;
    }
    catch(const std::exception &e){std::fprintf(stderr,"FAIL: %s\n",e.what());return 1;}
  }
}
