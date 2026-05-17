//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#ifndef __METAL_VERSION__
#include <arm_neon.h>
#endif
#include <simd/simd.h>

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name)                                                                      \
  enum _name : _type _name;                                                                        \
  enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>

typedef NS_ENUM(EnumBackingType, BufferIndex) {
  BufferIndexMeshPositions = 0,
  BufferIndexMeshGenerics  = 1,
  BufferIndexUniforms      = 2,
  BufferIndexJointMatrices = 3
};

typedef NS_ENUM(EnumBackingType, VertexAttribute) {
  VertexAttributePosition = 0,
  VertexAttributeTexcoord = 1,
};

typedef NS_ENUM(EnumBackingType, TextureIndex) {
  TextureIndexColor = 0,
};

typedef struct
{
  matrix_float4x4 perspectiveTransform;
  matrix_float4x4 worldTransform;
  matrix_float3x3 worldNormalTransform;
  simd_float4     lightDirectionAndAmbient;
  simd_float4     lightColorAndDiffuse;
  simd_float4     modelColor;
} Uniforms;

typedef struct
{
  simd_float2 size;
} Uniforms2D;

struct VertexDataPrim2D
{
  simd_float2 position;
#ifdef __METAL_VERSION__
  half4 color;
#else
  float16x4_t color;
#endif
};

struct VertexDataPrim3D
{
  simd_float3 position;
  simd_float3 normal;
#ifdef __METAL_VERSION__
  half4 color;
#else
  float16x4_t color;
#endif
};

struct VertexData3D
{
  simd_float3 position;
  simd_float3 normal;
  simd_float2 texcoord;
#ifdef __METAL_VERSION__
  half4 color;
#else
  float16x4_t color;
#endif
};

struct VertexDataModel3D
{
  simd_float3 position;
  simd_float3 normal;
  simd_float2 texcoord;
  simd_uint4  joints;
  simd_float4 weights;
#ifdef __METAL_VERSION__
  half4 color;
#else
  float16x4_t color;
#endif
};
