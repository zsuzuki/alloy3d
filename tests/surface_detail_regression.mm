#include "render_harness.h"

int main(int argc, char **argv)
{
  @autoreleasepool
  {
    try
    {
      Check(argc==3,"usage: surface_detail_regression shaders.metallib fixtures");
      auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
      {
        Harness h(device,argv[1]);alloy3d::CameraData camera;
        auto root=std::filesystem::path(argv[2]);
        auto mapped=h.Load(root/"mapped.glb"), smooth=h.Load(root/"smooth.glb"), rough=h.Load(root/"rough.glb");
        auto texture=mapped.parts[0].roughnessTexture;
        Check(texture==mapped.parts[0].occlusionTexture,"packed texture was duplicated");
        Check(texture.pixelFormat==MTLPixelFormatRGBA8Unorm || texture.pixelFormat==MTLPixelFormatBGRA8Unorm,
              "material data was decoded as sRGB");
        auto submit=[&](MetalModel *m){[h.draw drawModel:m position:{0,0,.5f} rotation:{} scale:{1,1,1} color:{1,1,1,1}];};
        [h.draw setLightDirection:{0,0,-1} ambient:1 diffuse:0];
        const size_t center=128*256+128;
        auto baseline=h.Run(camera,[&]{submit(mapped);});
        [h.draw setModelMaterialDetail:{true}];
        auto ambient=h.Run(camera,[&]{submit(mapped);});
        Check((baseline[center]&255)==255 && std::abs(int(ambient[center]&255)-128)<2,"AO did not attenuate ambient linearly");
        [h.draw setLightDirection:{0,0,-1} ambient:0 diffuse:1];
        Check(h.Run(camera,[&]{submit(mapped);})[center]==baseline[center],"AO incorrectly attenuated direct light");
        std::string error;
        auto debug=[h.draw createModelShader:"float3 alloy3dShade(ModelSurface s,float4 p){return float3(s.roughness,s.occlusion,0);}" diagnostics:error];
        Check(bool(debug),error.c_str());[h.draw setModelShader:debug parameters:{}];
        auto values=h.Run(camera,[&]{submit(mapped);});
        Check(std::abs(int((values[center]>>16)&255)-51)<2 && std::abs(int((values[center]>>8)&255)-128)<2,"roughness/AO channels or factors wrong");
        auto spec=[h.draw createModelShader:"float3 alloy3dShade(ModelSurface s,float4 p){return s.specularColor;}" diagnostics:error];
        Check(bool(spec),error.c_str());[h.draw setModelShader:spec parameters:{}];
        [h.draw setModelHighlight:{.8f,32}];[h.draw setLightDirection:{-1,0,-1} ambient:0 diffuse:1];
        auto a=h.Run(camera,[&]{submit(smooth);}), b=h.Run(camera,[&]{submit(rough);});
        Check((b[center]&255)>(a[center]&255)+60,"roughness did not broaden highlight");
        [h.draw setModelMaterialDetail:{false}];
        Check(h.Run(camera,[&]{submit(smooth);})==h.Run(camera,[&]{submit(rough);}),"disabled detail changed legacy highlight");
        [h.draw setModelShader:debug parameters:{}];
        for(int slot=0;slot<3;++slot)
        {
          h.Begin(slot);[h.draw setModelMaterialDetail:{true}];submit(mapped);[h.draw setModelMaterialDetail:{false}];
          h.Encode(slot,camera);[h.commands[slot] commit];
          Check(h.Read(slot)==values,"material detail not captured across frames");
        }
        [h.draw setModelMaterialDetail:{true}];
        auto shared=[mapped newInstance];
        Check(shared.parts[0].roughnessTexture==texture && shared.parts[0].occlusionTexture==texture,"shared material copied textures");
        std::array<Instance,2> placements;
        placements[0]={{-.4f,0,.5f},{},{.6f,.6f,1},{1,1,1,1}};
        placements[1]={{.4f,0,.5f},{},{-.6f,.6f,1},{1,1,1,1}};
        auto individual=h.Run(camera,[&]{for(auto &i:placements)[h.draw drawModel:shared position:i.position rotation:i.rotation scale:i.scale color:i.color];});
        Check(individual==h.Run(camera,[&]{[h.draw drawModelInstances:shared instances:placements];}),"material detail instancing differs");
        for(auto m:{mapped,smooth,rough,shared})[m release];
      }
      [device release];std::puts("surface detail: AO, roughness, linear data, legacy disabled, frame snapshots and shared instances passed");return 0;
    }
    catch(const std::exception &e){std::fprintf(stderr,"FAIL: %s\n",e.what());return 1;}
  }
}
