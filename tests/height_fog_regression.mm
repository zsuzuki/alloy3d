#include "render_harness.h"
#include <limits>

int main(int argc,char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc==3,"usage: height_fog_regression shaders.metallib material-fixtures");
      auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
      {
        Harness h(device,argv[1]);alloy3d::CameraData camera;
        camera.buildOrthographic(8,1,.1f,30);
        camera.buildModelView({0,0,10},{0,0,0},{0,1,0});
        [h.draw setLightDirection:{0,0,-1} ambient:1 diffuse:0];
        alloy3d::HeightFog3D fog{true,{0,0,0},.1f,0,.7f,1};
        auto plane=[&]{[h.draw drawPlane:{-4,-4,0} p1:{4,-4,0} p2:{4,4,0} p3:{-4,4,0} color:{1,1,1,1}];};
        auto baseline=h.Run(camera,plane);[h.draw setHeightFog:fog];auto result=h.Run(camera,plane);
        Check((result[192*256+128]&255)+50<(result[64*256+128]&255),"fog did not become denser at lower world height");
        int expected=std::round(255*std::exp(-.1f*10));
        Check(std::abs(int(result[128*256+128]&255)-expected)<3,"horizontal ray did not integrate exponential density");
        // Rotate the camera and put the same world point at the center; world up must not rotate with it.
        camera.buildModelView({0,5,10},{0,0,0},{0,1,0});
        auto tilted=h.Run(camera,plane);
        double span=5*.7, integral=(1-std::exp(-span))/span;
        expected=std::round(255*std::exp(-.1*std::sqrt(125.)*integral));
        Check(std::abs(int(tilted[128*256+128]&255)-expected)<4,"height fog used camera-space height");
        fog.falloff=0;fog.maxOpacity=.3f;[h.draw setHeightFog:fog];
        Check(std::abs(int(h.Run(camera,plane)[128*256+128]&255)-179)<2,"fog opacity limit failed");
        for(auto invalid:{-1.f,std::numeric_limits<float>::quiet_NaN()})
        {
          auto bad=fog;bad.density=invalid;bool rejected=false;
          try{[h.draw setHeightFog:bad];}catch(const std::invalid_argument&){rejected=true;}
          Check(rejected,"invalid height fog accepted");
        }
        [h.draw setHeightFog:{}];camera.buildModelView({0,0,10},{0,0,0},{0,1,0});
        Check(baseline==h.Run(camera,plane),"height fog off changed baseline");
        fog={true,{.2f,.3f,.4f},.03f,0,.5f,.8f};[h.draw setHeightFog:fog];
        std::string error;auto shader=[h.draw createModelShader:
            "float3 alloy3dShade(ModelSurface s,float4 p){return s.litColor;}" diagnostics:error];
        Check(bool(shader),error.c_str());
        for(const char *name:{"opaque_alpha","mask_checker","blend_red","unlit"})
        {
          auto model=h.Load(std::filesystem::path(argv[2])/(std::string(name)+".glb"));
          auto submit=[&]{[h.draw drawModel:model position:{} rotation:{} scale:{2,2,2} color:{1,1,1,1}];};
          [h.draw setModelShader:{} parameters:{}];auto standard=h.Run(camera,submit);
          [h.draw setModelShader:shader parameters:{}];Check(standard==h.Run(camera,submit),"custom fog differs");
          Instance placement{{},{},{2,2,2},{1,1,1,1}};
          Check(standard==h.Run(camera,[&]{[h.draw drawModelInstances:model instances:std::span(&placement,1)];}),"instanced fog differs");
          [h.draw setHeightFog:{}];auto off=h.Run(camera,submit);[h.draw setHeightFog:fog];
          for(size_t i=0;i<off.size();++i)Check((off[i]>>24)==(standard[i]>>24),"height fog changed material alpha");
          [model release];
        }
      }
      [device release];std::puts("height fog: integral, world up, cap, off, invalid input, custom/material/instance alpha passed");return 0;
    }
    catch(const std::exception &e){std::fprintf(stderr,"FAIL: %s\n",e.what());return 1;}
  }
}
