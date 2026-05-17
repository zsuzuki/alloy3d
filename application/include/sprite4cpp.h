//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

class SpriteCpp
{
public:
  enum class Align
  {
    LeftTop,
    RightTop,
    LeftCenter,
    RightCenter,
    LeftBottom,
    RightBottom,
    CenterTop,
    Center,
    CenterBottom,
  };

  SpriteCpp()          = default;
  virtual ~SpriteCpp() = default;

  virtual bool IsLoaded() const = 0;

  virtual void SetAlign(Align align)                                         = 0;
  virtual void SetScale(float scale)                                         = 0;
  virtual void SetRotate(float rotate)                                       = 0;
  virtual void SetPosition(float x, float y)                                 = 0;
  virtual void SetFaceColor(float red, float green, float blue, float alpha) = 0;
};
