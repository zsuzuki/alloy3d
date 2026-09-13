#pragma once
#include <metal_stdlib>
using namespace metal;

// Inputs to float3 alloy3dShade(ModelSurface s, float4 parameters).
struct ModelSurface
{
  float3 baseColor; // texture * vertex/material color * placement tint
  float3 litColor;  // built-in RGB, including shadows, highlights and unlit handling (before fog)
  float3 normal;    // normalized, view space, corrected for back faces; zero if absent
  float2 texcoord; // after ModelTextureTransform3D
  float3 lightColor;
  float  ambient;
  float  diffuse; // N dot L * light intensity, before shadow attenuation
  float  shadow;  // visibility in [0,1]
  bool   unlit;   // material unlit or no usable normal
  float3 ambientColor; // effective ambient RGB, including hemisphere lighting
  float3 specularColor; // built-in highlight RGB (already included in litColor)
  float3 viewPosition; // deformed and placed position in view space, including unlit models
  float3 viewDirection; // unit surface-to-eye direction; orthographic/identity: (0,0,1)
  float3 lightDirection; // unit surface-to-light direction in view space
  float lightIntensity; // directional diffuse intensity, [0,1]
  float roughness; // sampled material roughness when detail is enabled, otherwise 1
  float occlusion; // sampled ambient occlusion when detail is enabled, otherwise 1
  float3 transmissionColor; // thin-surface backlighting, already included in litColor
};
