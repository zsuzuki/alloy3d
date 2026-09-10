#pragma once
#include <metal_stdlib>
using namespace metal;

// Inputs to float3 alloy3dShade(ModelSurface s, float4 parameters).
struct ModelSurface
{
  float3 baseColor; // texture * vertex/material color * placement tint
  float3 litColor;  // built-in RGB, including shadows and unlit handling
  float3 normal;    // normalized, view space, corrected for back faces; zero if absent
  float2 texcoord;
  float3 lightColor;
  float  ambient;
  float  diffuse; // N dot L * light intensity, before shadow attenuation
  float  shadow;  // visibility in [0,1]
  bool   unlit;   // material unlit or no usable normal
  float3 ambientColor; // effective ambient RGB, including hemisphere lighting
};
