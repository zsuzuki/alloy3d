#pragma once
#include <alloy3d/bounds.h>
#include <cstdint>

namespace alloy3d
{
struct ModelTransmission3D
{
  // Thin-surface backlighting; does not change alpha or refract the background.
  float strength = 0; // Finite [0,1], zero disables.
  simd_float3 color = {1, 1, 1}; // Finite linear RGB [0,1].
};

struct ModelMaterialDetail3D
{
  // Optional lightweight use of glTF roughness and occlusion, not a full PBR model.
  bool enabled = false;
};

struct ModelHighlight3D
{
  // Blinn-Phong specular light. Zero strength disables it; no effect on Unlit materials.
  float strength  = 0;  // Finite [0,1].
  float shininess = 32; // Finite [1,128]; larger means a narrower highlight.
};

struct Fog3D
{
  bool enabled = false;
  // Linear RGB. Distance is camera-forward depth in world units, not radial distance.
  simd_float3 color = {.5f, .6f, .7f};
  float start = 10;
  float end   = 100;
};

struct HemisphereLight3D
{
  bool enabled = false;
  // Replaces DirectionalLight3D::ambient when enabled. Linear RGB and intensity in [0,1].
  simd_float3 skyColor    = {.65f, .8f, 1};
  simd_float3 groundColor = {.3f, .25f, .2f};
  simd_float3 up          = {0, 1, 0}; // Finite, nonzero world-space direction.
  float intensity = .35f;
};

struct DirectionalLight3D
{
  // World-space direction in which light travels. Finite, nonzero.
  simd_float3 direction = {-.4f, -.8f, -.6f};
  simd_float3 color     = {1, 1, 1};
  float       ambient   = .25f;
  float       diffuse   = .85f;
};

struct DirectionalShadow3D
{
  bool enabled = false;
  // Square depth map, allocated lazily for each of three frame pages. 64..4096.
  uint32_t resolution = 1024;
  // World-space region containing both casters and receivers. No automatic scene scan.
  Bounds3D bounds{{-10, -10, -10}, {10, 10, 10}};
  // Bias in normalized light depth. Valid range [0, 0.1].
  float depthBias = .001f;
  // Caster slope bias, [0,8]; 0 disables. Internal normalized depth clamp is 0.01.
  float slopeScale = 2.0f;
};
} // namespace alloy3d
