//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "game_pad.h"
#include <Foundation/NSObjCRuntime.h>
#import <GameController/GameController.h>

#include <list>

namespace GamePad
{
constexpr int RepeatCountInit = 30;
constexpr int RepeatCountCont = 5;

void PadState::Button::update(int &count, PadState::Button *&repBtn)
{
  repeat_ = false;

  if (press_)
  {
    if (!prev_)
    {
      // start repeat
      repBtn = this;
      count  = RepeatCountInit;
    }
    else if (repBtn == this)
    {
      if (count > 0)
      {
        count--;
      }
      else
      {
        repeat_ = true;
        count   = RepeatCountCont;
      }
    }
  }
}

void PadState::updateButton(Button &btn) { btn.update(repeatCount_, repeatButton_); }

void PadState::fetch(PadState &receive)
{
  auto repCnt           = receive.repeatCount_;
  auto repBtn           = receive.repeatButton_;
  receive               = *this;
  receive.repeatCount_  = repCnt;
  receive.repeatButton_ = repBtn;
  receive.updateButtons();
}

void PadState::updateButtons()
{
  updateButton(buttonMenu);
  updateButton(buttonOptions);
  updateButton(buttonA);
  updateButton(buttonB);
  updateButton(buttonC);
  updateButton(buttonD);
  updateButton(shoulderL);
  updateButton(shoulderR);
  updateButton(buttonUp);
  updateButton(buttonDown);
  updateButton(buttonLeft);
  updateButton(buttonRight);
  updateButton(thumbL);
  updateButton(thumbR);
  updateButton(buttonTouch);
}

namespace
{
std::list<PadState> padList;
using psit = decltype(padList)::iterator;
GamePadUpdateHandler  updateHandler{};
GamePadConnectHandler connectHandler{};
GamePadConnectHandler disconnectHandler{};

//
void convertMotion(PadState &state, GCMotion *motion)
{
  if (motion != Nil)
  {
    state.enabled      = true;
    auto att           = motion.attitude;
    state.posture      = simd_quaternion((float)att.x, (float)att.y, (float)att.z, (float)att.w);
    auto rot           = motion.rotationRate;
    state.rotation     = simd_make_float3(rot.x, rot.y, rot.z);
    auto acc           = motion.acceleration;
    state.acceleration = simd_make_float3(acc.x, acc.y, acc.z);
  }
}

//
void convertState(PadState &state, GCExtendedGamepad *input)
{
  state.enabled    = true;
  auto setupButton = [&](PadState::Button &btn, GCControllerButtonInput *src)
  { btn = src.isPressed; };
  setupButton(state.buttonMenu, input.buttonMenu);
  setupButton(state.buttonOptions, input.buttonOptions);
  setupButton(state.buttonA, input.buttonA);
  setupButton(state.buttonB, input.buttonB);
  setupButton(state.buttonC, input.buttonX);
  setupButton(state.buttonD, input.buttonY);
  setupButton(state.shoulderL, input.leftShoulder);
  setupButton(state.shoulderR, input.rightShoulder);
  setupButton(state.buttonUp, input.dpad.up);
  setupButton(state.buttonDown, input.dpad.down);
  setupButton(state.buttonLeft, input.dpad.left);
  setupButton(state.buttonRight, input.dpad.right);
  setupButton(state.thumbL, input.leftThumbstickButton);
  setupButton(state.thumbR, input.rightThumbstickButton);

  if ([input isKindOfClass:[GCDualShockGamepad class]])
  {
    GCDualShockGamepad *dualShock = (GCDualShockGamepad *)input;
    setupButton(state.buttonTouch, dualShock.touchpadButton);
  }

  auto analogValue = [](float value)
  {
    // constexpr float lim   = 0.005f;
    // constexpr float range = 1.0f - lim;
    // return value > lim ? (value - lim) / range : value < -lim ? (value + lim) / range : 0.0f;
    return value;
  };
  auto lStick    = input.leftThumbstick;
  auto rStick    = input.rightThumbstick;
  state.leftX    = analogValue(lStick.xAxis.value);
  state.leftY    = analogValue(lStick.yAxis.value);
  state.rightX   = analogValue(rStick.xAxis.value);
  state.rightY   = analogValue(rStick.yAxis.value);
  state.triggerL = analogValue(input.leftTrigger.analog ? input.leftTrigger.value : 0.0f);
  state.triggerR = analogValue(input.rightTrigger.analog ? input.rightTrigger.value : 0.0f);
}

//
psit searchPad(NSUInteger hash)
{
  auto hashNum = static_cast<uint64_t>(hash);
  auto ret     = padList.begin();
  for (; ret != padList.end(); ret++)
  {
    if (ret->checkHash(hashNum))
    {
      return ret;
    }
  }
  return ret;
}
//
void setupPad(GCController *controller)
{
  auto gamepad = controller.extendedGamepad;
  if (gamepad == Nil)
  {
    return;
  }

  auto     hashNum = static_cast<uint64_t>(controller.hash);
  PadState newState{hashNum};
  padList.push_back(newState);

  if (connectHandler)
  {
    connectHandler(hashNum);
  }

  gamepad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *elem) {
    auto padit = searchPad(hashNum);
    if (padit != padList.end())
    {
      convertState(*padit, gamepad);
      if (updateHandler)
      {
        updateHandler(*padit, UpdateType::PadState);
      }
    }
  };

  auto motion = [controller motion];
  if (motion != Nil)
  {
    if (motion.sensorsRequireManualActivation)
    {
      motion.sensorsActive = YES;
    }

    motion.valueChangedHandler = ^(GCMotion *motion) {
      auto padit = searchPad(hashNum);
      if (padit != padList.end())
      {
        convertMotion(*padit, motion);
        if (updateHandler)
        {
          updateHandler(*padit, UpdateType::Motion);
        }
      }
    };
  }

  // NSLog(@"Create Gamepad: %llx", hashNum);
}

//
void erasePad(GCController *controller)
{
  auto hashNum = static_cast<uint64_t>(controller.hash);
  auto padit   = searchPad(hashNum);
  if (padit != padList.end())
  {
    padList.erase(padit);
    if (disconnectHandler)
    {
      disconnectHandler(hashNum);
    }
    // NSLog(@"Delete Gamepad: %llx", hashNum);
  }
}

} // namespace

//
//
//
bool InitGamePad(GamePadUpdateHandler &&handler, GamePadConnectHandler &&connect,
                 GamePadConnectHandler &&disconnect)
{
  updateHandler     = std::move(handler);
  connectHandler    = std::move(connect);
  disconnectHandler = std::move(disconnect);

  auto notificationCenter = [NSNotificationCenter defaultCenter];
  [notificationCenter addObserverForName:GCControllerDidConnectNotification
                                  object:nil
                                   queue:nil
                              usingBlock:^(NSNotification *note) {
                                setupPad(note.object);
                              }];
  [notificationCenter addObserverForName:GCControllerDidDisconnectNotification
                                  object:nil
                                   queue:nil
                              usingBlock:^(NSNotification *note) {
                                erasePad(note.object);
                              }];

  return true;
}

//
//
//
bool GetPadState(int idx, PadState &state)
{
  GCExtendedGamepad *input  = Nil;
  GCMotion          *motion = Nil;

  for (GCController *controller in GCController.controllers)
  {
    if (controller.extendedGamepad)
    {
      if (idx == 0)
      {
        PadState baseState{};
        convertState(baseState, controller.extendedGamepad);
        auto motion = [controller motion];
        if (motion.sensorsRequireManualActivation)
        {
          motion.sensorsActive = YES;
        }
        convertMotion(baseState, motion);
        baseState.fetch(state);
        return true;
      }
      else
      {
        idx--;
      }
    }
  }

  state.enabled = false;
  return false;
}

} // namespace GamePad
