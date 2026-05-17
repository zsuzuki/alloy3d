//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <functional>

namespace Keyboard
{

//
//
//
enum class KeyCode : uint16_t
{
  SPC,
  UP,
  DOWN,
  LEFT,
  RIGHT,
  PGUP,
  PGDOWN,
  HOME,
  END,
  BS,
  DEL,
  LCTRL,
  RCTRL,
  LSHT,
  RSHT,
  LCMD,
  RCMD,
  LALT,
  RALT,
  ENTER,
  ESC,
  TAB,
  //
  A,
  B,
  C,
  D,
  E,
  F,
  G,
  H,
  I,
  J,
  K,
  L,
  M,
  N,
  O,
  P,
  Q,
  R,
  S,
  T,
  U,
  V,
  W,
  X,
  Y,
  Z,
  //
  Num0,
  Num1,
  Num2,
  Num3,
  Num4,
  Num5,
  Num6,
  Num7,
  Num8,
  Num9,
};

using KeyPressCallback = std::function<void(KeyCode, bool)>;

//
void Fetch(KeyPressCallback kpcb);

} // namespace Keyboard
