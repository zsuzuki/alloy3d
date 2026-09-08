//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#include <alloy3d/application.h>
#include <algorithm>
#include <array>
#include <alloy3d/camera.h>
#include <cmath>
#include <format>
#include <alloy3d/game_pad.h>
#include <iostream>
#include <alloy3d/keyboard.h>
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

constexpr float GridHalfSize          = 10.0f;
constexpr float GridStep              = 1.0f;
constexpr float ModelScale            = 1.0f;
constexpr float MoveSpeed             = 4.0f;
constexpr float CameraDist            = 18.0f;
constexpr float CameraTurn            = 2.2f;
constexpr float DeadZone              = 0.15f;
constexpr float CubeJumpBlendDuration = 0.35f;

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
class MainLoop : public alloy3d::ApplicationLoop
{
  bool                       shadowEnabled_ = true, shadowChanged_ = true, onKeyH_ = false;
  alloy3d::gamepad::PadState padState_{};
  alloy3d::gamepad::PadState padStateUpdate_{};
  bool              onKeyW_ = false;
  bool              onKeyA_ = false;
  bool              onKeyS_ = false;
  bool              onKeyD_ = false;
  bool onKeyO_ = false, toggleProjection_ = false, fitRequested_ = false, resetCamera_ = true;
  alloy3d::Bounds3D          sceneBounds_;
  simd_float3                cameraTarget_   = {0, 1.7f, 0};
  float                      cameraDistance_ = CameraDist;
  bool                       onKeyI_        = false;
  bool                       instanceDemo_  = false;
  bool                                                 onKeyM_ = false, materialDemo_ = false;
  float                                                materialTime_ = 0;
  std::array<alloy3d::ApplicationContext::ModelPtr, 7> materialModels_;
  bool                       releaseMemory_ = false;
  std::array<bool, 4> cameraKeys_{}; // left, right, up, down

  double windowWidth_  = WindowWidth;
  double windowHeight_ = WindowHeight;

  alloy3d::ApplicationContext::ModelPtr cube_;
  alloy3d::ApplicationContext::ModelPtr cubeJump_;
  alloy3d::ApplicationContext::ModelPtr animatedModel_;
  std::array<alloy3d::ApplicationContext::ModelPtr, 3> testModels_;
  float testAnimationTime_ = 0.0f;
  std::array<alloy3d::ApplicationContext::ModelPtr, 3> sharedModels_;
  std::array<alloy3d::ModelInstance, 81>               placements_;

  simd_float3 modelPosition_ = simd_make_float3(3.0f, 0.0f, 5.0f);
  float       modelYaw_      = 0.0f;
  float       cameraYaw_      = 0.15f;
  float       cameraPitch_    = 0.32f;
  float       animationTime_  = 0.0f;
  float       cubeJumpTime_               = 0.0f;
  float       cubeJumpBlendTime_          = 0.0f;
  std::size_t animationIndex_             = 0;
  std::size_t cubeJumpAnimationIndex_     = 0;
  std::size_t cubeJumpNextAnimationIndex_ = 0;

  bool initializedModelAnimation_    = false;
  bool initializedCubeJumpAnimation_ = false;
  bool blendingCubeJumpAnimation_    = false;

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

    alloy3d::gamepad::InitGamePad(
        [&](const alloy3d::gamepad::PadState &state, alloy3d::gamepad::UpdateType)
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
    cubeJump_.reset();
    animatedModel_.reset();
    for (auto &model : testModels_) model.reset();
    for (auto &model : materialModels_)
      model.reset();
    for (auto &model : sharedModels_)
      model.reset();
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

  void Start(alloy3d::ApplicationContext &ctx) override
  {
    cube_          = ctx.LoadModel("models/sample_cube.glb");
    cubeJump_      = ctx.LoadModel("models/cube_jump.glb");
    animatedModel_ = ctx.LoadModel("models/animated_bouncer.glb");
    const std::array<int, 3> jointCounts = {25, 100, 200};
    for (std::size_t i = 0; i < testModels_.size(); ++i)
      testModels_[i] = ctx.LoadModel(std::format("models/rig_{}.glb", jointCounts[i]));

    const std::array<const char *, 7> materialNames = {"opaque_alpha",
                                                       "mask_checker",
                                                       "blend_red",
                                                       "blend_blue",
                                                       "single_sided",
                                                       "double_sided",
                                                       "unlit"};
    for (size_t i = 0; i < materialModels_.size(); ++i)
      materialModels_[i] = ctx.LoadModel(std::format("models/{}.glb", materialNames[i]));

    for (auto &model : sharedModels_)
      model = ctx.CreateModelInstance(testModels_[0]);
    for (std::size_t i = 0; i < placements_.size(); ++i)
    {
      auto &instance    = placements_[i];
      instance.position = {float(i % 9) * 1.4f - 5.6f, .35f, float(i / 9) * 1.2f - 5.0f};
      instance.scale    = {.45f, .65f, .45f};
      instance.color    = {.5f + .05f * float(i % 9), .85f, 1, 1};
    }
    alloy3d::DirectionalLight3D light;
    light.direction = {-.35f, -.8f, -.45f};
    light.color     = {1, .96f, .9f};
    light.ambient   = .25f;
    light.diffuse   = .75f;
    ctx.SetDirectionalLight3D(light);
    ctx.SetTextFontSize(28.0f);
    lastFrameTime_ = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
  }

  void Update(alloy3d::ApplicationContext &ctx) override
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
    UpdateCubeJump(deltaTime);
    UpdateAnimatedModel(pad, deltaTime);
    UpdateCamera(ctx, pad, deltaTime);

    if (shadowChanged_)
    {
      alloy3d::DirectionalShadow3D shadow;
      shadow.enabled = shadowEnabled_;
      shadow.bounds  = {{-11, -.1f, -11}, {11, 8, 11}};
      ctx.SetDirectionalShadow3D(shadow);
      shadowChanged_ = false;
    }
    if (releaseMemory_)
    {
      ctx.ReleaseUnusedMemory();
      releaseMemory_ = false;
    }
    sceneBounds_ = {};
    ctx.DrawPlane3D(simd_make_float3(-10, -.02f, -10),
                    simd_make_float3(10, -.02f, -10),
                    simd_make_float3(10, -.02f, 10),
                    simd_make_float3(-10, -.02f, 10),
                    simd_make_float4(.18f, .20f, .23f, 1));
    DrawGrid(ctx);
    if (materialDemo_)
      DrawMaterialDemo(ctx, deltaTime);
    else if (instanceDemo_)
      DrawInstanceDemo(ctx, deltaTime);
    else
    {
      DrawModels(ctx);
      DrawTestModels(ctx, deltaTime);
      DrawCubeJumpLabel(ctx);
      DrawAnimationLabel(ctx);
    }
    if (fitRequested_)
    {
      if (sceneBounds_.isValid())
      {
        auto &camera = ctx.GetCamera();
        camera.fitBounds(sceneBounds_, 1.15f);
        cameraTarget_   = camera.getLookAt();
        cameraDistance_ = simd_length(camera.getEyePosition() - cameraTarget_);
      }
      fitRequested_ = false;
    }
    ctx.Print(ctx.GetCamera().getProjectionMode() == alloy3d::ProjectionMode::Orthographic
                  ? "O: Orthographic   |   F: fit models   |   I: instances   |   M: materials"
                  : "O: Perspective   |   F: fit models   |   I: instances   |   M: materials",
              20,
              58);
    ctx.Print(shadowEnabled_ ? "WASD: move   |   Arrows: orbit   |   R: reset   |   H: shadows ON"
                             : "WASD: move   |   Arrows: orbit   |   R: reset   |   H: shadows OFF",
              20,
              20);
  }

private:
  void FetchKeyboard()
  {
    alloy3d::keyboard::Fetch(
        [&](alloy3d::keyboard::KeyCode code, bool press)
        {
          switch (code)
          {
          case alloy3d::keyboard::KeyCode::W:
            onKeyW_ = press;
            break;
          case alloy3d::keyboard::KeyCode::A:
            onKeyA_ = press;
            break;
          case alloy3d::keyboard::KeyCode::S:
            onKeyS_ = press;
            break;
          case alloy3d::keyboard::KeyCode::D:
            onKeyD_ = press;
            break;
          case alloy3d::keyboard::KeyCode::LEFT:
            cameraKeys_[0] = press;
            break;
          case alloy3d::keyboard::KeyCode::RIGHT:
            cameraKeys_[1] = press;
            break;
          case alloy3d::keyboard::KeyCode::UP:
            cameraKeys_[2] = press;
            break;
          case alloy3d::keyboard::KeyCode::DOWN:
            cameraKeys_[3] = press;
            break;
          case alloy3d::keyboard::KeyCode::I:
            if (press && !onKeyI_)
            {
              instanceDemo_  = !instanceDemo_;
              materialDemo_  = false;
              releaseMemory_ = true;
            }
            onKeyI_ = press;
            break;
          case alloy3d::keyboard::KeyCode::H:
            if (press && !onKeyH_)
            {
              shadowEnabled_ = !shadowEnabled_;
              shadowChanged_ = true;
            }
            onKeyH_ = press;
            break;
          case alloy3d::keyboard::KeyCode::M:
            if (press && !onKeyM_)
            {
              materialDemo_  = !materialDemo_;
              instanceDemo_  = false;
              fitRequested_  = true;
              releaseMemory_ = true;
            }
            onKeyM_ = press;
            break;
          case alloy3d::keyboard::KeyCode::O:
            if (press && !onKeyO_)
              toggleProjection_ = !toggleProjection_;
            onKeyO_ = press;
            break;
          case alloy3d::keyboard::KeyCode::F:
            if (press)
              fitRequested_ = true;
            break;
          case alloy3d::keyboard::KeyCode::R:
            if (press)
              resetCamera_ = true;
            break;
          default:
            break;
          }
        });
  }

  void UpdateAnimationSelection(alloy3d::gamepad::PadState &pad)
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

  void UpdateAnimatedModel(const alloy3d::gamepad::PadState &pad, float deltaTime)
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
      const auto forward = simd_make_float3(-std::sin(cameraYaw_), 0.0f, -std::cos(cameraYaw_));
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

  void UpdateCubeJump(float deltaTime)
  {
    if (!cubeJump_ || !cubeJump_->IsLoaded() || cubeJump_->AnimationCount() == 0)
    {
      return;
    }

    if (!initializedCubeJumpAnimation_)
    {
      cubeJumpAnimationIndex_     = 0;
      cubeJumpNextAnimationIndex_ = 0;
      cubeJumpTime_               = 0.0f;
      cubeJumpBlendTime_          = 0.0f;
      initializedCubeJumpAnimation_ = true;
      cubeJump_->SetAnimation(cubeJumpAnimationIndex_);
    }

    const auto animationCount = cubeJump_->AnimationCount();
    if (animationCount == 1)
    {
      const auto duration = cubeJump_->AnimationDuration(cubeJumpAnimationIndex_);
      cubeJumpTime_ += deltaTime;
      if (duration > 0.0f)
      {
        cubeJumpTime_ = std::fmod(cubeJumpTime_, duration);
      }
      cubeJump_->SetAnimationTime(cubeJumpTime_);
      return;
    }

    if (blendingCubeJumpAnimation_)
    {
      cubeJumpBlendTime_ += deltaTime;
      const auto blendWeight = std::clamp(cubeJumpBlendTime_ / CubeJumpBlendDuration, 0.0f, 1.0f);
      if (blendWeight >= 1.0f)
      {
        blendingCubeJumpAnimation_ = false;
        cubeJumpAnimationIndex_    = cubeJumpNextAnimationIndex_;
        cubeJumpTime_              = cubeJumpBlendTime_;
        cubeJump_->SetAnimation(cubeJumpAnimationIndex_);
        cubeJump_->SetAnimationTime(cubeJumpTime_);
        return;
      }

      cubeJump_->SetAnimationBlend(cubeJumpAnimationIndex_,
                                   cubeJumpTime_,
                                   cubeJumpNextAnimationIndex_,
                                   cubeJumpBlendTime_,
                                   blendWeight);
      return;
    }

    const auto duration = cubeJump_->AnimationDuration(cubeJumpAnimationIndex_);
    cubeJumpTime_ += deltaTime;
    if (duration <= 0.0f)
    {
      cubeJumpTime_ = 0.0f;
      cubeJumpAnimationIndex_ = (cubeJumpAnimationIndex_ + 1) % animationCount;
      cubeJump_->SetAnimation(cubeJumpAnimationIndex_);
      cubeJump_->SetAnimationTime(cubeJumpTime_);
      return;
    }

    if (cubeJumpTime_ >= duration)
    {
      cubeJumpTime_               = std::max(0.0f, duration - 0.0001f);
      cubeJumpNextAnimationIndex_ = (cubeJumpAnimationIndex_ + 1) % animationCount;
      cubeJumpBlendTime_          = 0.0f;
      blendingCubeJumpAnimation_  = true;
      cubeJump_->SetAnimationBlend(cubeJumpAnimationIndex_,
                                   cubeJumpTime_,
                                   cubeJumpNextAnimationIndex_,
                                   cubeJumpBlendTime_,
                                   0.0f);
      return;
    }

    cubeJump_->SetAnimationTime(cubeJumpTime_);
  }

  void DrawCubeJumpLabel(alloy3d::ApplicationContext &ctx)
  {
    if (!cubeJump_ || !cubeJump_->IsLoaded())
    {
      return;
    }

    const auto animationCount = cubeJump_->AnimationCount();
    if (animationCount == 0)
    {
      return;
    }

    const auto labelPosition = simd_make_float3(0.0f, 0.2f, 6.5f);
    const auto labelColor    = simd_make_float4(0.45f, 0.95f, 1.0f, 1.0f);
    const auto label = blendingCubeJumpAnimation_
                           ? std::format("{} -> {} {:.0f}%",
                                         cubeJump_->AnimationName(cubeJumpAnimationIndex_),
                                         cubeJump_->AnimationName(cubeJumpNextAnimationIndex_),
                                         std::clamp(cubeJumpBlendTime_ / CubeJumpBlendDuration, 0.0f, 1.0f) * 100.0f)
                           : std::format("{} ({}/{})",
                                         cubeJump_->AnimationName(cubeJumpAnimationIndex_),
                                         cubeJumpAnimationIndex_ + 1,
                                         animationCount);
    ctx.DrawText3D(label,
                   labelPosition,
                   0.3f,
                   labelColor,
                   alloy3d::TextAlign3D::CenterBottom);
  }

  void UpdateCamera(alloy3d::ApplicationContext &ctx, const alloy3d::gamepad::PadState &pad, float deltaTime)
  {
    cameraYaw_ += (ApplyDeadZone(pad.rightX) + float(cameraKeys_[1]) - float(cameraKeys_[0])) * CameraTurn * deltaTime;
    cameraPitch_ += (ApplyDeadZone(pad.rightY) + float(cameraKeys_[2]) - float(cameraKeys_[3])) * CameraTurn * deltaTime;
    cameraPitch_ = std::clamp(cameraPitch_, 0.1f, 0.8f);

    // Orbit the exhibition or the bounds selected by F.
    const auto aspect = static_cast<float>(std::max(1.0, windowWidth_) / std::max(1.0, windowHeight_));
    auto      &camera = ctx.GetCamera();
    if (resetCamera_)
    {
      cameraYaw_      = .15f;
      cameraPitch_    = .32f;
      cameraTarget_   = {0, 1.7f, 0};
      cameraDistance_ = CameraDist * std::max(1.f, 1.6f / aspect);
      camera.buildPerspective(.785398163f, aspect, .1f, 100.f);
      resetCamera_ = false;
    }
    camera.setAspectRatio(aspect);
    if (toggleProjection_)
    {
      if (camera.getProjectionMode() == alloy3d::ProjectionMode::Orthographic)
      {
        // Preserve apparent size at the orbit target, including after an orthographic fit.
        const float distance =
            camera.getOrthographicHeight() / (2 * std::tan(camera.getFieldOfView() / 2));
        const float shift = distance - cameraDistance_;
        const float near  = std::max(.001f, camera.getNearPlane() + shift);
        camera.buildPerspective(camera.getFieldOfView(),
                                aspect,
                                near,
                                std::max(near + .001f, camera.getFarPlane() + shift));
        cameraDistance_ = distance;
      }
      else
        camera.buildOrthographic(2 * cameraDistance_ * std::tan(camera.getFieldOfView() / 2),
                                 aspect,
                                 camera.getNearPlane(),
                                 camera.getFarPlane());
      toggleProjection_ = false;
    }
    const auto distance           = cameraDistance_;
    const auto look               = cameraTarget_;
    const auto horizontalDistance = distance * std::cos(cameraPitch_);
    const auto eye = look + simd_make_float3(
        std::sin(cameraYaw_) * horizontalDistance,
        std::sin(cameraPitch_) * distance,
        std::cos(cameraYaw_) * horizontalDistance);
    const auto up   = simd_make_float3(0.0f, 1.0f, 0.0f);

    ctx.GetCamera().buildModelView(eye, look, up);
  }

  void DrawGrid(alloy3d::ApplicationContext &ctx)
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

  void IncludePlacement(const alloy3d::Bounds3D &bounds, simd_float3 position, simd_float3 rotation,
                        simd_float3 scale)
  {
    const auto q      = simd_mul(simd_mul(simd_quaternion(rotation.x, simd_make_float3(1, 0, 0)),
                                          simd_quaternion(rotation.y, simd_make_float3(0, 1, 0))),
                                 simd_quaternion(rotation.z, simd_make_float3(0, 0, 1)));
    auto       matrix = simd_matrix4x4(q);
    for (int i = 0; i < 3; ++i)
      matrix.columns[i] *= scale[i];
    matrix.columns[3] = simd_make_float4(position, 1);
    sceneBounds_.include(bounds.transformed(matrix));
  }

  void DrawModel(alloy3d::ApplicationContext                 &ctx,
                 const alloy3d::ApplicationContext::ModelPtr &model, simd_float3 position,
                 simd_float3 rotation, simd_float3 scale, simd_float4 color = {1, 1, 1, 1})
  {
    ctx.DrawModel3D(model, position, rotation, scale, color);
    if (fitRequested_)
    {
      alloy3d::Bounds3D bounds;
      if (model->GetBounds(bounds))
        IncludePlacement(bounds, position, rotation, scale);
    }
  }

  void DrawModels(alloy3d::ApplicationContext &ctx)
  {
    if (cube_ && cube_->IsLoaded())
    {
      DrawModel(ctx,
                cube_,
                simd_make_float3(-3.0f, 0.0f, 5.0f),
                simd_make_float3(0.0f, 0.0f, 0.0f),
                simd_make_float3(0.65f, 0.65f, 0.65f),
                simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f));
    }

    if (cubeJump_ && cubeJump_->IsLoaded())
    {
      DrawModel(ctx,
                cubeJump_,
                simd_make_float3(0.0f, 0.0f, 5.0f),
                simd_make_float3(0.0f, 0.0f, 0.0f),
                simd_make_float3(0.65f, 0.65f, 0.65f),
                simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f));
    }

    if (animatedModel_ && animatedModel_->IsLoaded())
    {
      DrawModel(ctx,
                animatedModel_,
                modelPosition_,
                simd_make_float3(0.0f, modelYaw_, 0.0f),
                simd_make_float3(ModelScale, ModelScale, ModelScale),
                simd_make_float4(1.0f, 1.0f, 1.0f, 1.0f));
    }
  }

  void DrawAnimationLabel(alloy3d::ApplicationContext &ctx)
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
    const auto labelPosition = modelPosition_ + simd_make_float3(0.0f, 0.2f, 1.5f);
    const auto labelColor    = simd_make_float4(1.0f, 0.92f, 0.35f, 1.0f);
    ctx.DrawText3D(animatedModel_->AnimationName(labelAnimationIndex),
                   labelPosition,
                   0.3f,
                   labelColor,
                   alloy3d::TextAlign3D::CenterBottom);
  }

  void DrawMaterialDemo(alloy3d::ApplicationContext &ctx, float deltaTime)
  {
    materialTime_ = std::fmod(materialTime_ + deltaTime, 100.f);
    auto draw =
        [&](size_t model, simd_float3 position, simd_float3 rotation = simd_make_float3(0, 0, 0))
    {
      if (materialModels_[model] && materialModels_[model]->IsLoaded())
        DrawModel(ctx, materialModels_[model], position, rotation, simd_make_float3(2, 2, 2));
    };
    draw(0, simd_make_float3(-6, 2, 0));
    draw(1, simd_make_float3(-3, 2, 0));
    // Near plane is deliberately submitted first; transparent parts are sorted at render time.
    draw(2, simd_make_float3(-.3f, 2, .4f));
    draw(3, simd_make_float3(.3f, 2, 0));
    draw(4, simd_make_float3(3, 2, 0), simd_make_float3(0, materialTime_, 0));
    draw(5, simd_make_float3(6, 2, 0), simd_make_float3(0, materialTime_, 0));
    draw(4, simd_make_float3(-2, 1, 4), simd_make_float3(0, .9f * std::sin(materialTime_), 0));
    draw(6, simd_make_float3(2, 1, 4), simd_make_float3(0, .9f * std::sin(materialTime_), 0));
    const std::array<const char *, 5> labels = {"OPAQUE / alpha ignored",
                                                "MASK / cutout",
                                                "BLEND / sorted",
                                                "Single sided",
                                                "Double sided"};
    for (size_t i = 0; i < labels.size(); ++i)
      ctx.DrawText3D(labels[i],
                     simd_make_float3(float(i) * 3 - 6, 3.5f, 0),
                     .25f,
                     simd_make_float4(.6f, .9f, 1, 1),
                     alloy3d::TextAlign3D::CenterBottom);
    ctx.DrawText3D("Lit",
                   simd_make_float3(-2, 2.5f, 4),
                   .3f,
                   simd_make_float4(1, 1, 1, 1),
                   alloy3d::TextAlign3D::CenterBottom);
    ctx.DrawText3D("Unlit",
                   simd_make_float3(2, 2.5f, 4),
                   .3f,
                   simd_make_float4(1, 1, 1, 1),
                   alloy3d::TextAlign3D::CenterBottom);
    ctx.Print("Material gallery: rotating panels show back faces and lighting", 20, 96);
  }

  void DrawInstanceDemo(alloy3d::ApplicationContext &ctx, float deltaTime)
  {
    testAnimationTime_ = std::fmod(testAnimationTime_ + deltaTime, 12.0f);
    const auto &model  = testModels_[0];
    if (model && model->IsLoaded())
    {
      if (model->CurrentAnimationIndex() != 0)
        model->SetAnimation(0);
      model->SetAnimationTime(testAnimationTime_);
      ctx.DrawModelInstances3D(model, placements_);
      if (fitRequested_)
      {
        alloy3d::Bounds3D bounds;
        if (model->GetBounds(bounds))
          for (const auto &placement : placements_)
            IncludePlacement(bounds, placement.position, placement.rotation, placement.scale);
      }
    }
    for (std::size_t i = 0; i < sharedModels_.size(); ++i)
    {
      const auto &copy = sharedModels_[i];
      if (!copy || !copy->IsLoaded())
        continue;
      copy->SetAnimationBlend(
          0, testAnimationTime_ * (1 + .2f * i), 1, testAnimationTime_ + .7f * i, float(i) * .5f);
      DrawModel(ctx, copy, {float(i) * 3 - 3, .5f, 6}, {0, 0, 0}, {.8f, .8f, .8f});
    }
    ctx.Print("81 instances: shared pose   |   Front row: 3 shared models, independent animation",
              20,
              96);
  }

  void DrawTestModels(alloy3d::ApplicationContext &ctx, float deltaTime)
  {
    testAnimationTime_ = std::fmod(testAnimationTime_ + deltaTime, 12.0f);
    const std::array<const char *, 3> labels = {
        "25 joints / Wave", "100 joints / Lift", "200 joints / Blend"};
    for (std::size_t i = 0; i < testModels_.size(); ++i)
    {
      const auto &model = testModels_[i];
      const float x = (static_cast<float>(i) - 1.0f) * 5.0f;
      if (model && model->IsLoaded())
      {
        if (i == 2)
          model->SetAnimationBlend(0, testAnimationTime_, 1, testAnimationTime_,
                                   0.5f - 0.5f * std::cos(testAnimationTime_ * 0.523598776f));
        else
        {
          if (model->CurrentAnimationIndex() != i) model->SetAnimation(i);
          model->SetAnimationTime(testAnimationTime_);
        }
        DrawModel(ctx,
                  model,
                  simd_make_float3(x, 2.0f, -2.0f),
                  simd_make_float3(0, 0, 0),
                  simd_make_float3(1, 1, 1));
      }
      ctx.DrawText3D(model && model->IsLoaded() ? labels[i] : "Model failed to load",
                     simd_make_float3(x, 4.9f, -2.0f), 0.35f,
                     simd_make_float4(0.45f, 0.85f, 1.0f, 1.0f), alloy3d::TextAlign3D::CenterBottom);
    }
  }
};

//
//
//
int main(int argc, char **argv)
{
  auto mainloop = std::make_shared<MainLoop>();
  alloy3d::LaunchApplication(mainloop);

  return 0;
}

//
