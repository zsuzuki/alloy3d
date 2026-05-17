//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include "camera.h"
#include <arm_neon.h>
#include <complex>
#include <simd/matrix.h>
#include <simd/vector_make.h>

//
CameraData::CameraData()
{
  projection_ = matrix_identity_float4x4;
  modelview_  = matrix_identity_float4x4;
  eyePoint_   = simd_make_float3(0.0f, 0.0f, 0.0f);
  lookAt_     = simd_make_float3(0.0f, 0.0f, 1.0f);
  upDir_      = simd_make_float3(0.0f, 1.0f, 0.0f);
  aspect_     = 1.0f;
  fovy_       = 45.0f;
}

//
CameraData::~CameraData() = default;

//
void CameraData::buildPerspective(float fovy, float aspect, float znear, float zfar)
{
  fovy_       = fovy;
  aspect_     = aspect;
  znear_      = znear;
  zfar_       = zfar;
  float ys    = 1.0f / tanf(fovy_ * 0.5f);
  float xs    = ys / aspect_;
  float zs    = -((zfar_ + znear_) / (zfar_ - znear_));
  float zs2   = -(2.0 * zfar_ * znear_) / (zfar_ - znear_);
  projection_ = simd_matrix_from_rows(simd_make_float4(xs, 0.0f, 0.0f, 0.0f),
                                      simd_make_float4(0.0f, ys, 0.0f, 0.0f),
                                      simd_make_float4(0.0f, 0.0f, zs, zs2),
                                      simd_make_float4(0.0f, 0.0f, -1.0f, 0.0f));
}

//
void CameraData::buildModelView(simd_float3 eye, simd_float3 look, simd_float3 up)
{
  eyePoint_ = eye;
  lookAt_   = look;
  upDir_    = up;

  auto &eyePos    = eyePoint_;
  auto  targetVec = eyePos - lookAt_;
  auto  frontVec  = simd_normalize(targetVec);
  auto  upVec     = simd_normalize(upDir_);
  auto  sideVec   = simd_normalize(simd_cross(upVec, targetVec));
  upVec           = simd_normalize(simd_cross(frontVec, sideVec));

  auto &viewMtx      = modelview_;
  viewMtx.columns[0] = simd_make_float4(sideVec[0], upVec[0], frontVec[0], 0.0f);
  viewMtx.columns[1] = simd_make_float4(sideVec[1], upVec[1], frontVec[1], 0.0f);
  viewMtx.columns[2] = simd_make_float4(sideVec[2], upVec[2], frontVec[2], 0.0f);
  viewMtx.columns[3] = simd_make_float4(0.0f, 0.0f, 0.0f, 1.0f);

  auto trans            = simd_make_float4(-eyePos[0], -eyePos[1], -eyePos[2], 1.0f);
  viewMtx.columns[3]    = simd_mul(viewMtx, trans);
  viewMtx.columns[3][3] = 1.0f;
}

//
