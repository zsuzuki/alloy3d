//
// Copyright 2024 Y.Suzuki(wave.suzuki.z@gmail.com)
//
#pragma once
#include <alloy3d/render_options.h>

#include <alloy3d/lighting.h>
#include <alloy3d/model.h>
#include <alloy3d/model_instance.h>
#include <alloy3d/model_shader.h>
#include <alloy3d/model_texture.h>
#include <alloy3d/render_memory.h>
#include <alloy3d/sprite.h>
#include <memory>
#include <simd/vector_types.h>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace alloy3d
{

class CameraData;

enum class TextAlign3D
{
  LeftBottom = 0,
  CenterBottom,
  RightBottom,
};

//
class ApplicationContext
{

public:
  // Submit drawing and resource/animation changes from the application callbacks.
  // Concurrent rendering or mutation of a context/model is not supported.
  // Transient vertex storage grows on demand and reuses its peak capacity.
  ApplicationContext()          = default;
  virtual ~ApplicationContext() = default;

  // info
  virtual float ContentScale() const = 0;

  // Optional hooks for custom contexts; implemented by the bundled Metal host.
  virtual void SetTextCacheBudget(TextCacheBudget budget) {}
  virtual RenderMemoryStats GetRenderMemoryStats() const { return {}; }
  // Clear caches now and release vertex pages when next safe to reuse. Queued
  // draws remain valid. Does not unload models or wait synchronously for the GPU.
  virtual void ReleaseUnusedMemory() {}

  // text
  virtual void Print(std::string_view msg, float x, float y)                 = 0;
  virtual void SetTextColor(float red, float green, float blue, float alpha) = 0;
  virtual void SetTextFont(std::string_view fontName)                        = 0;
  virtual void SetTextFontSize(float fontSize)                               = 0;
  virtual void SetTextFontColor(float red, float green, float blue, float alpha) = 0;

  // 2D
  virtual void DrawLine(simd_float2 from, simd_float2 to, simd_float4 color)                    = 0;
  virtual void DrawRect(simd_float2 from, simd_float2 to, simd_float4 color)                    = 0;
  virtual void DrawRoundRect(simd_float2 from, simd_float2 to, float radius,
                             simd_float4 color)                                                 = 0;
  virtual void FillRect(simd_float2 from, simd_float2 to, simd_float4 color)                    = 0;
  virtual void FillRoundRect(simd_float2 from, simd_float2 to, float radius,
                             simd_float4 color)                                                 = 0;
  virtual void DrawPolygon(simd_float2 pos, float rad, float rot, int sides, simd_float4 color) = 0;
  virtual void FillPolygon(simd_float2 pos, float rad, float rot, int sides, simd_float4 color) = 0;

  using SpritePtr                                   = std::shared_ptr<Sprite>;
  virtual SpritePtr CreateSprite(std::string fname) = 0;
  virtual void      DrawSprite(SpritePtr spr)       = 0;

  // 3D
  virtual CameraData &GetCamera() = 0;

  // Compile once (e.g. Start), then reuse. Returns null with diagnostics on failure.
  // Source defines float3 alloy3dShade(ModelSurface s, float4 parameters).
  virtual ModelShaderPtr CreateModelShader(std::string_view source, std::string &diagnostics)
  {
    diagnostics = "Model surface shaders are unsupported by this context";
    return {};
  }
  // Persistent model draw state; handle and parameters are copied at submission.
  // Null restores built-in shading. Returns false for foreign/unsupported shaders
  // or non-finite parameters, leaving the previous state intact.
  virtual bool SetModelShader(ModelShaderPtr shader, simd_float4 parameters = {0, 0, 0, 0})
  {
    return !shader;
  }
  // Persistent model draw state, copied at submission (also for an instance batch).
  // Default strength is zero. Invalid settings throw without changing state.
  virtual bool SetModelHighlight3D(const ModelHighlight3D &highlight) { return false; }
  virtual bool SetModelMaterialDetail3D(const ModelMaterialDetail3D &detail) { return false; }
  virtual bool SetModelTransmission3D(const ModelTransmission3D &transmission) { return false; }

  // Transform base-color UVs, including MASK shadow coverage and custom surface UVs.
  // Identity by default. Invalid values throw without changing state in the bundled host.
  virtual bool SetModelTextureTransform3D(const ModelTextureTransform3D &transform) { return false; }
  // Per-draw base-color sampling, including MASK shadows. Default anisotropy is 1.
  virtual bool SetModelTextureSampling3D(const ModelTextureSampling3D &sampling) { return false; }
  virtual bool SetModelNormalMapping3D(const ModelNormalMapping3D &mapping) { return false; }

  // Direction the light travels, in world coordinates.
  virtual void SetLight3D(simd_float3 direction, float ambient, float diffuse) = 0;
  // Finite color/ambient/diffuse in [0,1]. Bundled host validates transactionally.
  virtual void SetDirectionalLight3D(const DirectionalLight3D &light)
  {
    SetLight3D(light.direction, light.ambient, light.diffuse);
  }
  // Returns false on unsupported custom contexts; bundled host throws on invalid settings.
  virtual bool SetDirectionalShadow3D(const DirectionalShadow3D &shadow) { return false; }
  // Persistent scene state, evaluated at render time like the directional light.
  // Returns false on unsupported contexts. Invalid settings throw without changing state.
  virtual bool SetFog3D(const Fog3D &fog) { return false; }
  virtual bool SetHemisphereLight3D(const HemisphereLight3D &light) { return false; }
  virtual void DrawLine3D(simd_float3 from, simd_float3 to, simd_float4 color) = 0;
  virtual void DrawTriangle3D(simd_float3 p0, simd_float3 p1, simd_float3 p2,
                              simd_float4 color)                               = 0;
  virtual void DrawPlane3D(simd_float3 p0, simd_float3 p1, simd_float3 p2, simd_float3 p3,
                           simd_float4 color)                                  = 0;
  virtual void DrawSphere3D(simd_float3 center, float radius, simd_float4 color,
                            int slices = 24, int stacks = 12)                  = 0;
  virtual void DrawBox3D(simd_float3 center, simd_float3 size, simd_float4 color) = 0;
  virtual void DrawBox3D(simd_float3 center, simd_float3 size, float rotationY,
                         simd_float4 color)                                      = 0;
  virtual void DrawBox3D(simd_float3 center, simd_float3 size, simd_float3 rotation,
                         simd_float4 color)                                      = 0;
  virtual void DrawCylinder3D(simd_float3 center, float radius, float height, simd_float4 color,
                              int segments = 24)                                 = 0;
  virtual void DrawCylinder3D(simd_float3 center, float radius, float height,
                              simd_float3 rotation, simd_float4 color,
                              int segments = 24)                                 = 0;
  virtual void DrawCone3D(simd_float3 center, float radius, float height, simd_float4 color,
                          int segments = 24)                                     = 0;
  virtual void DrawCone3D(simd_float3 center, float radius, float height, simd_float3 rotation,
                          simd_float4 color, int segments = 24)                  = 0;
  virtual void DrawCone3D(simd_float3 center, simd_float3 direction, float radius, float height,
                          simd_float4 color, int segments = 24)                  = 0;
  virtual void DrawText3D(std::string_view msg, simd_float3 position, float lineHeight,
                          simd_float4 color,
                          TextAlign3D align = TextAlign3D::LeftBottom)            = 0;
  virtual void DrawText3D(std::string_view msg, simd_float3 position, float lineHeight,
                          simd_float3 rotation, simd_float4 color,
                          TextAlign3D align = TextAlign3D::LeftBottom)            = 0;
  using ModelPtr                                  = std::shared_ptr<Model>;
  virtual ModelPtr LoadModel(std::string fname)   = 0;
  // Share immutable resources, copy the current pose, then animate independently.
  // The bundled host implements this; unsupported custom contexts return null.
  virtual ModelPtr CreateModelInstance(ModelPtr source) { return {}; }
  // Copies placements at submission; all use the model's pose at render time.
  // BLEND materials or faded placements use sorted individual draws in the bundled host.
  // Custom contexts retain correct behavior through this individual-draw fallback.
  virtual void DrawModelInstances3D(ModelPtr model, std::span<const ModelInstance> instances)
  {
    for (const auto &instance : instances)
      DrawModel3D(model, instance.position, instance.rotation, instance.scale, instance.color);
  }
  virtual void     DrawModel3D(ModelPtr model,
                               simd_float3 position,
                               simd_float3 rotation,
                               simd_float3 scale,
                               simd_float4 color = simd_float4{1.0f, 1.0f, 1.0f, 1.0f}) = 0;
};

//
class ApplicationLoop
{
public:
  ApplicationLoop()          = default;
  virtual ~ApplicationLoop() = default;

  // window title
  [[nodiscard]] virtual const char *GetApplicationName() const { return "Alloy3D"; };

  // Read once before creating the window and render pipelines.
  [[nodiscard]] virtual RenderOptions GetRenderOptions() const { return {}; }

  // start window size
  virtual bool InitialWindowSize(double &width, double &height, bool &border) { return true; }
  // to close window
  virtual void WillCloseWindow() {}
  // window clear color
  virtual void WindowClearColor(double &red, double &green, double &blue, double &alpha) {}
  // resize window
  virtual void ResizeWindow(double width, double height) {}
  // file drop
  virtual void DroppedFiles(const std::vector<std::string> &paths) {}

  // start after window initialization
  virtual void Start(ApplicationContext &ctx) {}
  // main update loop
  virtual void Update(ApplicationContext &ctx) = 0;
};

//
void LaunchApplication(std::shared_ptr<ApplicationLoop> apploop);

} // namespace alloy3d
