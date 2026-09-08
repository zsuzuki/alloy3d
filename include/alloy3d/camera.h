//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <alloy3d/bounds.h>

namespace alloy3d
{

enum class ProjectionMode
{
  Identity,
  Perspective,
  Orthographic
};

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
  float           orthographicHeight_;
  ProjectionMode  projectionMode_;

public:
  CameraData();
  ~CameraData();

  // Right-handed view space (forward is -Z), Metal depth range [0, 1].
  // Invalid/non-finite parameters throw std::invalid_argument without changing state.
  // Default projection/view remain identity for low-level drawing compatibility.
  // fovy is the vertical field of view in radians.
  void buildPerspective(float fovy, float aspect, float znear, float zfar);
  // Centered orthographic projection. Height is the visible vertical world extent.
  void buildOrthographic(float height, float aspect, float znear, float zfar);
  // Preserve projection mode, FOV/orthographic height and clipping planes.
  void setAspectRatio(float aspect);
  // A zero/parallel up vector uses a stable perpendicular axis. eye == look is invalid.
  void buildModelView(simd_float3 eye, simd_float3 look, simd_float3 up);
  // Fit world-space bounds, preserving viewing direction and projection mode.
  // Adjusts eye, target, clipping planes and orthographic height. Identity becomes perspective.
  void fitBounds(const Bounds3D &bounds, float padding = 1.1f);
  //
  [[nodiscard]] matrix_float4x4 getProjectionMatrix() const { return projection_; }
  [[nodiscard]] matrix_float4x4 getModelViewMatrix() const { return modelview_; }
  [[nodiscard]] simd_float3     getEyePosition() const { return eyePoint_; }
  [[nodiscard]] simd_float3     getLookAt() const { return lookAt_; }
  [[nodiscard]] simd_float3     getUpDirection() const { return upDir_; }
  [[nodiscard]] float           getAspect() const { return aspect_; }
  [[nodiscard]] float           getFieldOfView() const { return fovy_; }
  [[nodiscard]] float           getNearPlane() const { return znear_; }
  [[nodiscard]] float           getFarPlane() const { return zfar_; }
  [[nodiscard]] float           getOrthographicHeight() const { return orthographicHeight_; }
  [[nodiscard]] ProjectionMode  getProjectionMode() const { return projectionMode_; }
};

} // namespace alloy3d
