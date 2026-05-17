//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#import "keyboard.h"
#include <Foundation/NSObjCRuntime.h>
#include <GameController/GCKeyCodes.h>
#import <GameController/GameController.h>
#include <map>

namespace Keyboard
{

//
std::map<GCKeyCode, KeyCode> keycodeMap = {
    {GCKeyCodeSpacebar, KeyCode::SPC},
    {GCKeyCodeUpArrow, KeyCode::UP},
    {GCKeyCodeDownArrow, KeyCode::DOWN},
    {GCKeyCodeLeftArrow, KeyCode::LEFT},
    {GCKeyCodeRightArrow, KeyCode::RIGHT},
    {GCKeyCodePageUp, KeyCode::PGUP},
    {GCKeyCodePageDown, KeyCode::PGDOWN},
    {GCKeyCodeHome, KeyCode::HOME},
    {GCKeyCodeEnd, KeyCode::END},
    {GCKeyCodeDeleteOrBackspace, KeyCode::BS},
    {GCKeyCodeDeleteForward, KeyCode::DEL},
    {GCKeyCodeLeftControl, KeyCode::LCTRL},
    {GCKeyCodeRightControl, KeyCode::RCTRL},
    {GCKeyCodeLeftShift, KeyCode::LSHT},
    {GCKeyCodeRightShift, KeyCode::RSHT},
    {GCKeyCodeLeftGUI, KeyCode::LCMD},
    {GCKeyCodeRightGUI, KeyCode::RCMD},
    {GCKeyCodeLeftAlt, KeyCode::LALT},
    {GCKeyCodeRightAlt, KeyCode::RALT},
    {GCKeyCodeEscape, KeyCode::ESC},
    {GCKeyCodeTab, KeyCode::TAB},
    {GCKeyCodeReturnOrEnter, KeyCode::ENTER},
    {GCKeyCodeKeyA, KeyCode::A},
    {GCKeyCodeKeyB, KeyCode::B},
    {GCKeyCodeKeyC, KeyCode::C},
    {GCKeyCodeKeyD, KeyCode::D},
    {GCKeyCodeKeyE, KeyCode::E},
    {GCKeyCodeKeyF, KeyCode::F},
    {GCKeyCodeKeyG, KeyCode::G},
    {GCKeyCodeKeyH, KeyCode::H},
    {GCKeyCodeKeyI, KeyCode::I},
    {GCKeyCodeKeyJ, KeyCode::J},
    {GCKeyCodeKeyK, KeyCode::K},
    {GCKeyCodeKeyL, KeyCode::L},
    {GCKeyCodeKeyM, KeyCode::M},
    {GCKeyCodeKeyN, KeyCode::N},
    {GCKeyCodeKeyO, KeyCode::O},
    {GCKeyCodeKeyP, KeyCode::P},
    {GCKeyCodeKeyQ, KeyCode::Q},
    {GCKeyCodeKeyR, KeyCode::R},
    {GCKeyCodeKeyS, KeyCode::S},
    {GCKeyCodeKeyT, KeyCode::T},
    {GCKeyCodeKeyU, KeyCode::U},
    {GCKeyCodeKeyV, KeyCode::V},
    {GCKeyCodeKeyW, KeyCode::W},
    {GCKeyCodeKeyX, KeyCode::X},
    {GCKeyCodeKeyY, KeyCode::Y},
    {GCKeyCodeKeyZ, KeyCode::Z},
    {GCKeyCodeZero, KeyCode::Num0},
    {GCKeyCodeOne, KeyCode::Num1},
    {GCKeyCodeTwo, KeyCode::Num2},
    {GCKeyCodeThree, KeyCode::Num3},
    {GCKeyCodeFour, KeyCode::Num4},
    {GCKeyCodeFive, KeyCode::Num5},
    {GCKeyCodeSix, KeyCode::Num6},
    {GCKeyCodeSeven, KeyCode::Num7},
    {GCKeyCodeEight, KeyCode::Num8},
    {GCKeyCodeNine, KeyCode::Num9},
};

//
//
//
void Fetch(KeyPressCallback kpcb)
{
  auto *keyboard             = [GCKeyboard coalescedKeyboard];
  auto *keyInput             = keyboard.keyboardInput;
  keyInput.keyChangedHandler = ^(GCKeyboardInput *_Nonnull keyboard,
                                 GCControllerButtonInput *_Nonnull key,
                                 GCKeyCode keyCode,
                                 BOOL      pressed) {
    auto transKeyMap = keycodeMap.find(keyCode);
    if (transKeyMap != keycodeMap.end())
    {
      kpcb(transKeyMap->second, pressed);
    }
    // else
    // {
    //   NSLog(@"key: %u %s", (unsigned)(keyCode), pressed ? "ON" : "OFF");
    // }
  };
}

} // namespace Keyboard
