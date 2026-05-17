//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <simd/simd.h>

class CameraData final
{
  matrix_float4x4 projection_;
  matrix_float4x4 modelview_;
  simd_float3     eyePoint_; // 視点
  simd_float3     lookAt_;   // 注視点
  simd_float3     upDir_;    // 上向き
  float           aspect_;   // アスペクト比
  float           fovy_;     // 画角
  float           znear_;
  float           zfar_;

public:
  CameraData();
  ~CameraData();

  void buildPerspective(float fovy, float aspect, float znear, float zfar);
  void buildModelView(simd_float3 eye, simd_float3 look, simd_float3 up);
  //
  [[nodiscard]] matrix_float4x4 getProjectionMatrix() const { return projection_; }
  [[nodiscard]] matrix_float4x4 getModelViewMatrix() const { return modelview_; }
  [[nodiscard]] simd_float3     getEyePosition() const { return eyePoint_; }
  [[nodiscard]] simd_float3     getLookAt() const { return lookAt_; }
  [[nodiscard]] simd_float3     getUpDirection() const { return upDir_; }
  [[nodiscard]] float           getAspect() const { return aspect_; }
  [[nodiscard]] float           getFieldOfView() const { return fovy_; }
};
