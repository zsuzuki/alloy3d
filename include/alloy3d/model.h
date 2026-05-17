//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <cstddef>
#include <simd/simd.h>
#include <simd/vector_make.h>
#include <string>
#include <string_view>

namespace alloy3d
{

class Model
{
public:
  Model()          = default;
  virtual ~Model() = default;

  virtual bool IsLoaded() const = 0;
  virtual std::size_t AnimationCount() const = 0;
  virtual std::string AnimationName(std::size_t index) const = 0;
  virtual float AnimationDuration(std::size_t index) const = 0;
  virtual std::size_t CurrentAnimationIndex() const = 0;
  virtual float CurrentAnimationDuration() const = 0;
  virtual void SetAnimation(std::size_t index) = 0;
  virtual bool SetAnimation(std::string_view name) = 0;
  virtual void SetAnimationTime(float seconds) = 0;

  virtual std::size_t RigCount() const = 0;
  virtual std::string RigName(std::size_t index) const = 0;
  virtual int RigIndex(std::string_view name) const = 0;
  virtual bool RigTransform(std::size_t index, simd_float4x4 &transform) const = 0;
  bool RigPosition(std::size_t index, simd_float3 &position) const
  {
    simd_float4x4 transform{};
    if (!RigTransform(index, transform))
    {
      return false;
    }
    position = simd_make_float3(transform.columns[3].x, transform.columns[3].y, transform.columns[3].z);
    return true;
  }
};

} // namespace alloy3d
