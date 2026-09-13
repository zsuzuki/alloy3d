#include "render_harness.h"
int main(int argc,char **argv)
{
  @autoreleasepool {try {
    Check(argc==3,"usage: scene_depth_regression shaders fixtures");auto device=MTLCreateSystemDefaultDevice();if(!device)return 77;
    for(NSUInteger samples:{1u,4u})
    {
      Harness plain(device,argv[1],256,samples,true),h(device,argv[1],256,samples,true,true);
      h.post->set({1,alloy3d::ToneMapping3D::None});plain.post->set({1,alloy3d::ToneMapping3D::None});
      alloy3d::CameraData camera;auto red=h.Load(std::filesystem::path(argv[2])/"blend_red.glb");
      auto bg=h.Load(std::filesystem::path(argv[2])/"unlit.glb");
      auto render=[&](Harness &target,float distance,bool background=true,bool particles=true)
      {
        return target.Run(camera,[&]{
          [target.draw setLightDirection:{0,0,-1} ambient:1 diffuse:0];
          [target.draw setModelSoftParticles:distance];
          if(background)[target.draw drawModel:bg position:{0,0,.6f} rotation:{} scale:{1,1,1} color:{0,0,1,1}];
          if(particles)[target.draw drawModel:red position:{0,0,.5f} rotation:{} scale:{1,1,1} color:{1,1,1,1}];
        });
      };
      auto full=render(h,0);Check(full==render(plain,0),"split passes changed disabled pixels");
      auto softened=render(h,.2f),background=render(h,0,true,false);
      auto center=128*256+128;int rFull=(full[center]>>16)&255,rSoft=(softened[center]>>16)&255;
      Check(rFull>20 && std::abs(rSoft*2-rFull)<=2,"soft intersection did not halve particle contribution");
      Check(render(h,.2f,false)==render(h,0,false),"clear depth faded particles");
      Check(render(h,.2f,true,false)==background,"soft particles altered opaque material");
      Check(render(h,0)==full,"soft particle off did not restore pixels");
      // Culling compaction and transparent batching share GPU pages across both phases.
      [h.draw setFrustumCulling:true];[h.draw setTransparentBatching:true];
      auto batches=[&](bool cull){[h.draw setFrustumCulling:cull];return h.Run(camera,[&]{
        [h.draw setModelSoftParticles:0];
        std::vector<Instance> placements(3);placements[0].position={0,0,.6f};placements[1].position={5,0,.6f};placements[2].position={-.5f,0,.6f};
        [h.draw drawModelInstances:bg instances:placements];
        [h.draw drawModel:red position:{0,0,.5f} rotation:{} scale:{1,1,1} color:{1,1,1,1}];
        [h.draw drawModel:red position:{.5f,0,.4f} rotation:{} scale:{1,1,1} color:{1,1,1,1}];
      });};
      Check(batches(true)==batches(false),"phase buffer reuse corrupted visible instances");
      Check(h.post->bytes()>plain.post->bytes(),"scene snapshot missing from memory accounting");
      h.post->releaseUnusedMemory();Check(render(h,0)==full,"snapshot release changed pixels");
      bool invalid=false;try{[h.draw setModelSoftParticles:-1];}catch(const std::invalid_argument &){invalid=true;}Check(invalid,"invalid soft distance accepted");
      [red release];[bg release];
    }
    [device release];return 0;
  } catch(const std::exception &e){fprintf(stderr,"FAIL: %s\n",e.what());return 1;}}
}
