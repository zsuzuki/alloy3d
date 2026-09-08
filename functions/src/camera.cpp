//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include <algorithm>
#include <alloy3d/camera.h>
#include <cmath>
#include <numbers>
#include <stdexcept>

namespace
{
void Require(bool condition)
{
  if (!condition)
    throw std::invalid_argument("Alloy3D camera parameters must form a finite, valid camera");
}
bool Finite(simd_float3 v)
{
  return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}
void CheckMatrix(const simd_float4x4 &m)
{
  for (const auto &column : m.columns)
    for (int i = 0; i < 4; ++i)
      Require(std::isfinite(column[i]));
}
simd_double3 Double(simd_float3 v) { return simd_make_double3(v.x, v.y, v.z); }
simd_float3  Float(simd_double3 v) { return simd_make_float3(v.x, v.y, v.z); }
void         CheckProjection(float size, float aspect, float near, float far, bool perspective)
{
  Require(std::isfinite(size) && std::isfinite(aspect) && std::isfinite(near) &&
          std::isfinite(far));
  Require(size > 0 && aspect > 0 && near >= 0 && far > near);
  if (perspective)
    Require(size < std::numbers::pi && near > 0);
}
} // namespace

alloy3d::CameraData::CameraData()
    : projection_(matrix_identity_float4x4), modelview_(matrix_identity_float4x4),
      eyePoint_{0, 0, 0}, lookAt_{0, 0, -1}, upDir_{0, 1, 0}, aspect_(1),
      fovy_(std::numbers::pi_v<float> / 4), znear_(.1f), zfar_(1000), orthographicHeight_(2),
      projectionMode_(ProjectionMode::Identity)
{
}

alloy3d::CameraData::~CameraData() = default;

void alloy3d::CameraData::buildPerspective(float fovy, float aspect, float znear, float zfar)
{
  CheckProjection(fovy, aspect, znear, zfar, true);
  const double ys         = 1 / std::tan(double(fovy) / 2);
  const double range      = double(zfar) - znear;
  const auto   projection = simd_matrix_from_rows(
      simd_make_float4(ys / aspect, 0, 0, 0),
      simd_make_float4(0, ys, 0, 0),
      simd_make_float4(0, 0, -double(zfar) / range, -double(zfar) * znear / range),
      simd_make_float4(0, 0, -1, 0));
  CheckMatrix(projection);
  Require(projection.columns[0].x > 0 && projection.columns[1].y > 0 &&
          projection.columns[3].z < 0);
  projection_     = projection;
  fovy_           = fovy;
  aspect_         = aspect;
  znear_          = znear;
  zfar_           = zfar;
  projectionMode_ = ProjectionMode::Perspective;
}

void alloy3d::CameraData::buildOrthographic(float height, float aspect, float znear, float zfar)
{
  CheckProjection(height, aspect, znear, zfar, false);
  const double range = double(zfar) - znear;
  const auto   projection =
      simd_matrix_from_rows(simd_make_float4(2 / (double(height) * aspect), 0, 0, 0),
                            simd_make_float4(0, 2 / double(height), 0, 0),
                            simd_make_float4(0, 0, -1 / range, -double(znear) / range),
                            simd_make_float4(0, 0, 0, 1));
  CheckMatrix(projection);
  Require(projection.columns[0].x > 0 && projection.columns[1].y > 0 &&
          projection.columns[2].z < 0);
  projection_         = projection;
  orthographicHeight_ = height;
  aspect_             = aspect;
  znear_              = znear;
  zfar_               = zfar;
  projectionMode_     = ProjectionMode::Orthographic;
}

void alloy3d::CameraData::setAspectRatio(float aspect)
{
  Require(std::isfinite(aspect) && aspect > 0);
  switch (projectionMode_)
  {
  case ProjectionMode::Perspective:
    buildPerspective(fovy_, aspect, znear_, zfar_);
    break;
  case ProjectionMode::Orthographic:
    buildOrthographic(orthographicHeight_, aspect, znear_, zfar_);
    break;
  case ProjectionMode::Identity:
    aspect_ = aspect;
    break;
  }
}

void alloy3d::CameraData::buildModelView(simd_float3 eye, simd_float3 look, simd_float3 up)
{
  Require(Finite(eye) && Finite(look) && Finite(up));
  auto back = Double(eye) - Double(look);
  Require(simd_length_squared(back) > 0);
  back        = simd_normalize(back);
  auto upAxis = Double(up);
  if (simd_length_squared(upAxis) > 0)
    upAxis = simd_normalize(upAxis);
  auto right = simd_cross(upAxis, back);
  if (simd_length_squared(right) < 1e-12)
  {
    // Select the axis least parallel to the view direction.
    int axis = 0;
    if (std::abs(back.y) < std::abs(back[axis]))
      axis = 1;
    if (std::abs(back.z) < std::abs(back[axis]))
      axis = 2;
    upAxis       = simd_make_double3(0, 0, 0);
    upAxis[axis] = 1;
    right        = simd_cross(upAxis, back);
  }
  right                  = simd_normalize(right);
  const auto correctedUp = simd_cross(back, right);
  const auto e           = Double(eye);
  const auto view        = simd_matrix_from_rows(
      simd_make_float4(right.x, right.y, right.z, -simd_dot(right, e)),
      simd_make_float4(correctedUp.x, correctedUp.y, correctedUp.z, -simd_dot(correctedUp, e)),
      simd_make_float4(back.x, back.y, back.z, -simd_dot(back, e)),
      simd_make_float4(0, 0, 0, 1));
  CheckMatrix(view);
  modelview_ = view;
  eyePoint_  = eye;
  lookAt_    = look;
  upDir_     = Float(correctedUp);
}

void alloy3d::CameraData::fitBounds(const Bounds3D &bounds, float padding)
{
  Require(bounds.isValid() && std::isfinite(padding) && padding >= 1);
  const auto center   = (Double(bounds.min) + Double(bounds.max)) * .5;
  const auto halfSize = (Double(bounds.max) - Double(bounds.min)) * .5;
  // A tiny point/empty-size model still receives a useful finite view.
  const double radius         = std::max(1e-3, simd_length(halfSize)) * padding;
  const double verticalHalf   = double(fovy_) * .5;
  const double horizontalHalf = std::atan(std::tan(verticalHalf) * aspect_);
  const double distance =
      projectionMode_ == ProjectionMode::Orthographic
          ? radius * 2
          : std::max(radius / std::sin(std::min(verticalHalf, horizontalHalf)), radius * 1.001);
  const double near   = std::max((distance - radius) * .5, radius * 1e-5);
  const double far    = distance + radius * 1.1;
  auto         back   = simd_normalize(Double(eyePoint_) - Double(lookAt_));
  auto         fitted = *this;
  fitted.buildModelView(Float(center + back * distance), Float(center), upDir_);
  if (projectionMode_ == ProjectionMode::Orthographic)
    fitted.buildOrthographic(2 * radius / std::min(1.0, double(aspect_)), aspect_, near, far);
  else
    fitted.buildPerspective(fovy_, aspect_, near, far);
  *this = fitted;
}
