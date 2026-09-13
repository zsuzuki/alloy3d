#pragma once
#include <algorithm>
#include <alloy3d/camera.h>
#include <alloy3d/lighting.h>
#include <alloy3d/lod.h>
#include <alloy3d/model_instance.h>
#include <alloy3d/model_texture.h>
#include <array>
#include <cmath>
#include <cstdint>
#include <span>
#include <vector>

namespace forest
{
// All colors are linear RGB. Layout is deterministic, shared by app and probe.
inline constexpr simd_float3                  SkyColor         = {.22f, .43f, .68f};
inline constexpr simd_float3                  MistColor        = {.36f, .45f, .39f};
inline constexpr size_t                       DropletDensity   = 100;
inline constexpr size_t                       BankEmitters     = 72;
inline constexpr size_t                       BaseEmitters     = BankEmitters + 8;
inline constexpr size_t                       DropletCapacity  = BaseEmitters * DropletDensity;
inline constexpr float                        DropletSpacing   = 1.2f;
inline constexpr float                        DropletFadeStart = 10.f;
inline constexpr float                        DropletFadeEnd   = 20.f;
inline constexpr float                        DropletScale     = .75f;
inline constexpr simd_float3                  DropletTint      = {.40f, .52f, .50f};
inline constexpr std::array<const char *, 50> Assets           = {
    "ground",        "tree",          "leaves",        "grass",         "fern",
    "rock",          "beam",          "mote",          "water",         "tree_2",
    "leaves_2",      "tree_3",        "leaves_3",      "crown",         "crown_2",
    "crown_3",       "crown_lod",     "crown_lod_2",   "crown_lod_3",   "leaves_lod",
    "leaves_lod_2",  "leaves_lod_3",  "billboard_1_0", "billboard_1_1", "billboard_1_2",
    "billboard_1_3", "billboard_1_4", "billboard_1_5", "billboard_1_6", "billboard_1_7",
    "billboard_2_0", "billboard_2_1", "billboard_2_2", "billboard_2_3", "billboard_2_4",
    "billboard_2_5", "billboard_2_6", "billboard_2_7", "billboard_3_0", "billboard_3_1",
    "billboard_3_2", "billboard_3_3", "billboard_3_4", "billboard_3_5", "billboard_3_6",
    "billboard_3_7", "billboard_1_0", "billboard_2_0", "billboard_3_0", "droplet"};
enum Asset : size_t
{
  Ground,
  Tree,
  Leaves,
  Grass,
  Fern,
  Rock,
  Beam,
  Mote,
  Water,
  Tree2,
  Leaves2,
  Tree3,
  Leaves3,
  Crown,
  Crown2,
  Crown3,
  CrownLod,
  CrownLod2,
  CrownLod3,
  LeavesLod,
  LeavesLod2,
  LeavesLod3,
  BillboardBegin,
  ThicketBegin = BillboardBegin + 24,
  Droplet      = ThicketBegin + 3
};
inline constexpr Asset BillboardAsset(size_t variant, int view)
{
  return static_cast<Asset>(BillboardBegin + variant * 8 + view);
}
inline constexpr bool IsBillboard(size_t asset)
{
  return asset >= BillboardBegin && asset < ThicketBegin;
}
inline constexpr std::array<Asset, 3> Trunks         = {Tree, Tree2, Tree3};
inline constexpr std::array<Asset, 3> Crowns         = {Crown, Crown2, Crown3};
inline constexpr std::array<Asset, 3> Foliage        = {Leaves, Leaves2, Leaves3};
inline constexpr std::array<Asset, 3> DistantCrowns  = {CrownLod, CrownLod2, CrownLod3};
inline constexpr std::array<Asset, 3> DistantFoliage = {LeavesLod, LeavesLod2, LeavesLod3};
inline constexpr bool                 IsFoliage(size_t asset)
{
  return asset == Leaves || asset == Leaves2 || asset == Leaves3 || asset == LeavesLod ||
         asset == LeavesLod2 || asset == LeavesLod3 || asset == Fern || asset == Grass;
}
inline constexpr const char *GroundShader = R"metal(
float3 alloy3dShade(ModelSurface s, float4 p)
{
  float2 q = s.texcoord * 2.4 + float2(sin(p.x * .19), cos(p.x * .16)) * .13;
  float fleck = sin(q.x * 2.1 + sin(q.y * 1.8)) * sin(q.y * 2.7 + cos(q.x));
  float pools = smoothstep(.18, .8, sin(q.x * .32 + q.y * .23));
  float sun = smoothstep(.1, .72, fleck) * pools * p.y;
  return s.litColor * (.88 + sun * 1.15) + s.baseColor * float3(1.0, .88, .48) * sun * s.shadow * .85;
}
)metal";
inline constexpr const char *LeafShader   = R"metal(
float3 alloy3dShade(ModelSurface s, float4 p)
{
  // Directional thin-surface lighting is supplied by the library.
  return s.litColor;
}
)metal";

inline constexpr const char *WaterShader = R"metal(
float3 alloy3dShade(ModelSurface s, float4 p)
{
  float2 uv = s.texcoord;
  // UVs follow the river bends. Derivatives put ripple slopes into view space.
  float3 dx=dfdx(s.viewPosition), dy=dfdy(s.viewPosition);
  float2 tx=dfdx(uv), ty=dfdy(uv);
  float det=tx.x*ty.y-tx.y*ty.x;
  float3 n=s.normal;
  if (abs(det)>1e-10)
  {
    float3 tangent=normalize((dx*ty.y-dy*tx.y)/det);
    float3 bitangent=normalize((dy*tx.x-dx*ty.x)/det);
    float a=6.2831853*(uv.x*7+uv.y*3);
    float b=6.2831853*(uv.x*3-uv.y*5)+p.x*.31;
    // The library's normal map supplies detail independently of reflected color.
    float sx=.015*cos(a);
    float sy=.010*cos(b);
    n=normalize(n-tangent*sx-bitangent*sy);
  }
  float facing=saturate(dot(n,s.viewDirection));
  float fresnel=.025+.72*pow(1-facing,5.0);
  float pattern=dot(s.baseColor,float3(.2126,.7152,.0722));
  float3 bed=mix(float3(.055,.105,.075),float3(.12,.22,.17),saturate(pattern*2));
  float3 reflection=float3(.30,.48,.56);
  float3 color=mix(s.baseColor*.90+bed*.10,reflection,fresnel*.65);
  float3 halfway=s.lightDirection+s.viewDirection;
  float h2=dot(halfway,halfway);
  float glint=h2>1e-8 ? pow(saturate(dot(n,halfway*rsqrt(h2))),100.0) : 0;
  // Broken pale streaks carried downstream by the same UV transform as the texture.
  float crest=smoothstep(.20,.50,pattern)*.07;
  float light=.50+.50*s.shadow;
  return color*light + float3(.48,.65,.59)*crest*light
      + s.lightColor*glint*s.lightIntensity*s.shadow*.9;
}
)metal";

inline float StreamCenter(float z)
{
  return 4.6f + 1.15f * std::sin(z * .14f) + .35f * std::sin(z * .37f);
}
inline float StreamWidth(float z) { return .90f + .18f * std::sin(z * .23f + .7f); }
inline float WaterLevel(float z) { return -.27f - .008f * z; }
inline float Smooth(float a, float b, float x)
{
  float t = std::clamp((x - a) / (b - a), 0.f, 1.f);
  return t * t * (3 - 2 * t);
}
inline float Height(float x, float z)
{
  float base    = .22f * std::sin(x * .31f + z * .13f) + .16f * std::cos(z * .37f - x * .12f) +
                  .10f * std::sin(x * .83f + z * .49f);
  float d       = std::abs(x - StreamCenter(z)) / StreamWidth(z);
  float channel = WaterLevel(z) - .32f + .52f * Smooth(.6f, 1.6f, d);
  float blend   = Smooth(1.6f, 2.6f, d);
  float rise    = 7.5f * std::max(Smooth(55, 92, -z), Smooth(28, 60, std::abs(x)));
  return channel * (1 - blend) + base * blend + rise;
}

// Root tips reach up to 2.1 model units from the trunk. Sample the whole footprint,
// not just its center, so low banks and uneven ground cannot leave roots suspended.
inline float TreeBaseHeight(float x, float z, float scale)
{
  float y = Height(x, z);
  for (float radius : {.7f, 1.4f, 2.1f})
    for (int i = 0; i < 64; ++i)
    {
      float a = i * 6.28318530718f / 64;
      y = std::min(y, Height(x + std::cos(a) * radius * scale, z + std::sin(a) * radius * scale));
    }
  return y - .12f * scale;
}

struct Settings
{
  bool wind = true, fog = true, shafts = true, shadows = true, paused = false, hud = true,
       flow = true, billboards = true, droplets = true, normalMaps = true, materialDetail = true,
       transmission = true, heightFog = true;
};

class Scene
{
  struct DropEmitter
  {
    float z, across, inward, speed, lift, radius, period, phase;
  };
  std::vector<DropEmitter>                                       drops_;
  size_t                                                         treeCount_ = 0;
  uint32_t                                                       seed_      = 0x197307;
  std::array<std::vector<alloy3d::ModelInstance>, Assets.size()> base_, live_;
  std::vector<alloy3d::ModelInstance> lodWood_, lodLeaves_;
  float                                                          Random(float low, float high)
  {
    seed_ = seed_ * 1664525u + 1013904223u;
    return low + (high - low) * float(seed_ >> 8) / 16777216.f;
  }
  void Place(Asset asset, simd_float3 position, simd_float3 scale, float yaw = 0,
             simd_float4 color = {1, 1, 1, 1})
  {
    base_[asset].push_back({position, {0, yaw, 0}, scale, color});
  }
  void PlantTree(float x, float z, float scale, float yaw)
  {
    // Keep trunks and their roots on the banks, shifting only riverside placements.
    float dx = x - StreamCenter(z), clearance = StreamWidth(z) + 1.5f * scale;
    if (std::abs(dx) < clearance)
      x = StreamCenter(z) + (dx < 0 ? -clearance : clearance);
    float  y       = TreeBaseHeight(x, z, scale);
    size_t variant = treeCount_++ % Trunks.size();
    Place(Trunks[variant], {x, y, z}, {scale, scale, scale}, yaw);
    Place(Crowns[variant], {x, y + 4.f * scale, z}, {scale, scale, scale}, yaw);
    Place(Foliage[variant], {x, y + 4.f * scale, z}, {scale, scale, scale}, yaw);
    // Keep the existing forest layout stable: the old seven leaf clumps consumed 35 values.
    for (int i = 0; i < 35; ++i)
      Random(0, 1);
  }

public:
  Settings settings;
  float    waterTime = 0;
  float    time = 0, yaw = 0, pitch = .045f, travel = 0;

  Scene()
  {
    Place(Ground, {0, 0, 0}, {1, 1, 1});
    Place(Water, {0, 0, 0}, {1, 1, 1});
    for (int z = -58; z <= 12; z += 6)
      for (int x = -27; x <= 27; x += 6)
      {
        float px = x + Random(-2, 2), pz = z + Random(-2, 2);
        if (std::abs(px - 1.7f * std::sin(pz * .12f)) < 3.1f)
          continue;
        PlantTree(px, pz, Random(.75f, 1.5f), Random(0, 6.283f));
      }
    PlantTree(-5.3f, 5, 1.42f, .7f);
    PlantTree(6.5f, 1, 1.5f, 2.1f);
    for (int i = 0; i < 2700; ++i)
    {
      float x = Random(-30, 30), z = Random(-58, 18);
      float path = std::abs(x - 1.7f * std::sin(z * .12f));
      if (path < 1.1f || (path < 2 && Random(0, 1) < .7f))
        continue;
      float size = Random(.55f, 1.5f);
      Place(Grass,
            {x, Height(x, z), z},
            {size, size, size},
            Random(0, 6.283f),
            {Random(.65f, 1.1f), Random(.8f, 1.15f), Random(.65f, 1), 1});
      if (std::abs(x - StreamCenter(z)) < StreamWidth(z) + .28f)
        base_[Grass].pop_back();
    }
    for (int i = 0; i < 520; ++i)
    {
      float x = Random(-25, 25), z = Random(-50, 17);
      if (std::abs(x - 1.7f * std::sin(z * .12f)) < 1.5f)
        continue;
      float size = Random(.65f, 1.6f);
      Place(Fern, {x, Height(x, z), z}, {size, size, size}, Random(0, 6.283f));
      if (std::abs(x - StreamCenter(z)) < StreamWidth(z) + .65f * size)
        base_[Fern].pop_back();
    }
    for (int i = 0; i < 130; ++i)
    {
      float x = Random(-25, 25), z = Random(-50, 16), size = Random(.3f, 1.3f);
      if (std::abs(x - 1.7f * std::sin(z * .12f)) < 1.1f)
        continue;
      Place(Rock,
            {x, Height(x, z) + size * .22f, z},
            {size, Random(.6f, 1.1f) * size, size},
            Random(0, 6.283f));
      if (std::abs(x - StreamCenter(z)) < StreamWidth(z) + size * .65f)
        base_[Rock].pop_back();
    }
    // Selected gaps, with the same travel direction as the directional light.
    for (auto point : {simd_float3{-2, 0, -6},
                       {1.5f, 0, -10},
                       {4, 0, -18},
                       {-4, 0, -23},
                       {0, 0, -31},
                       {2, 0, 1}})
    {
      point.y = Height(point.x, point.z);
      Place(Beam, point, {1, 1, 1});
    }
    for (int i = 0; i < 65; ++i)
    {
      float size = Random(.012f, .032f);
      Place(Mote, {Random(-8, 8), Random(.5f, 7), Random(-25, 10)}, {size, size, size});
    }
    // Small wet stones along both banks, with a few exposed stones in the channel.
    for (int i = 0; i < 100; ++i)
    {
      float z = Random(-58, 20), side = i % 2 ? 1.f : -1.f, size = Random(.12f, .38f);
      float x = StreamCenter(z) + side * StreamWidth(z) * Random(.98f, 1.45f);
      Place(Rock, {x, Height(x, z) + size * .2f, z}, {size, size * .7f, size}, Random(0, 6.283f));
    }
    for (float z : {-19.f, -7.f, 2.f, 9.f})
    {
      float x = StreamCenter(z) + .3f * StreamWidth(z);
      Place(Rock, {x, WaterLevel(z) - .09f, z}, {.28f, .35f, .42f}, .3f);
    }
    // Extend the forest behind the original clearing. These trees use the far crown level.
    for (int row = 0; row < 3; ++row)
      for (int col = -7; col <= 7; ++col)
      {
        float x = col * 7.2f + (row % 2) * 3.1f + Random(-1.3f, 1.3f);
        float z = -66.f - row * 10.f + Random(-1, 1);
        PlantTree(x, z, Random(.85f, 1.25f), Random(0, 6.283f));
      }
    // Low foliage in staggered layers covers gaps between distant trunks. It reuses
    // crown images, kept separate from tree LOD groups and hidden behind the near forest.
    for (int row = 0; row < 3; ++row)
      for (int col = -11; col <= 11; ++col)
      {
        float x = col * 5.f + (row % 2) * 2.5f, z = -61.f - row * 11.f;
        float size  = Random(.48f, .72f);
        auto  asset = static_cast<Asset>(ThicketBegin + (col + row + 33) % 3);
        Place(asset,
              {x, Height(x, z) - 1.4f * size, z},
              {size, size * .9f, size},
              0,
              {.68f, .78f, .64f, 1});
      }
    for (int side : {-1, 1})
      for (int row = 0; row < 2; ++row)
        for (int i = 0; i < 16; ++i)
        {
          float x = side * (35.f + row * 9.f), z = 18.f - i * 5.f + (row % 2) * 2.5f;
          float size  = Random(.55f, .8f);
          auto  asset = static_cast<Asset>(ThicketBegin + (i + row) % 3);
          Place(asset,
                {x, Height(x, z) - 1.4f * size, z},
                {size, size, size},
                0,
                {.68f, .78f, .64f, 1});
        }
    // Fixed slots avoid per-frame emission/allocation growth. Add these last so the
    // random sequence and placement of the existing forest stay unchanged.
    for (size_t i = 0; i < BankEmitters; ++i)
    {
      float side = i % 2 ? 1.f : -1.f;
      drops_.push_back({-44.f + (i / 2) * 1.8f + Random(-.3f, .3f),
                        side * Random(.83f, .92f),
                        -side * Random(.10f, .24f),
                        Random(.32f, .58f),
                        Random(.736f, 1.152f),
                        Random(.011f, .019f),
                        Random(1.2f, 2.8f),
                        Random(0, 8)});
    }
    for (float z : {-19.f, -7.f, 2.f, 9.f})
      for (int i = 0; i < 2; ++i)
        drops_.push_back({z + .50f,
                          .3f + (i ? .18f : -.18f),
                          i ? .10f : -.10f,
                          Random(.35f, .60f),
                          Random(.8f, 1.12f),
                          Random(.013f, .018f),
                          Random(1.4f, 2.5f),
                          Random(0, 8)});
    // Three occasional higher-hop patterns: left bank, right bank, and a stone.
    // Override before copying so the other 77 patterns and random sequence stay intact.
    drops_[8].lift  = 1.46f; // Peak about 12cm above the water.
    drops_[19].lift = 1.58f; // Peak about 14cm.
    drops_[76].lift = 1.70f; // Peak about 16cm.
    // Keep the sparse background. Extra bank emitters occupy a denser world-space
    // lattice around the camera; stone emitters stay attached to their stones.
    const size_t emitterCount = drops_.size();
    for (size_t layer = 1; layer < DropletDensity; ++layer)
      for (size_t i = 0; i < emitterCount; ++i)
      {
        auto emitter = drops_[i];
        emitter.phase += emitter.period * float(layer) / float(DropletDensity);
        if (i < BankEmitters)
          emitter.z = float(i / 2) * DropletSpacing;
        // Dense copies need slightly different launch sites to remain a spray
        // instead of tracing the same bright arc with overlapping droplets.
        emitter.z += i < BankEmitters ? Random(-.5f, .5f) : Random(-.24f, .24f);
        emitter.across += Random(-.035f, .035f);
        drops_.push_back(emitter);
      }
    live_ = base_;
    live_[Droplet].reserve(drops_.size());
  }

  void Animate(float seconds, simd_float3 cameraEye)
  {
    // All motion is derived from time, so pausing and probe captures are reproducible.
    if (settings.flow)
      waterTime += seconds - time;
    time = seconds;
    for (size_t variant = 0; variant < Crowns.size(); ++variant)
    {
      live_[Crowns[variant]]  = base_[Crowns[variant]];
      live_[Foliage[variant]] = base_[Foliage[variant]];
    }
    for (Asset asset : {Crown, Leaves, Crown2, Leaves2, Crown3, Leaves3, Grass, Fern, Mote})
      for (size_t i = 0; i < base_[asset].size(); ++i)
      {
        auto &p     = live_[asset][i];
        p           = base_[asset][i];
        float phase = p.position.x * .65f + p.position.z * .38f + float(i) * .73f;
        if (settings.wind && asset != Mote)
        {
          float amplitude = asset == Grass ? .10f : asset == Fern ? .045f : .008f;
          p.rotation.z    = amplitude * (std::sin(time * 1.35f + phase) +
                                         .35f * std::sin(time * 2.4f + phase * 1.7f));
          p.rotation.x    = amplitude * .5f * std::sin(time * 1.1f + phase + .8f);
        }
        if (asset == Mote)
        {
          p.position.x += .24f * std::sin(time * .23f + phase);
          p.position.y += .16f * std::sin(time * .35f + phase);
          p.rotation.y = yaw;
        }
      }
    for (size_t asset = BillboardBegin; asset < ThicketBegin; ++asset)
      live_[asset].clear();
    // Screen-size LOD with complementary coverage. Both representations stay opaque.
    simd_float2 eye = {cameraEye.x, cameraEye.z};
    alloy3d::CameraData lodCamera;
    Camera(lodCamera, 1);
    for (size_t variant = 0; variant < Crowns.size(); ++variant)
    {
      lodWood_.swap(live_[Crowns[variant]]);
      lodLeaves_.swap(live_[Foliage[variant]]);
      const auto &wood = lodWood_, &leaves = lodLeaves_;
      live_[Crowns[variant]].clear();
      live_[Foliage[variant]].clear();
      live_[DistantCrowns[variant]].clear();
      live_[DistantFoliage[variant]].clear();
      for (size_t i = 0; i < wood.size(); ++i)
      {
        const std::array<float,2> thresholds = {.54f,.34f};
        auto transition = alloy3d::SelectLod3D(
            alloy3d::ProjectedHeight3D(lodCamera, wood[i].position + simd_make_float3(0,5*wood[i].scale.y,0),
                                       6*wood[i].scale.y),
            std::span(thresholds.data(), settings.billboards ? 2 : 1));
        auto placeLevel = [&](size_t level, simd_float2 coverage)
        {
          if (coverage.y <= coverage.x) return;
          auto w = wood[i], l = leaves[i];
          w.coverage = l.coverage = coverage;
          if (level < 2)
          {
            live_[level == 0 ? Crowns[variant] : DistantCrowns[variant]].push_back(w);
            live_[level == 0 ? Foliage[variant] : DistantFoliage[variant]].push_back(l);
          }
          else
          {
            float facing = std::atan2(eye.x-w.position.x, eye.y-w.position.z);
            int view = int(std::floor((facing-w.rotation.y)*8.f/6.28318530718f+.5f));
            view = (view%8+8)%8;
            w.rotation.y = facing;
            live_[BillboardAsset(variant,view)].push_back(w);
          }
        };
        if (transition.nearLevel == transition.farLevel) placeLevel(transition.nearLevel,simd_float2{0,1});
        else
        {
          placeLevel(transition.nearLevel,simd_float2{0,1-transition.farWeight});
          placeLevel(transition.farLevel,simd_float2{1-transition.farWeight,1});
        }
      }
    }
    for (size_t asset = ThicketBegin; asset < Droplet; ++asset)
      for (size_t i = 0; i < base_[asset].size(); ++i)
      {
        auto &p      = live_[asset][i];
        p            = base_[asset][i];
        p.rotation.y = std::atan2(eye.x - p.position.x, eye.y - p.position.z);
      }
    for (size_t i = 0; i < live_[Beam].size(); ++i)
      live_[Beam][i].color.w = .82f + .18f * std::sin(time * .27f + float(i));
    live_[Droplet].clear();
    for (size_t i = 0; i < drops_.size(); ++i)
    {
      const auto &emitter = drops_[i];
      float       age     = std::fmod(waterTime + emitter.phase, emitter.period);
      if (age < 0)
        age += emitter.period;
      float lifetime = 2.f * emitter.lift / 9.8f;
      if (age >= lifetime)
        continue;
      // Follow the curved channel downstream; each short hop lands on the water.
      float      originZ = emitter.z;
      const bool nearby  = i >= BaseEmitters;
      if (nearby && i % BaseEmitters < BankEmitters)
      {
        // Wrap only outside the 20m fade radius. Visible hops remain anchored in
        // world space when the camera moves, including while the stream is paused.
        constexpr float span = (BankEmitters / 2) * DropletSpacing;
        originZ += std::floor((cameraEye.z - originZ + span * .5f) / span) * span;
      }
      if (originZ < -44.5f || originZ > 19.5f)
        continue;
      float z        = originZ + emitter.speed * age;
      float x        = StreamCenter(z) + (emitter.across + emitter.inward * age) * StreamWidth(z);
      float y        = WaterLevel(z) + .012f + emitter.lift * age - 4.9f * age * age;
      float progress = age / lifetime;
      float alpha    = std::min(1.f, progress / .08f) * std::min(1.f, (1.f - progress) / .25f);
      if (nearby)
      {
        float distance = simd_length(simd_float2{x - cameraEye.x, z - cameraEye.z});
        float fade =
            std::clamp((DropletFadeEnd - distance) / (DropletFadeEnd - DropletFadeStart), 0.f, 1.f);
        alpha *= fade * fade * (3.f - 2.f * fade);
        if (alpha <= 0)
          continue;
      }
      float stretch = 1.f + .30f * std::abs(emitter.lift - 9.8f * age);
      float radius  = emitter.radius * DropletScale;
      live_[Droplet].push_back({{x, y, z},
                                {0, 0, 0},
                                {radius, radius * stretch, radius},
                                {DropletTint.x, DropletTint.y, DropletTint.z, alpha}});
    }
  }

  void Camera(alloy3d::CameraData &camera, float aspect) const
  {
    simd_float3 eye     = {std::sin(yaw) * 3.f, 2.25f, 14.f - travel};
    simd_float3 forward = {std::sin(yaw), std::sin(pitch), -std::cos(yaw)};
    camera.buildPerspective(.87f, aspect, .1f, 110);
    camera.buildModelView(eye, eye + forward * 25, {0, 1, 0});
  }
  alloy3d::DirectionalLight3D Light() const
  {
    return {{-.65f, -1, .38f}, {1, .94f, .80f}, .25f, 1.f};
  }
  alloy3d::Fog3D             Fog() const { return {settings.fog, MistColor, 18, 96}; }
  alloy3d::HeightFog3D HeightFog() const
  {
    return {settings.fog && settings.heightFog, MistColor, .012f, .5f, .65f, .25f};
  }
  alloy3d::HemisphereLight3D Ambient() const
  {
    return {true, {.78f, .90f, .94f}, {.20f, .24f, .09f}, {0, 1, 0}, .68f};
  }
  alloy3d::DirectionalShadow3D Shadow() const
  {
    alloy3d::DirectionalShadow3D shadow;
    shadow.enabled    = settings.shadows;
    shadow.resolution = 2048;
    shadow.bounds     = {{-32, -2, -64}, {32, 24, 24}};
    shadow.depthBias  = .0005f;
    return shadow;
  }
  alloy3d::ModelTextureTransform3D TextureTransform(size_t asset) const
  {
    if (asset == Water)
      return {{1, 1}, {0, -std::fmod(waterTime * .155f, 1.f)}};
    return {};
  }
  template <class Submit> void Draw(Submit submit) const
  {
    for (size_t asset = 0; asset < Assets.size(); ++asset)
    {
      if ((asset == Beam || asset == Mote) && !settings.shafts)
        continue;
      if (asset == Droplet && !settings.droplets)
        continue;
      // Opaque foliage stays instanced; BLEND sheets use the renderer's depth sorting.
      submit(asset, std::span<const alloy3d::ModelInstance>(live_[asset]));
    }
  }
};
} // namespace forest
