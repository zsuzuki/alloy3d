//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once

#include <functional>
#include <simd/simd.h>

namespace GamePad
{

//
//
//
class PadState
{
public:
  class Button
  {
    bool press_;
    bool prev_;
    bool repeat_;

  public:
    Button() : press_(false), prev_(false) {}
    explicit Button(bool swon, bool prev) : press_(swon), prev_(prev) {}
    Button(const Button &other) = default;
    Button(Button &&other)      = delete;
    ~Button()                   = default;

    Button &operator=(const Button &other)
    {
      prev_  = press_;
      press_ = other.press_;
      return *this;
    }
    Button &operator=(Button &&) = delete;
    Button &operator=(bool val)
    {
      press_ = val;
      return *this;
    }

    void update(int &count, Button *&repBtn);
    void overridePress(bool press = true) { press_ = press ? true : press_; }

    [[nodiscard]] bool Pressed() const { return press_; }
    [[nodiscard]] bool On() const { return press_ && !prev_; }
    [[nodiscard]] bool Release() const { return !press_ && prev_; }
    [[nodiscard]] bool Repeat() const { return On() || repeat_; }
  };

  PadState() = default;
  PadState(uint64_t hnum) : hash(hnum) {}

  bool   enabled = false;
  Button buttonUp;
  Button buttonDown;
  Button buttonLeft;
  Button buttonRight;
  Button buttonA;
  Button buttonB;
  Button buttonC;
  Button buttonD;
  Button thumbL;
  Button thumbR;
  Button shoulderL;
  Button shoulderR;
  Button buttonMenu;
  Button buttonOptions;
  Button buttonTouch;
  float  leftX    = 0.0f;
  float  leftY    = 0.0f;
  float  rightX   = 0.0f;
  float  rightY   = 0.0f;
  float  triggerL = 0.0f;
  float  triggerR = 0.0f;

  simd_float3 acceleration = simd_make_float3(0.0f);
  simd_float3 rotation     = simd_make_float3(0.0f);
  simd_quatf  posture      = simd_quaternion(0.0f, 0.0f, 0.0f, 1.0f);

  [[nodiscard]] bool operator==(const PadState &other) const { return hash == other.hash; }
  [[nodiscard]] bool operator!=(const PadState &other) const { return hash != other.hash; }

  [[nodiscard]] bool checkHash(uint64_t hnum) const { return hash == hnum; }

  void fetch(PadState &receive);

private:
  int      repeatCount_  = 0;
  Button  *repeatButton_ = nullptr;
  uint64_t hash          = 0;

  void updateButtons();
  void updateButton(Button &btn);
};

//
enum class UpdateType
{
  PadState,
  Motion,
};
using GamePadUpdateHandler  = std::function<void(const PadState &state, UpdateType)>;
using GamePadConnectHandler = std::function<void(uint64_t)>;

// 更新時コールバックで処理する場合はこちら(更新レートが高いコントローラー推奨)
bool InitGamePad(GamePadUpdateHandler &&handler, GamePadConnectHandler &&connect,
                 GamePadConnectHandler &&disconnect);

// 毎フレーム更新チェックする場合はこちら(InitGamePadを呼ぶ必要はない)
bool GetPadState(int idx, PadState &state);

} // namespace GamePad
