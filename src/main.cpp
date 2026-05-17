//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include <app_launch.h>
#include <algorithm>
#include <camera.h>
#include <cmath>
#include <format>
#include <game_pad.h>
#include <iostream>
#include <keyboard.h>
#include <memory>
#include <mutex>
#include <simd/quaternion.h>
#include <simd/vector_make.h>
#include <simd/vector_types.h>
#include <time.h>

namespace
{
//
constexpr double WindowWidth  = 1600.0;
constexpr double WindowHeight = 800.0;

constexpr float GridHalfSize = 20.0f;
constexpr float GridStep     = 1.0f;
constexpr float ModelScale   = 1.5f;
constexpr float MoveSpeed    = 4.0f;
constexpr float CameraDist   = 7.0f;
constexpr float CameraHeight = 5.0f;
constexpr float CameraTurn   = 2.2f;
constexpr float DeadZone     = 0.15f;

constexpr std::size_t AnimationNameOffset = 3;

float ApplyDeadZone(float value)
{
  return std::abs(value) < DeadZone ? 0.0f : value;
}

float ClampLength(float &x, float &y)
{
  auto len = std::sqrt(x * x + y * y);
  if (len > 1.0f)
  {
    x /= len;
    y /= len;
    return 1.0f;
  }
  return len;
}
} // namespace

//
//
//
class MainLoop : public ApplicationLoop
{
  GamePad::PadState padState_{};
  GamePad::PadState padStateUpdate_{};
  bool              onKeyW_ = false;
  bool              onKeyA_ = false;
  bool              onKeyS_ = false;
  bool              onKeyD_ = false;

  double windowWidth_  = WindowWidth;
  double windowHeight_ = WindowHeight;

  ApplicationContext::ModelPtr cube_;
  ApplicationContext::ModelPtr animatedModel_;

  simd_float3 modelPosition_ = simd_make_float3(0.0f, 0.0f, 10.0f);
  float       modelYaw_      = 0.0f;
  float       cameraYaw_      = 0.0f;
  float       cameraPitch_    = 0.18f;
  float       animationTime_  = 0.0f;
  std::size_t animationIndex_ = 0;

  bool initializedModelAnimation_ = false;

  std::mutex padLock_;
  uint64_t   lastFrameTime_ = 0;

public:
  MainLoop()           = default;
  ~MainLoop() override = default;

  [[nodiscard]] const char *GetApplicationName() const override { return "Alloy3D Viewer"; }

  bool InitialWindowSize(double &width, double &height, bool &border) override
  {
    std::cout << std::format("Default window size: {} x {}\n", width, height);
    width  = windowWidth_;
    height = windowHeight_;

    GamePad::InitGamePad(
        [&](const GamePad::PadState &state, GamePad::UpdateType)
        {
          std::lock_guard guard{padLock_};
          padState_ = state;
        },
        [&](uint64_t hash)
        {
          std::cout << std::format("Connect GamePad: {:x}\n", hash);
        },
        [&](uint64_t hash)
        {
          std::lock_guard guard{padLock_};
          if (padState_.checkHash(hash))
          {
            padState_.enabled = false;
            std::cout << std::format("Disconnect GamePad: {:x}\n", hash);
          }
        });

    return true;
  }

  void WillCloseWindow() override
  {
    cube_.reset();
    animatedModel_.reset();
    std::cout << std::format("To Close Window\n");
  }

  void WindowClearColor(double &red, double &green, double &blue, double &alpha) override
  {
    std::cout << std::format("Default clear color: R={} G={} B={} A={}\n", red, green, blue, alpha);
    red   = 0.02;
    green = 0.025;
    blue  = 0.035;
    alpha = 1.0;
  }

  void ResizeWindow(double width, double height) override
  {
    windowWidth_  = width;
    windowHeight_ = height;
  }

  void DroppedFiles(const std::vector<std::string> &paths) override
  {
    std::cout << std::format("Dropped files: {}\n", paths.size());
    for (const auto &path : paths)
    {
      std::cout << "  " << path << "\n";
    }
  }

  void Start(ApplicationContext &ctx) override
  {
    cube_          = ctx.LoadModel("models/sample_cube.glb");
    animatedModel_ = ctx.LoadModel("models/animated_bouncer.glb");

    ctx.SetTextFontSize(28.0f);
    lastFrameTime_ = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
  }

  void Update(ApplicationContext &ctx) override
  {
    const auto nowTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    const auto deltaTime =
        lastFrameTime_ == 0 ? 0.0f : static_cast<float>((nowTime - lastFrameTime_) / 1000000000.0);
    lastFrameTime_ = nowTime;

    FetchKeyboard();

    auto &pad = padStateUpdate_;
    {
      std::lock_guard guard{padLock_};
      padState_.fetch(pad);
    }

    UpdateAnimationSelection(pad);
    UpdateAnimatedModel(pad, deltaTime);
    UpdateCamera(ctx, pad, deltaTime);

    ctx.SetLight3D(simd_make_float3(-0.35f, -0.8f, -0.45f), 0.35f, 0.85f);
    DrawGrid(ctx);
    DrawModels(ctx);
    DrawAnimationLabel(ctx);

  }

private:
  void FetchKeyboard()
  {
    Keyboard::Fetch(
        [&](Keyboard::KeyCode code, bool press)
        {
          switch (code)
          {
          case Keyboard::KeyCode::W:
            onKeyW_ = press;
            break;
          case Keyboard::KeyCode::A:
            onKeyA_ = press;
            break;
          case Keyboard::KeyCode::S:
            onKeyS_ = press;
            break;
          case Keyboard::KeyCode::D:
            onKeyD_ = press;
            break;
          default:
            break;
          }
        });
  }

  void UpdateAnimationSelection(GamePad::PadState &pad)
  {
    if (!animatedModel_ || !animatedModel_->IsLoaded())
    {
      return;
    }

    const auto animationCount = animatedModel_->AnimationCount();
    if (animationCount == 0)
    {
      return;
    }

    if (!initializedModelAnimation_)
    {
      animationIndex_              = 0;
      animationTime_               = 0.0f;
      initializedModelAnimation_ = true;
      animatedModel_->SetAnimation(animationIndex_);
    }

    if (pad.buttonUp.On())
    {
      animationIndex_ = (animationIndex_ + animationCount - 1) % animationCount;
      animationTime_  = 0.0f;
      animatedModel_->SetAnimation(animationIndex_);
    }
    else if (pad.buttonDown.On())
    {
      animationIndex_ = (animationIndex_ + 1) % animationCount;
      animationTime_  = 0.0f;
      animatedModel_->SetAnimation(animationIndex_);
    }
  }

  void UpdateAnimatedModel(const GamePad::PadState &pad, float deltaTime)
  {
    float moveX = -ApplyDeadZone(pad.leftX);
    float moveY = ApplyDeadZone(pad.leftY);

    if (onKeyA_)
    {
      moveX -= 1.0f;
    }
    if (onKeyD_)
    {
      moveX += 1.0f;
    }
    if (onKeyW_)
    {
      moveY += 1.0f;
    }
    if (onKeyS_)
    {
      moveY -= 1.0f;
    }

    const auto moveLength = ClampLength(moveX, moveY);
    if (moveLength > 0.0f)
    {
      const auto forward = simd_make_float3(std::sin(cameraYaw_), 0.0f, std::cos(cameraYaw_));
      const auto right   = simd_make_float3(std::cos(cameraYaw_), 0.0f, -std::sin(cameraYaw_));
      const auto move    = forward * moveY + right * moveX;
      modelPosition_ += move * (MoveSpeed * deltaTime);
      modelYaw_ = std::atan2(move.x, move.z);
    }

    if (animatedModel_ && animatedModel_->IsLoaded() && animatedModel_->AnimationCount() > 0)
    {
      const auto duration = animatedModel_->CurrentAnimationDuration();
      animationTime_ += deltaTime;
      if (duration > 0.0f)
      {
        animationTime_ = std::fmod(animationTime_, duration);
      }
      animatedModel_->SetAnimationTime(animationTime_);
    }
  }

  void UpdateCamera(ApplicationContext &ctx, const GamePad::PadState &pad, float deltaTime)
  {
    cameraYaw_ += ApplyDeadZone(pad.rightX) * CameraTurn * deltaTime;
    cameraPitch_ += ApplyDeadZone(pad.rightY) * CameraTurn * deltaTime;
    cameraPitch_ = std::clamp(cameraPitch_, -0.35f, 0.8f);

    const auto horizontalDistance = CameraDist * std::cos(cameraPitch_);
    const auto eye = simd_make_float3(
        modelPosition_.x - std::sin(cameraYaw_) * horizontalDistance,
        modelPosition_.y + CameraHeight + std::sin(cameraPitch_) * CameraDist,
        modelPosition_.z - std::cos(cameraYaw_) * horizontalDistance);
    const auto look = modelPosition_ + simd_make_float3(0.0f, 1.4f, 0.0f);
    const auto up   = simd_make_float3(0.0f, 1.0f, 0.0f);

    ctx.GetCamera().buildModelView(eye, look, up);
  }

  void DrawGrid(ApplicationContext &ctx)
  {
    const auto lineColor = simd_make_float4(0.35f, 0.38f, 0.42f, 1.0f);
    const auto axisX     = simd_make_float4(0.75f, 0.25f, 0.25f, 1.0f);
    const auto axisZ     = simd_make_float4(0.25f, 0.45f, 0.85f, 1.0f);

    for (float i = -GridHalfSize; i <= GridHalfSize; i += GridStep)
    {
      auto colorZ = std::abs(i) < 0.001f ? axisZ : lineColor;
      auto colorX = std::abs(i) < 0.001f ? axisX : lineColor;
      ctx.DrawLine3D(simd_make_float3(-GridHalfSize, 0.0f, i),
                     simd_make_float3(GridHalfSize, 0.0f, i),
                     colorZ);
      ctx.DrawLine3D(simd_make_float3(i, 0.0f, -GridHalfSize),
                     simd_make_float3(i, 0.0f, GridHalfSize),
                     colorX);
    }
  }

  void DrawModels(ApplicationContext &ctx)
  {
    if (cube_ && cube_->IsLoaded())
    {
      ctx.DrawModel3D(cube_,
                      simd_make_float3(0.0f, 0.0f, 0.0f),
                      simd_make_float3(0.0f, 0.0f, 0.0f),
                      simd_make_float3(1.0f, 1.0f, 1.0f),
                      simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f));
    }

    if (animatedModel_ && animatedModel_->IsLoaded())
    {
      ctx.DrawModel3D(animatedModel_,
                      modelPosition_,
                      simd_make_float3(0.0f, modelYaw_, 0.0f),
                      simd_make_float3(ModelScale, ModelScale, ModelScale),
                      simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f));
    }
  }

  void DrawAnimationLabel(ApplicationContext &ctx)
  {
    if (!animatedModel_ || !animatedModel_->IsLoaded())
    {
      return;
    }

    const auto animationCount = animatedModel_->AnimationCount();
    if (animationCount == 0)
    {
      return;
    }

    const auto currentAnimationIndex = animatedModel_->CurrentAnimationIndex();
    const auto labelAnimationIndex   = (currentAnimationIndex + AnimationNameOffset) % animationCount;
    const auto labelPosition = modelPosition_ + simd_make_float3(0.0f, 3.2f, 0.0f);
    const auto labelColor    = simd_make_float4(1.0f, 0.92f, 0.35f, 1.0f);
    ctx.DrawText3D(animatedModel_->AnimationName(labelAnimationIndex),
                   labelPosition,
                   0.7f,
                   labelColor,
                   TextAlign3D::CenterBottom);
  }
};

//
//
//
int main(int argc, char **argv)
{
  auto mainloop = std::make_shared<MainLoop>();
  LaunchApplication(mainloop);

  return 0;
}

//
